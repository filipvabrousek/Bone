//
//  BoneLayerPanel.swift
//  Bone-27
//
//  The Layer mode of the glass panel (.glassPanel): tap any element on screen
//  and edit the CALayer SwiftUI drew it into – opacity, corners, border,
//  shadow, 3D transform, blend mode, filters. ↑/↓ walk to the parent or the
//  first sublayer. Copy Swift gives the matching .tuneLayers(...) line.
//
//  Research / simulator use only — private Core Animation filters, never ship it.
//

#if canImport(UIKit)

import Combine
import SwiftUI
import UIKit

enum BonePanelMode: String, CaseIterable {
    /// Glass under the finger → glass inputs, anything else → its layer.
    case auto = "Auto"
    case glass = "Glass"
    case layer = "Layer"
}

/// The filter controls of the Layer mode, turned into a `.filters([...])` list.
struct BoneFilterKnobs: Equatable {
    var blur = 0.0
    var saturate = 1.0
    var hue = 0.0
    var brightness = 0.0
    var contrast = 1.0
    var invert = false
    var matrix = "none"

    var filters: [BoneFilter] {
        var f: [BoneFilter] = []
        if blur > 0 { f.append(.gaussianBlur(blur)) }
        if saturate != 1 { f.append(.colorSaturate(saturate)) }
        if hue != 0 { f.append(.colorHueRotate(hue)) }
        if brightness != 0 { f.append(.colorBrightness(brightness)) }
        if contrast != 1 { f.append(.colorContrast(contrast)) }
        if invert { f.append(.colorInvert) }
        if let m = BoneMatrixPreset.all.first(where: { $0.name == matrix }) { f.append(.colorMatrix(m.floats)) }
        return f
    }
}

final class BoneLayerEditor: ObservableObject {

    @Published private(set) var tuning = LayerTuning(values: [:])
    @Published var knobs = BoneFilterKnobs() { didSet { if knobs != oldValue { filtersChanged() } } }
    @Published private(set) var frame: CGRect = .null
    @Published private(set) var revision = 0

    private(set) weak var layer: CALayer?
    private weak var window: UIWindow?
    private weak var scene: UIWindowScene?
    private weak var excluded: UIWindow?
    private var center = CGPoint.zero
    private var className = ""
    private var snapshot: [String: Any] = [:]
    private(set) var generation = 0
    private var link: CADisplayLink?
    private var ticks = 0

    var title: String {
        guard let layer else { return "no layer" }
        return "\(type(of: layer)) · \(Int(frame.width))×\(Int(frame.height)) · \(LayerTarget.preset(for: layer).name)"
    }

    /// Inputs the panel holds – `.tuneLayers` leaves this layer alone meanwhile.
    func holds(_ l: CALayer) -> Bool { l === layer && !tuning.isEmpty }

    // MARK: Picking

    /// Visible layers without sublayers, back to front, in every window but the panel's.
    static func leaves(in scene: UIWindowScene?, excluding panel: UIWindow?) -> [(layer: CALayer, frame: CGRect, window: UIWindow)] {
        guard let scene else { return [] }
        var out: [(layer: CALayer, frame: CGRect, window: UIWindow)] = []
        let windows = scene.windows.filter { $0 !== panel && !$0.isHidden }.sorted { $0.windowLevel.rawValue < $1.windowLevel.rawValue }
        for w in windows {
            func walk(_ l: CALayer) {
                guard !l.isHidden, l.opacity > 0.01, !(l.delegate is BonePanelAnchorView) else { return }
                if l !== w.layer, LayerTarget.leaves.matches(l) {
                    let f = BoneGlassLayers.screenFrame(of: l, in: w)
                    if f.width > 1, f.height > 1 { out.append((layer: l, frame: f, window: w)) }
                }
                l.sublayers?.forEach(walk)
            }
            walk(w.layer)
        }
        return out
    }

    func select(_ l: CALayer, in w: UIWindow, scene: UIWindowScene?, excluding panel: UIWindow?) {
        layer = l
        window = w
        self.scene = scene
        excluded = panel
        className = String(describing: type(of: l))
        tuning = LayerTuning(values: [:])
        knobs = BoneFilterKnobs()
        snapshot = [:]
        for p in LayerProperty.allCases {
            if let key = p.key, let v = l.value(forKey: key) { snapshot[key] = v }
        }
        frame = BoneGlassLayers.screenFrame(of: l, in: w)
        center = CGPoint(x: frame.midX, y: frame.midY)
        startLink()
        revision &+= 1
    }

