//
//  BoneGlassPanel.swift
//  Bone-27
//
//  A live editor for Liquid Glass. Add it once, to the app's root view:
//
//      WindowGroup { ContentView().glassPanel() }
//
//  Tap the floating drop button, then tap any glass on screen – your own
//  .glassEffect() views and system bars alike. Every input of its filters gets
//  a control (slider, toggle, colour, size, 4×5 colour matrix), including the
//  hidden ones SwiftUI never sets (purple). Changes go straight to the real
//  glass and are re-applied when SwiftUI rebuilds it.
//
//  Layer mode  (switch in the pick hint): tap ANY element and edit its CALayer –
//              see BoneLayerPanel.swift / .tuneLayers.
//  Probe       runs .probeGlass on the picked glass; inputs it finds live are added.
//  Copy Swift  .tune([...]) code for the current changes, on the clipboard.
//  Save JSON   captures/glass-panel.json – load it with .tune(file: "glass-panel.json"),
//              which in the simulator re-reads the file whenever you edit it.
//
//  Research / simulator use only — private API, never ship it.
//

#if canImport(UIKit)

import Combine
import SwiftUI
import UIKit

extension View {

    /// Adds the Liquid Glass panel: a floating button that edits any glass on screen.
    func glassPanel() -> some View {
        background(BoneGlassPanelAnchor())
    }
}

/// Finds the window scene and installs the panel's overlay window there.
struct BoneGlassPanelAnchor: UIViewRepresentable {
    func makeUIView(context: Context) -> BonePanelAnchorView { BonePanelAnchorView() }
    func updateUIView(_ view: BonePanelAnchorView, context: Context) {}
}

final class BonePanelAnchorView: UIView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        isUserInteractionEnabled = false
        if let scene = window?.windowScene { BoneGlassPanelModel.shared.install(on: scene) }
    }
}

/// Overlay window above the app. Lets every touch through except on the panel
/// itself (or everywhere while picking). SwiftUI ignores taps in a window that
/// is not key, so the panel becomes key when it is touched and gives key back
/// on Cancel / close.
final class BonePanelWindow: UIWindow {
    weak var model: BoneGlassPanelModel?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let m = model else { return nil }
        guard m.picking || m.buttonRect.contains(point) || m.cardRect.contains(point) else { return nil }
        if !isKeyWindow {
            m.rememberKeyWindow()
            makeKey()
        }
        return super.hitTest(point, with: event)
    }
}

final class BoneLinkTarget: NSObject {
    private let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func step() { action() }
}

// MARK: - Model

struct BoneKnob: Identifiable {
    let filterIndex: Int
    let key: String
    let kind: BoneValueKind
    let hidden: Bool
    var id: String { "\(filterIndex).\(key)" }
    var label: String { GlassInput(rawValue: key)?.caseName ?? key }
}

struct BoneKnobGroup: Identifiable {
    let id: String
    let knobs: [BoneKnob]
}

struct BonePreset: Identifiable {
    let name: String
    let tuning: GlassTuning
    var id: String { name }
}

struct BoneMatrixPreset: Identifiable {
    let name: String
    let floats: [Float]
    var id: String { name }
    static let all = [BoneMatrixPreset(name: "identity", floats: BoneColorMatrix.identity),
                      BoneMatrixPreset(name: "grayscale", floats: BoneColorMatrix.grayscale),
                      BoneMatrixPreset(name: "invert", floats: BoneColorMatrix.invert),
                      BoneMatrixPreset(name: "swap R/B", floats: BoneColorMatrix.swapRedBlue)]
}

final class BoneGlassPanelModel: ObservableObject {

    static let shared = BoneGlassPanelModel()

    static let presets: [BonePreset] = [
        BonePreset(name: "no shadow", tuning: .noShadow),
        BonePreset(name: "no lensing", tuning: .noLensing),
        BonePreset(name: "no blur", tuning: .noBlur),
        BonePreset(name: "no highlight", tuning: .noHighlight),
        BonePreset(name: "no bleed", tuning: .noBleed),
        BonePreset(name: "flat", tuning: .flat),
        BonePreset(name: "aberration", tuning: .aberration),
    ]

