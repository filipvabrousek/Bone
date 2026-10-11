//
//  BoneGlassPanelModel.swift
//  Bone-27
//
//  The inspector's model (.boneInspector / .glassPanel): what is picked, the
//  glass inputs and their overrides, the values kept on the glass while
//  SwiftUI rebuilds it, and the actions (Copy Swift, Save JSON, Probe). The
//  windows are in BoneGlassPanel.swift, the views in BoneGlassPanelViews.swift.
//

#if DEBUG   // Bone is private API: it compiles to nothing outside Debug builds

#if (canImport(UIKit) && !os(watchOS)) || os(macOS)

import Combine
import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

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
    @Published var mode = BonePanelMode.auto
    /// Which card is open: the glass inputs or the layer.
    @Published var showing = BonePanelMode.glass
    /// 3D exploded view (BoneExploded.swift).
    @Published var exploded = false
    @Published var peeking = false
    @Published var explodeSpacing = 30.0
    @Published var explodeInfo = ""
    #if canImport(UIKit)
    weak var explodedView: BoneExplodedView?
    #endif
    private var explodeShot: CGImage?
    /// Timeline bar (BoneTimeline.swift): pause, slow down, step and scrub animations.
    @Published var timelineOpen = false
    #if canImport(UIKit) && !os(visionOS)
    let timeline = BoneTimeline()
    #elseif os(macOS)
    let macTimeline = BoneMacTimeline()
    #endif
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
    var timelineRect: CGRect = .zero
    /// A take on screen covers the app: the window takes every touch.
    var timelineCovers: Bool {
        #if os(visionOS)
        false
        #elseif os(macOS)
        timelineOpen && !isOpen && !picking && macTimeline.take != nil
        #else
        timelineOpen && !isOpen && !picking && !exploded && timeline.showsFrame
        #endif
    }

    /// The app's own windows (everything but the panel), back to front.
    var appWindows: [BonePlatformWindow] {
        #if canImport(UIKit)
        return (scene?.windows ?? []).filter { $0 !== panelWindow && !$0.isHidden }
            .sorted { $0.windowLevel.rawValue < $1.windowLevel.rawValue }
        #else
        return appWindow.map { [$0] } ?? []
        #endif
    }
    var panel: BonePlatformWindow? { panelWindow }

    /// Points the overlay window takes the touch / mouse at (everything else goes to the app).
    func takesPoint(_ point: CGPoint) -> Bool {
        picking || exploded || buttonRect.contains(point) || cardRect.contains(point)
            || timelineRect.contains(point) || timelineCovers
    }

    /// Layer mode: the CALayer being edited.
    let layerEditor = BoneLayerEditor()

    private(set) var filters: [BoneFilterRef] = []
    private weak var element: CALayer?
    private weak var elementWindow: BonePlatformWindow?
    private var center: CGPoint = .zero
    private var snapshots: [Int: NSObject] = [:]          // filter index → copy taken at selection
    private var originalKeys: [Int: Set<String>] = [:]    // inputs SwiftUI had set
    private var overrides: [Int: [String: Any]] = [:]     // filter index → input → value
    private var liveHidden: [Int: Set<String>] = [:]      // found by the probe
    private var panelWindow: BonePanelWindow?
    #if canImport(UIKit)
    private weak var scene: UIWindowScene?
    #else
    private weak var appWindow: NSWindow?
    #endif
    private weak var previousKey: BonePlatformWindow?
    private var ticker: BoneTicker?
    private var ticks = 0
    private var prober: BoneGlassProber?

    #if canImport(UIKit)
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
        #if !os(visionOS)
        timeline.model = self
        #endif
    }
    #else
    func install(on window: NSWindow) {
        if panelWindow != nil, appWindow === window { return }
        let w = BonePanelWindow(over: window)
        w.model = self
        let host = NSHostingView(rootView: BoneGlassPanelView(model: self))
        host.frame = CGRect(origin: .zero, size: window.frame.size)
        host.autoresizingMask = [.width, .height]
        w.contentView = host
        w.orderFront(nil)
        panelWindow = w
        appWindow = window
        macTimeline.model = self
    }
    #endif

    // MARK: Timeline

    #if canImport(UIKit) && !os(visionOS)
    func openTimeline() {
        picking = false
        code = nil
        timelineOpen = true
        timeline.open()
        rememberKeyWindow()
        panelWindow?.makeKey()       // the bar's first touch would be dropped by a non-key window
    }

    func closeTimeline() {
        timeline.close()
        timelineOpen = false
        timelineRect = .zero
        previousKey?.makeKey()
    }
    #elseif os(macOS)
    func openTimeline() {
        picking = false
        code = nil
        timelineOpen = true
        macTimeline.open()
    }

    func closeTimeline() {
        macTimeline.close()
        timelineOpen = false
        timelineRect = .zero
    }
    #endif

    // MARK: Picking

    private func candidates() -> [(layer: CALayer, frame: CGRect, window: BonePlatformWindow)] {
        var out: [(layer: CALayer, frame: CGRect, window: BonePlatformWindow)] = []
        for w in appWindows {
            guard let root = BoneWindows.root(w) else { continue }
            for l in BoneGlassLayers.glassLayers(in: root) {
                let f = BoneWindows.frame(of: l, in: w)
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
        let glass = candidates().map { $0.frame }
        let all = BoneLayerEditor.leaves(in: appWindows)
        let leaves = all.map { $0.frame }
        switch mode {
        case .auto:   // outline what you most likely want; every element is still tappable
            outlines = glass + all.filter { LayerTarget.text.matches($0.layer) }.map { $0.frame }
            status = "Tap text, glass or any element."
        case .glass:
            outlines = glass
            status = glass.isEmpty ? "No Liquid Glass on screen." : "Tap a glass element."
        case .layer:
            outlines = leaves
            status = "Tap any element."
        }
    }

    private var lastPoint = CGPoint.zero

    func pick(at point: CGPoint) {
        picking = false
        lastPoint = point
        let glass = candidates().last { $0.frame.contains(point) }
        let leaf = leafAt(point)
        switch mode {
        case .glass where glass != nil, .auto where glass != nil:
            showGlass(glass!)
        case .layer where leaf != nil, .auto where leaf != nil:
            showLayer(leaf!)
        default:
            status = "Nothing to inspect at that point."
        }
    }

    /// The frontmost drawn layer at a point – text first, so a tap on a glass
    /// button's label finds the label.
    private func leafAt(_ point: CGPoint) -> (layer: CALayer, frame: CGRect, window: BonePlatformWindow)? {
        let hits = BoneLayerEditor.leaves(in: appWindows).filter { $0.frame.contains(point) }
        return hits.last(where: { LayerTarget.text.matches($0.layer) }) ?? hits.last
    }

    private func showGlass(_ hit: (layer: CALayer, frame: CGRect, window: BonePlatformWindow)) {
        showing = .glass
        select(hit.layer, in: hit.window)
    }

    private func showLayer(_ hit: (layer: CALayer, frame: CGRect, window: BonePlatformWindow)) {
        showing = .layer
        layerEditor.select(hit.layer, in: hit.window) { [weak self] in self?.appWindows ?? [] }
        open()
    }

    #if canImport(UIKit)
    // MARK: 3D exploded view

    /// Takes a screenshot without the panel (glass is cut from it), then opens the 3D view.
    func openExploded() {
        picking = false
        code = nil
        captureWithoutPanel { shot in
            self.explodeShot = shot
            self.exploded = true
            self.rememberKeyWindow()
            self.panelWindow?.makeKey()
        }
    }

    func buildExploded() {
        explodedView?.build(scene: scene, excluding: panelWindow, screenshot: explodeShot)
        explodeInfo = "\(explodedView?.nodes.count ?? 0) layers"
    }

    /// Re-freezes the app as it is now (e.g. after tuning glass).
    func refreshExploded() {
        captureWithoutPanel { shot in
            self.explodeShot = shot
            self.buildExploded()
        }
    }

    func closeExploded() {
        exploded = false
        peeking = false
        isOpen = false
        explodeShot = nil
        previousKey?.makeKey()
    }

    func pickExploded(_ node: BoneExplodedNode) {
        guard let l = node.source, let w = node.window else { return }
        lastPoint = CGPoint(x: node.frame.midX, y: node.frame.midY)
        if node.isGlass { showGlass((layer: l, frame: node.frame, window: w)) }
        else { showLayer((layer: l, frame: node.frame, window: w)) }
    }

    /// What to preview on the selected plane.
    func explodedTuning() -> (LayerTuning, Int)? {
        guard isOpen, showing == .layer, let sel = explodedView?.selected, sel.source === layerEditor.layer else { return nil }
        return (layerEditor.tuning, layerEditor.generation)
    }

    /// Screenshot without the panel – and without the text on glass, so glass planes
    /// show only the glass (its label gets a plane of its own).
    /// Glass overrides to preview on the selected glass plane (its glass filter only).
    func explodedGlassValues() -> [String: Any]? {
        guard isOpen, showing == .glass, let sel = explodedView?.selected, sel.isGlass,
              sel.source?.superlayer === element, let i = filters.firstIndex(where: \.isGlass) else { return nil }
        return overrides[i] ?? [:]
    }

    private func captureWithoutPanel(_ done: @escaping (CGImage?) -> Void) {
        let glass = candidates().map { $0.frame }
        let labels = BoneLayerEditor.leaves(in: appWindows)
            .filter { hit in LayerTarget.text.matches(hit.layer) && glass.contains { $0.contains(CGPoint(x: hit.frame.midX, y: hit.frame.midY)) } }
            .map { $0.layer }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        labels.forEach { $0.isHidden = true }
        CATransaction.commit()
        panelWindow?.isHidden = true
        CATransaction.flush()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {   // let the render server drop the panel
            let shot = BoneScreen.capture()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            labels.forEach { $0.isHidden = false }
            CATransaction.commit()
            self.panelWindow?.isHidden = false
            done(shot)
        }
    }

    #endif

    /// Glass card → its label (the text drawn on the glass), else whatever is at its centre.
    func switchToLayer() {
        let leaves = BoneLayerEditor.leaves(in: appWindows)
        let label = leaves.last { LayerTarget.text.matches($0.layer) && selection.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }
        if let hit = label ?? leafAt(CGPoint(x: selection.midX, y: selection.midY)) { showLayer(hit) }
    }

    /// Layer card → the glass around it.
    func switchToGlass() {
        let p = layerEditor.frame.isNull ? lastPoint : CGPoint(x: layerEditor.frame.midX, y: layerEditor.frame.midY)
        if let hit = candidates().last(where: { $0.frame.contains(p) }) { showGlass(hit) }
    }

    /// Is there glass under the layer being edited?
    var glassAtPoint: Bool {
        let p = layerEditor.frame.isNull ? lastPoint : CGPoint(x: layerEditor.frame.midX, y: layerEditor.frame.midY)
        return candidates().contains { $0.frame.contains(p) }
    }

    private func open() {
        isOpen = true
        rememberKeyWindow()
        panelWindow?.makeKey()
    }

    func rememberKeyWindow() {
        if let k = appWindows.first(where: { $0.isKeyWindow }) { previousKey = k }
    }

    func cancelPicking() {
        picking = false
        if !isOpen { previousKey?.makeKey() }
    }

    func select(_ glass: CALayer, in window: BonePlatformWindow) {
        let el = BoneGlassLayers.element(of: glass)
        element = el
        elementWindow = window
        filters = BoneGlassLayers.filterRefs(inElement: el)
        let frame = BoneWindows.frame(of: glass, in: window)
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
        guard ticker == nil else { return }
        ticker = BoneTicker { [weak self] in self?.tick() }
    }

    /// SwiftUI rebuilds the filter (and sometimes the layers) on updates –
    /// re-apply the overrides a few times per second.
    private func tick() {
        guard !probing else { return }
        ticks += 1
        if let el = element, let win = elementWindow, BoneWindows.isAttached(el, to: win) {
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
            let f = BoneWindows.frame(of: glass, in: win)
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
                    let s = (self?.current(k) as? NSValue)?.boneSize ?? .zero
                    return Double(axis == 0 ? s.width : s.height)
                },
                set: { [weak self] v in
                    guard let self else { return }
                    var s = (self.current(k) as? NSValue)?.boneSize ?? .zero
                    if axis == 0 { s.width = v } else { s.height = v }
                    self.set(k, NSValue.bone(size: s))
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
        BonePasteboard.copy(c)
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
        panelWindow?.hideForCapture(true)   // keep the panel out of the screen captures
        let p = BoneGlassProber(element: el, window: win, filters: [filters[i]])
        prober = p
        p.run { [weak self] report in
            report.write(fileName: "glass-probe-panel.txt")
            guard let self else { return }
            self.liveHidden[i] = Set(report.liveHidden[0] ?? [])
            self.prober = nil
            self.probing = false
            self.panelWindow?.hideForCapture(false)
            self.status = report.summary + " → glass-probe-panel.txt"
            self.revision &+= 1
        }
    }
}

#endif

#endif   // DEBUG