    func up() {
        guard let l = layer, let parent = l.superlayer, let w = window, parent !== w.layer else { return }
        select(parent, in: w, scene: scene, excluding: excluded)
    }

    func down() {
        guard let l = layer, let w = window,
              let child = l.sublayers?.first(where: { $0.bounds.width > 0 && $0.bounds.height > 0 }) ?? l.sublayers?.first else { return }
        select(child, in: w, scene: scene, excluding: excluded)
    }

    // MARK: Keeping the values

    private func startLink() {
        guard link == nil else { return }
        let l = CADisplayLink(target: BoneLinkTarget { [weak self] in self?.tick() }, selector: #selector(BoneLinkTarget.step))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 4, maximum: 10, preferred: 8)
        l.add(to: .main, forMode: .common)
        link = l
    }

    private func tick() {
        ticks += 1
        if let l = layer, let w = window, BoneGlassLayers.isAttached(l, to: w) {
            // still there
        } else if layer != nil || !tuning.isEmpty {
            // SwiftUI replaced it – the same kind of layer at the same place
            if let hit = Self.leaves(in: scene, excluding: excluded)
                .last(where: { $0.frame.contains(center) && String(describing: type(of: $0.layer)) == className }) {
                layer = hit.layer
                window = hit.window
            }
        }
        guard let l = layer, let w = window else { return }
        if !tuning.isEmpty { BoneLayerApplier.apply(tuning, to: l, generation: generation) }
        let f = BoneGlassLayers.screenFrame(of: l, in: w)
        if f != frame { frame = f }
        if ticks % 3 == 0 { revision &+= 1 }
    }

    // MARK: Editing

    func set(_ p: LayerProperty, _ v: LayerValue?) {
        tuning.values[p] = v
        if v == nil { restore(p) }
        applyNow()
    }

    func isChanged(_ p: LayerProperty) -> Bool { tuning.values[p] != nil }

    func reset(_ p: LayerProperty) {
        if p == .filters { knobs = BoneFilterKnobs() } else { set(p, nil) }
    }

    func resetAll() {
        let keys = Array(tuning.values.keys)
        tuning = LayerTuning(values: [:])
        keys.forEach(restore)
        knobs = BoneFilterKnobs()
        applyNow()
    }

    func apply(_ preset: LayerTuning) {
        for (p, v) in preset.values { tuning.values[p] = v }
        applyNow()
    }

    private func filtersChanged() {
        generation += 1
        let list = knobs.filters
        tuning.values[.filters] = list.isEmpty ? nil : .filters(list)
        applyNow()
    }

    private func restore(_ p: LayerProperty) {
        guard let l = layer, let key = p.key else { return }   // transform and filters: the applier undoes them
        l.setValue(snapshot[key], forKey: key)
    }

    private func applyNow() {
        if let l = layer { BoneLayerApplier.apply(tuning, to: l, generation: generation) }
        revision &+= 1
    }

    // MARK: Bindings

    static func defaultValue(_ p: LayerProperty) -> Double {
        switch p {
        case .scale, .scaleX, .scaleY: return 1
        case .perspective: return 500
        default: return 0
        }
    }

    static func range(_ p: LayerProperty) -> ClosedRange<Double> {
        switch p {
        case .opacity, .shadowOpacity: return 0...1
        case .cornerRadius, .shadowRadius: return 0...60
        case .borderWidth: return 0...20
        case .rotation, .rotationX, .rotationY: return -180...180
        case .scale, .scaleX, .scaleY: return 0...3
        case .translationX, .translationY: return -200...200
        case .perspective: return 100...2000
        default: return 0...1
        }
    }

    func number(_ p: LayerProperty) -> Binding<Double> {
        Binding(get: { [weak self] in
                    guard let self else { return 0 }
                    if let v = self.tuning.values[p]?.number { return v }
                    if let key = p.key, let n = self.layer?.value(forKey: key) as? NSNumber { return n.doubleValue }
                    return Self.defaultValue(p)
                },
                set: { [weak self] in self?.set(p, .number($0)) })
    }

    func toggle(_ p: LayerProperty) -> Binding<Bool> {
        Binding(get: { [weak self] in ((self?.number(p).wrappedValue) ?? 0) != 0 },
                set: { [weak self] in self?.set(p, .number($0 ? 1 : 0)) })
    }

    func color(_ p: LayerProperty) -> Binding<CGColor> {
        Binding(get: { [weak self] in
                    if case .color(let c)? = self?.tuning.values[p] { return c }
                    if let key = p.key, let v = self?.layer?.value(forKey: key), CFGetTypeID(v as CFTypeRef) == CGColor.typeID {
                        return v as! CGColor
                    }
                    return CGColor(gray: 0, alpha: 0)
                },
                set: { [weak self] in self?.set(p, .color($0)) })
    }

    func shadowOffset(_ axis: Int) -> Binding<Double> {
        Binding(get: { [weak self] in
                    var s = self?.layer?.shadowOffset ?? .zero
                    if case .size(let t)? = self?.tuning.values[.shadowOffset] { s = t }
                    return Double(axis == 0 ? s.width : s.height)
                },
                set: { [weak self] v in
                    guard let self else { return }
                    var s = self.layer?.shadowOffset ?? .zero
                    if case .size(let t)? = self.tuning.values[.shadowOffset] { s = t }
                    if axis == 0 { s.width = v } else { s.height = v }
                    self.set(.shadowOffset, .size(s))
                })
    }

    var blend: Binding<String> {
        Binding(get: { [weak self] in
                    if case .blend(let b)? = self?.tuning.values[.blendMode] { return b.rawValue }
                    return "none"
                },
                set: { [weak self] in self?.set(.blendMode, LayerBlend(rawValue: $0).map { .blend($0) }) })
    }

    // MARK: Copy Swift

    func swiftCode() -> String {
        guard let layer else { return "" }
        var parts: [String] = []
        for p in LayerProperty.allCases {
            guard let v = tuning.values[p] else { continue }
            let lit: String
            switch v {
            case .number(let d): lit = BoneSwiftLiteral.number(d)
            case .color(let c): lit = ".color(\(BoneSwiftLiteral.uiColor(c)))"
            case .size(let s): lit = ".size(\(BoneSwiftLiteral.number(s.width)), \(BoneSwiftLiteral.number(s.height)))"
            case .blend(let b): lit = ".blend(.\(b.rawValue))"
            case .filters(let f): lit = ".filters([\(f.map(\.swift).joined(separator: ", "))])"
            case .image: lit = ".image(UIImage(named: \"…\")!)"
            case .gravity(let g): lit = ".gravity(CALayerContentsGravity(rawValue: \"\(g.rawValue)\"))"
            }
            parts.append(".\(p.rawValue): \(lit)")
        }
        return parts.isEmpty ? "// nothing changed"
            : ".tuneLayers([\(parts.joined(separator: ", "))], where: \(LayerTarget.preset(for: layer).name))"
    }
}

// MARK: - Views

struct BoneLayerOutline: View {
    @ObservedObject var editor: BoneLayerEditor
    var body: some View {
        Canvas { ctx, _ in
            if !editor.frame.isNull {
                ctx.stroke(Path(roundedRect: editor.frame.insetBy(dx: -3, dy: -3), cornerRadius: 6), with: .color(.pink),
                           style: StrokeStyle(lineWidth: 2.5, dash: [6, 4]))
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct BoneLayerCard: View {
    @ObservedObject var model: BoneGlassPanelModel
    @ObservedObject var editor: BoneLayerEditor
    @State private var code: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Layer").font(.headline)
                    Text(editor.title).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
                if model.glassAtPoint {
                    Button { model.switchToGlass() } label: { Image(systemName: "drop.halffull") }
                }
                Button { editor.up() } label: { Image(systemName: "arrow.up.square") }
                Button { editor.down() } label: { Image(systemName: "arrow.down.square") }
                Button { model.startPicking() } label: { Image(systemName: "scope") }
                Button { model.atTop.toggle() } label: {
                    Image(systemName: model.atTop ? "rectangle.bottomhalf.inset.filled" : "rectangle.tophalf.inset.filled")
                }
                Button { model.close() } label: { Image(systemName: "xmark.circle.fill") }
            }
            .font(.title3)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip("Copy Swift", "doc.on.doc") {
                        let c = editor.swiftCode()
                        UIPasteboard.general.string = c
                        code = c
                    }
                    chip("Reset all", "arrow.uturn.backward") { editor.resetAll(); code = nil }
                    chip("outline", nil) { editor.apply(.outline) }
                    chip("tilt", nil) { editor.apply([.rotationX: 25, .rotationY: -20]) }
                    chip("glow", nil) { editor.apply([.shadowOpacity: 1, .shadowRadius: 12, .shadowColor: .color(.systemPink)]) }
                    chip("difference", nil) { editor.set(.blendMode, .blend(.difference)) }
                }
            }
            if let code {
                Text(code)
                    .font(.caption2.monospaced())
                    .textSelection(.enabled)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    section("Appearance")
                    numberRow(.opacity)
                    toggleRow(.hidden)
                    numberRow(.cornerRadius)
                    toggleRow(.masksToBounds)
                    colorRow(.backgroundColor)
                    numberRow(.borderWidth)
                    colorRow(.borderColor)
                    section("Shadow")
                    numberRow(.shadowOpacity)
                    numberRow(.shadowRadius)
                    colorRow(.shadowColor)
                    HStack(spacing: 6) {
                        label(.shadowOffset)
                        Text("x").font(.caption2)
                        Slider(value: editor.shadowOffset(0), in: -50...50)
                        Text("y").font(.caption2)
                        Slider(value: editor.shadowOffset(1), in: -50...50)
                    }
                    section("Transform (about the centre)")
                    ForEach([LayerProperty.rotation, .rotationX, .rotationY, .scale, .scaleX, .scaleY,
                             .translationX, .translationY, .perspective], id: \.self) { numberRow($0) }
                    section("Blend")
                    HStack {
                        label(.blendMode)
                        Spacer()
                        Picker("Blend", selection: editor.blend) {
                            Text("none").tag("none")
                            ForEach(LayerBlend.allCases, id: \.rawValue) { Text($0.rawValue).tag($0.rawValue) }
                        }
                    }
                    section("Filters")
                    knob("gaussianBlur", $editor.knobs.blur, 0...30)
                    knob("colorSaturate", $editor.knobs.saturate, 0...3)
                    knob("colorHueRotate", $editor.knobs.hue, -Double.pi...Double.pi)
                    knob("colorBrightness", $editor.knobs.brightness, -1...1)
                    knob("colorContrast", $editor.knobs.contrast, 0...3)
                    Toggle("colorInvert", isOn: $editor.knobs.invert).font(.caption.monospaced())
                    HStack {
                        Text("colorMatrix").font(.caption.monospaced())
                        Spacer()
                        Picker("Matrix", selection: $editor.knobs.matrix) {
                            Text("none").tag("none")
                            ForEach(BoneMatrixPreset.all) { Text($0.name).tag($0.name) }
                        }
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
    }

    // MARK: Rows

    private func section(_ title: String) -> some View {
        Text(title.uppercased()).font(.caption2.bold()).foregroundStyle(.secondary).padding(.top, 4)
    }

    private func label(_ p: LayerProperty) -> some View {
        HStack(spacing: 4) {
            Text(p.rawValue).font(.caption.monospaced())
            if editor.isChanged(p) {
                Button { editor.reset(p) } label: { Image(systemName: "arrow.uturn.backward.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.pink)
            }
        }
    }

    private func numberRow(_ p: LayerProperty) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                label(p)
                Spacer()
                TextField("", value: editor.number(p), format: BoneGlassPanelModel.numberFormat)
                    .font(.caption.monospaced())
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numbersAndPunctuation)
                    .frame(width: 92)
            }
            Slider(value: editor.number(p), in: BoneLayerEditor.range(p))
        }
    }

    private func toggleRow(_ p: LayerProperty) -> some View {
        HStack { label(p); Spacer(); Toggle("", isOn: editor.toggle(p)).labelsHidden() }
    }

    private func colorRow(_ p: LayerProperty) -> some View {
        HStack { label(p); Spacer(); ColorPicker("", selection: editor.color(p), supportsOpacity: true).labelsHidden() }
    }

    private func knob(_ name: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(name).font(.caption.monospaced())
                Spacer()
                Text(BoneSwiftLiteral.number(value.wrappedValue)).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

    private func chip(_ title: String, _ icon: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon) }
                Text(title)
            }
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.pink.opacity(0.15), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

#endif