    static let numberFormat = FloatingPointFormatStyle<Double>(locale: Locale(identifier: "en_US_POSIX"))
        .grouping(.never).precision(.fractionLength(0...4))

    @Published var picking = false
    @Published var mode = BonePanelMode.glass
    @Published var isOpen = false
    @Published var probing = false
    @Published var atTop = false
    @Published var filterIndex = 0
    @Published var search = ""
    @Published var status = ""
    @Published var code: String?
    @Published var outlines: [CGRect] = []
    @Published var selection: CGRect = .null
    @Published var rangeScale: [String: Double] = [:]
    @Published private(set) var revision = 0

    /// Window-space rects the overlay window takes touches in.
    var buttonRect: CGRect = .zero
    var cardRect: CGRect = .zero

    /// Layer mode: the CALayer being edited.
    let layerEditor = BoneLayerEditor()

    private(set) var filters: [BoneFilterRef] = []
    private weak var element: CALayer?
    private weak var elementWindow: UIWindow?
    private var center: CGPoint = .zero
    private var snapshots: [Int: NSObject] = [:]          // filter index → copy taken at selection
    private var originalKeys: [Int: Set<String>] = [:]    // inputs SwiftUI had set
    private var overrides: [Int: [String: Any]] = [:]     // filter index → input → value
    private var liveHidden: [Int: Set<String>] = [:]      // found by the probe
    private var panelWindow: BonePanelWindow?
    private weak var scene: UIWindowScene?
    private weak var previousKey: UIWindow?
    private var link: CADisplayLink?
    private var ticks = 0
    private var prober: BoneGlassProber?

    func install(on scene: UIWindowScene) {
        if let w = panelWindow, w.windowScene === scene { return }
        let w = BonePanelWindow(windowScene: scene)
        w.model = self
        w.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 50)
        w.backgroundColor = .clear
        let host = UIHostingController(rootView: BoneGlassPanelView(model: self))
        host.view.backgroundColor = .clear
        w.rootViewController = host
        w.isHidden = false
        panelWindow = w
        self.scene = scene
    }

    // MARK: Picking

    private func candidates() -> [(layer: CALayer, frame: CGRect, window: UIWindow)] {
        guard let scene else { return [] }
        let windows = scene.windows.filter { $0 !== panelWindow && !$0.isHidden }
            .sorted { $0.windowLevel.rawValue < $1.windowLevel.rawValue }
        var out: [(layer: CALayer, frame: CGRect, window: UIWindow)] = []
        for w in windows {
            for l in BoneGlassLayers.glassLayers(in: w.layer) {
                let f = BoneGlassLayers.screenFrame(of: l, in: w)
                if f.width > 1, f.height > 1 { out.append((layer: l, frame: f, window: w)) }
            }
        }
        return out
    }

    func startPicking() {
        code = nil
        refreshOutlines()
        picking = true
    }

    func refreshOutlines() {
        if mode == .layer {
            outlines = BoneLayerEditor.leaves(in: scene, excluding: panelWindow).map { $0.frame }
            status = "Tap any element."
        } else {
            outlines = candidates().map { $0.frame }
            status = outlines.isEmpty ? "No Liquid Glass on screen." : "Tap a glass element."
        }
    }

    func pick(at point: CGPoint) {
        picking = false
        if mode == .layer {
            guard let hit = BoneLayerEditor.leaves(in: scene, excluding: panelWindow).last(where: { $0.frame.contains(point) }) else {
                status = "No layer at that point."
                return
            }
            layerEditor.select(hit.layer, in: hit.window, scene: scene, excluding: panelWindow)
            open()
            return
        }
        guard let hit = candidates().last(where: { $0.frame.contains(point) }) else {
            status = "No glass at that point."
            return
        }
        select(hit.layer, in: hit.window)
    }

    private func open() {
        isOpen = true
        rememberKeyWindow()
        panelWindow?.makeKey()
    }

    func rememberKeyWindow() {
        if let k = scene?.windows.first(where: { $0.isKeyWindow && $0 !== panelWindow }) { previousKey = k }
    }

    func cancelPicking() {
        picking = false
        if !isOpen { previousKey?.makeKey() }
    }

    func select(_ glass: CALayer, in window: UIWindow) {
        let el = BoneGlassLayers.element(of: glass)
        element = el
        elementWindow = window
        filters = BoneGlassLayers.filterRefs(inElement: el)
        let frame = BoneGlassLayers.screenFrame(of: glass, in: window)
        center = CGPoint(x: frame.midX, y: frame.midY)
        selection = frame
        snapshots = [:]
        originalKeys = [:]
        overrides = [:]
        liveHidden = [:]
        for (i, ref) in filters.enumerated() {
            snapshots[i] = ref.filter?.copy() as? NSObject
            originalKeys[i] = Set(ref.keys)
        }
        filterIndex = 0
        status = "\(type(of: glass)) · " + filters.map(\.type).joined(separator: " + ")
        startLink()
        open()
    }

    func close() {
        isOpen = false
        cardRect = .zero
        code = nil
        previousKey?.makeKey()
    }

    // MARK: Keeping the values

    private func startLink() {
        guard link == nil else { return }
        let l = CADisplayLink(target: BoneLinkTarget { [weak self] in self?.tick() }, selector: #selector(BoneLinkTarget.step))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 4, maximum: 10, preferred: 8)
        l.add(to: .main, forMode: .common)
        link = l
    }

    /// SwiftUI rebuilds the filter (and sometimes the layers) on updates –
    /// re-apply the overrides a few times per second.
    private func tick() {
        guard !probing else { return }
        ticks += 1
        if let el = element, let win = elementWindow, BoneGlassLayers.isAttached(el, to: win) {
            // still there
        } else if isOpen || !overrides.isEmpty {
            reacquire()
        }
        for (i, ref) in filters.enumerated() {
            for (k, v) in overrides[i] ?? [:] {
                if let cur = ref.value(k), BoneGlassLayers.same(cur, v) { continue }
                ref.set(k, v)
            }
        }
        if let glass = filters.first?.layer, let win = elementWindow {
            let f = BoneGlassLayers.screenFrame(of: glass, in: win)
            if f != selection {
                selection = f
                center = CGPoint(x: f.midX, y: f.midY)
            }
        }
        if isOpen, ticks % 3 == 0 { revision &+= 1 }
    }

    /// The glass was replaced – find it again at the same place.
    private func reacquire() {
        guard let hit = candidates().last(where: { $0.frame.contains(center) }) else { return }
        let el = BoneGlassLayers.element(of: hit.layer)
        element = el
        elementWindow = hit.window
        let fresh = BoneGlassLayers.filterRefs(inElement: el)
        if fresh.map(\.type) != filters.map(\.type) { overrides = [:] }
        filters = fresh
    }

    // MARK: Knobs

    func knobGroups() -> [BoneKnobGroup] {
        guard filters.indices.contains(filterIndex) else { return [] }
        let i = filterIndex, ref = filters[i]
        let original = originalKeys[i] ?? []
        var keys = original.union((overrides[i] ?? [:]).keys)
        if ref.isGlass { keys.formUnion(GlassInput.allCases.map(\.rawValue)) }
        keys.formUnion(liveHidden[i] ?? [])
        keys.remove("inputSourceSublayerName")
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        var groups: [String: [BoneKnob]] = [:]
        for key in keys {
            let knob = BoneKnob(filterIndex: i, key: key, kind: BoneValueKind.of(key: key, current: ref.value(key)),
                                hidden: !original.contains(key))
            if !q.isEmpty, !knob.label.lowercased().contains(q), !key.lowercased().contains(q) { continue }
            let group = knob.hidden ? "Hidden – not set by SwiftUI" : (GlassInput(rawValue: key)?.group ?? "Inputs")
            groups[group, default: []].append(knob)
        }
        return groups.map { BoneKnobGroup(id: $0.key, knobs: $0.value.sorted { $0.label < $1.label }) }
            .sorted { ($0.id.hasPrefix("Hidden") ? 0 : 1, $0.id) < ($1.id.hasPrefix("Hidden") ? 0 : 1, $1.id) }
    }

    private func ref(_ k: BoneKnob) -> BoneFilterRef? {
        filters.indices.contains(k.filterIndex) ? filters[k.filterIndex] : nil
    }

    func current(_ k: BoneKnob) -> Any? { ref(k)?.value(k.key) }

    func set(_ k: BoneKnob, _ value: Any) {
        overrides[k.filterIndex, default: [:]][k.key] = value
        ref(k)?.set(k.key, value)
        revision &+= 1
    }

    func isChanged(_ k: BoneKnob) -> Bool { overrides[k.filterIndex]?[k.key] != nil }

    /// Inputs the panel is holding on a layer – `.tune` leaves these alone, so
    /// the panel wins on views that also have `.tune` and the two never fight.
    func holds(_ layer: CALayer, filter name: String, key: String) -> Bool {
        filters.indices.contains { filters[$0].layer === layer && filters[$0].name == name && overrides[$0]?[key] != nil }
    }

    func reset(_ k: BoneKnob) {
        overrides[k.filterIndex]?[k.key] = nil
        restore(filter: k.filterIndex, key: k.key)
        revision &+= 1
    }

    func resetAll() {
        let touched = overrides
        overrides = [:]
        for (i, values) in touched { values.keys.forEach { restore(filter: i, key: $0) } }
        status = "Back to SwiftUI's values."
        revision &+= 1
    }

    /// Back to SwiftUI's value in place – or remove the input if SwiftUI never set it.
    private func restore(filter i: Int, key: String) {
        guard filters.indices.contains(i) else { return }
        let ref = filters[i]
        if originalKeys[i]?.contains(key) == true, let original = snapshots[i]?.value(forKey: key) {
            ref.set(key, original)
        } else {
            ref.remove(key)
        }
    }

    func apply(_ preset: BonePreset) {
        guard let gi = filters.firstIndex(where: \.isGlass) else { return }
        for (k, v) in preset.tuning.caValues { set(BoneKnob(filterIndex: gi, key: k, kind: .number, hidden: false), v) }
        status = "Applied \(preset.name)."
    }

    // MARK: Bindings

    func number(_ k: BoneKnob) -> Binding<Double> {
        Binding(get: { [weak self] in (self?.current(k) as? NSNumber)?.doubleValue ?? 0 },
                set: { [weak self] in self?.set(k, NSNumber(value: $0)) })
    }

    func toggle(_ k: BoneKnob) -> Binding<Bool> {
        Binding(get: { [weak self] in ((self?.current(k) as? NSNumber)?.doubleValue ?? 0) != 0 },
                set: { [weak self] in self?.set(k, NSNumber(value: $0 ? 1 : 0)) })
    }

    func color(_ k: BoneKnob) -> Binding<CGColor> {
        Binding(get: { [weak self] in
                    if let v = self?.current(k), CFGetTypeID(v as CFTypeRef) == CGColor.typeID { return v as! CGColor }
                    return CGColor(gray: 0, alpha: 0)
                },
                set: { [weak self] in self?.set(k, $0) })
    }

    func size(_ k: BoneKnob, _ axis: Int) -> Binding<Double> {
        Binding(get: { [weak self] in
                    let s = (self?.current(k) as? NSValue)?.cgSizeValue ?? .zero
                    return Double(axis == 0 ? s.width : s.height)
                },
                set: { [weak self] v in
                    guard let self else { return }
                    var s = (self.current(k) as? NSValue)?.cgSizeValue ?? .zero
                    if axis == 0 { s.width = v } else { s.height = v }
                    self.set(k, NSValue(cgSize: s))
                })
    }

    func matrix(_ k: BoneKnob) -> [Float] {
        current(k).flatMap { BoneColorMatrix.floats(from: $0) } ?? BoneColorMatrix.identity
    }

    func matrixCell(_ k: BoneKnob, _ i: Int) -> Binding<Double> {
        Binding(get: { [weak self] in Double(self?.matrix(k)[i] ?? 0) },
                set: { [weak self] v in
                    guard let self else { return }
                    var m = self.matrix(k)
                    m[i] = Float(v)
                    self.set(k, BoneColorMatrix.value(m))
                })
    }

    func setMatrix(_ k: BoneKnob, _ m: [Float]) { set(k, BoneColorMatrix.value(m)) }

    func range(_ k: BoneKnob) -> ClosedRange<Double> {
        let base = Self.baseRange(k.key)
        let s = rangeScale[k.id] ?? 1
        let cur = (current(k) as? NSNumber)?.doubleValue ?? 0
        return min(base.lowerBound * s, cur)...max(base.upperBound * s, cur)
    }

    func widen(_ k: BoneKnob) { rangeScale[k.id] = (rangeScale[k.id] ?? 1) * 4 }

    static func baseRange(_ key: String) -> ClosedRange<Double> {
        func has(_ s: String) -> Bool { key.contains(s) }
        if has("Opacity") || has("Contribution") || has("DarkenBlend") { return 0...1 }
        if has("Saturation") { return 0...3 }
        if has("MaxLuma") || has("HoldingToneWhite") || has("MatrixWhite") || has("MatrixBlack") { return -1...2 }
        if has("Clamp") { return 0...3 }
        if has("Angle") { return -Double.pi...Double.pi }
        if has("Spread") { return 0...5 }
        if has("Bias") || has("EffectOffset") { return -2...2 }
        if has("Headroom") { return 0...16 }
        if has("Highlight") { return 0...2 }
        if has("Radius") || has("Width") { return 0...100 }
        return -100...100
    }

    // MARK: Actions

    func copySwift() {
        let c = swiftCode()
        UIPasteboard.general.string = c
        code = c
        status = "Copied to the clipboard."
    }

    func swiftCode() -> String {
        var typed: [String] = [], raw: [String] = []
        for (i, ref) in filters.enumerated() {
            for (k, v) in (overrides[i] ?? [:]).sorted(by: { $0.key < $1.key }) {
                if ref.isGlass, let g = GlassInput(rawValue: k), let lit = BoneSwiftLiteral.glassValue(v) {
                    typed.append(".\(g.caseName): \(lit)")
                } else if let lit = BoneSwiftLiteral.object(v) {
                    raw.append("\"\(ref.isGlass ? k : "\(ref.name).\(k)")\": \(lit)")
                }
            }
        }
        var lines: [String] = []
        if !typed.isEmpty { lines.append(".tune([\(typed.joined(separator: ", "))])") }
        if !raw.isEmpty { lines.append(".tune(.raw([\(raw.joined(separator: ", "))]))") }
        return lines.isEmpty ? "// nothing changed" : lines.joined(separator: "\n")
    }

    func saveJSON() {
        var out: [String: Any] = [:]
        for (i, ref) in filters.enumerated() {
            var section = out[ref.name] as? [String: Any] ?? [:]
            for (k, v) in overrides[i] ?? [:] {
                if let e = BoneGlassJSON.encode(v) { section[GlassInput(rawValue: k)?.caseName ?? k] = e }
            }
            if !section.isEmpty { out[ref.name] = section }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys]) else { return }
        BoneCapture.writeData(data, fileName: "glass-panel.json")
        status = "Saved glass-panel.json – load it with .tune(file: \"glass-panel.json\")."
    }

    func probe() {
        guard let el = element, let win = elementWindow, filters.indices.contains(filterIndex) else { return }
        let i = filterIndex
        probing = true
        status = "Probing \(filters[i].type)…"
        panelWindow?.isHidden = true   // keep the panel out of the screen captures
        let p = BoneGlassProber(element: el, window: win, filters: [filters[i]])
        prober = p
        p.run { [weak self] report in
            report.write(fileName: "glass-probe-panel.txt")
            guard let self else { return }
            self.liveHidden[i] = Set(report.liveHidden[0] ?? [])
            self.prober = nil
            self.probing = false
            self.panelWindow?.isHidden = false
            self.status = report.summary + " → glass-probe-panel.txt"
            self.revision &+= 1
        }
    }
}

// MARK: - Swift literals for Copy Swift

enum BoneSwiftLiteral {

    static func number(_ d: Double) -> String {
        if d == d.rounded(), abs(d) < 1e9 { return String(Int(d)) }
        var s = String(format: "%.4f", d)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s == "-0" ? "0" : s
    }

    static func uiColor(_ c: CGColor) -> String {
        let s = c.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil) ?? c
        var v = (s.components ?? [0, 0, 0, 1]).map { number(Double($0)) }
        if v.count == 2 { v = [v[0], v[0], v[0], v[1]] }
        while v.count < 4 { v.append("1") }
        return "UIColor(red: \(v[0]), green: \(v[1]), blue: \(v[2]), alpha: \(v[3]))"
    }

    /// A GlassValue for `.tune([.input: …])`.
    static func glassValue(_ v: Any) -> String? {
        if let n = v as? NSNumber { return number(n.doubleValue) }
        if CFGetTypeID(v as CFTypeRef) == CGColor.typeID { return ".color(\(uiColor(v as! CGColor)))" }
        if let val = v as? NSValue, String(cString: val.objCType).contains("CGSize") {
            return ".size(\(number(Double(val.cgSizeValue.width))), \(number(Double(val.cgSizeValue.height))))"
        }
        return nil
    }

    /// A Core Animation value for `.tune(.raw([...]))`.
    static func object(_ v: Any) -> String? {
        if let n = v as? NSNumber { return number(n.doubleValue) }
        if CFGetTypeID(v as CFTypeRef) == CGColor.typeID { return "\(uiColor(v as! CGColor)).cgColor" }
        if let m = BoneColorMatrix.floats(from: v) {
            return "BoneColorMatrix.value([\(m.map { number(Double($0)) }.joined(separator: ", "))])"
        }
        if let val = v as? NSValue, String(cString: val.objCType).contains("CGSize") {
            return "NSValue(cgSize: CGSize(width: \(number(Double(val.cgSizeValue.width))), height: \(number(Double(val.cgSizeValue.height)))))"
        }
        return nil
    }
}

// MARK: - Views

struct BoneGlassPanelView: View {
    @ObservedObject var model: BoneGlassPanelModel

    var body: some View {
        ZStack {
            if model.picking {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .global) { model.pick(at: $0) }
                outlines(model.outlines, dash: [])
                VStack(spacing: 8) {
                    Picker("Mode", selection: $model.mode) {
                        ForEach(BonePanelMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                    .onChange(of: model.mode) { model.refreshOutlines() }
                    Text(model.status).font(.callout.bold())
                    Button("Cancel") { model.cancelPicking() }.buttonStyle(.borderedProminent).tint(.pink)
                }
                .padding(14)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 8)
            } else if model.isOpen {
                if model.mode == .layer {
                    BoneLayerOutline(editor: model.layerEditor)
                } else if !model.probing {
                    outlines([model.selection], dash: [6, 4])
                }
                VStack(spacing: 0) {
                    if !model.atTop { Spacer(minLength: 0) }
                    Group {
                        if model.mode == .layer {
                            BoneLayerCard(model: model, editor: model.layerEditor)
                        } else {
                            BoneGlassCard(model: model)
                        }
                    }
                        .containerRelativeFrame(.vertical) { h, _ in h * 0.46 }
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { model.cardRect = $0 }
                        .onDisappear { model.cardRect = .zero }
                    if model.atTop { Spacer(minLength: 0) }
                }
                .padding(.horizontal, 8)
            } else {
                Button { model.startPicking() } label: {
                    Image(systemName: "drop.halffull")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .frame(width: 54, height: 54)
                        .background(Circle().fill(Color.pink.gradient))
                        .shadow(radius: 6)
                }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { model.buttonRect = $0 }
                .onDisappear { model.buttonRect = .zero }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(20)
            }
        }
    }

    private func outlines(_ rects: [CGRect], dash: [CGFloat]) -> some View {
        Canvas { ctx, _ in
            for r in rects where !r.isNull {
                ctx.stroke(Path(roundedRect: r.insetBy(dx: -3, dy: -3), cornerRadius: 10), with: .color(.pink),
                           style: StrokeStyle(lineWidth: 2.5, dash: dash))
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct BoneGlassCard: View {
    @ObservedObject var model: BoneGlassPanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Liquid Glass").font(.headline)
                    Text(model.status).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
                Button { model.startPicking() } label: { Image(systemName: "scope") }
                Button { model.atTop.toggle() } label: {
                    Image(systemName: model.atTop ? "rectangle.bottomhalf.inset.filled" : "rectangle.tophalf.inset.filled")
                }
                Button { model.close() } label: { Image(systemName: "xmark.circle.fill") }
            }
            .font(.title3)
            if model.filters.count > 1 {
                Picker("Filter", selection: $model.filterIndex) {
                    ForEach(model.filters.indices, id: \.self) { i in Text(model.filters[i].type).tag(i) }
                }
                .pickerStyle(.segmented)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip("Probe", "waveform.path.ecg") { model.probe() }
                    chip("Copy Swift", "doc.on.doc") { model.copySwift() }
                    chip("Save JSON", "square.and.arrow.down") { model.saveJSON() }
                    chip("Reset all", "arrow.uturn.backward") { model.resetAll() }
                    ForEach(BoneGlassPanelModel.presets) { p in chip(p.name, nil) { model.apply(p) } }
                }
            }
            TextField("Search inputs", text: $model.search)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if let code = model.code {
                Text(code)
                    .font(.caption2.monospaced())
                    .textSelection(.enabled)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(model.knobGroups()) { g in
                        Text(g.id.uppercased()).font(.caption2.bold()).foregroundStyle(.secondary).padding(.top, 4)
                        ForEach(g.knobs) { BoneKnobRow(model: model, knob: $0) }
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
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

struct BoneKnobRow: View {
    @ObservedObject var model: BoneGlassPanelModel
    let knob: BoneKnob

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(knob.label)
                    .font(.caption.monospaced())
                    .foregroundStyle(knob.hidden ? Color.purple : Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if model.isChanged(knob) {
                    Button { model.reset(knob) } label: { Image(systemName: "arrow.uturn.backward.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.pink)
                }
                Spacer(minLength: 4)
                accessory
            }
            control
        }
    }

    @ViewBuilder private var accessory: some View {
        switch knob.kind {
        case .number:
            TextField("", value: model.number(knob), format: BoneGlassPanelModel.numberFormat)
                .font(.caption.monospaced())
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numbersAndPunctuation)
                .frame(width: 92)
            Button { model.widen(knob) } label: { Image(systemName: "arrow.left.and.right.circle") }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        case .toggle:
            Toggle("", isOn: model.toggle(knob)).labelsHidden()
        case .color:
            ColorPicker("", selection: model.color(knob), supportsOpacity: true).labelsHidden()
        default:
            EmptyView()
        }
    }

    @ViewBuilder private var control: some View {
        switch knob.kind {
        case .number:
            Slider(value: model.number(knob), in: model.range(knob))
        case .size:
            HStack(spacing: 6) {
                Text("w").font(.caption2)
                Slider(value: model.size(knob, 0), in: -100...100)
                Text("h").font(.caption2)
                Slider(value: model.size(knob, 1), in: -100...100)
            }
        case .matrix:
            BoneMatrixEditor(model: model, knob: knob)
        case .toggle, .color:
            EmptyView()
        default:
            Text("\(knob.kind.rawValue) value – not editable here").font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct BoneMatrixEditor: View {
    @ObservedObject var model: BoneGlassPanelModel
    let knob: BoneKnob

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Grid(horizontalSpacing: 3, verticalSpacing: 3) {
                GridRow {
                    ForEach(["r", "g", "b", "a", "bias"], id: \.self) { Text($0).font(.caption2).foregroundStyle(.secondary) }
                }
                ForEach(0..<4, id: \.self) { r in
                    GridRow {
                        ForEach(0..<5, id: \.self) { c in
                            TextField("", value: model.matrixCell(knob, r * 5 + c), format: BoneGlassPanelModel.numberFormat)
                                .font(.caption2.monospaced())
                                .multilineTextAlignment(.trailing)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.numbersAndPunctuation)
                        }
                    }
                }
            }
            HStack(spacing: 6) {
                ForEach(BoneMatrixPreset.all) { p in
                    Button(p.name) { model.setMatrix(knob, p.floats) }.font(.caption2).buttonStyle(.bordered)
                }
            }
        }
    }
}

#endif
