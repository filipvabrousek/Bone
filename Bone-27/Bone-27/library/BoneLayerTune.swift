//
//  BoneLayerTune.swift
//  Bone-27
//
//  Tuning for ANY SwiftUI view – the layers SwiftUI draws it into. On iOS 27
//  Text is a CGDrawingLayer (a bitmap), an SF Symbol a ColorShapeLayer, a
//  gradient fill a GradientLayer – bare CALayers without a UIView. Each can be
//  filtered, blended, transformed, shadowed or given new contents:
//
//      Text("Hello").tuneLayers([.rotation: -8, .shadowOpacity: 1, .shadowRadius: 6], where: .text)
//      Text("Hello").tuneLayers([.filters: .filters([.gaussianBlur(2), .colorInvert])])
//      Image(systemName: "star.fill").tuneLayers([.blendMode: .blend(.difference)], where: .shape)
//      VStack { … }.tuneLayers(.outline, where: .all)            // see every layer
//      VStack { … }.dumpLayers("layers.txt")                       // what is there
//
//  Layers are SwiftUI's choice (it may merge or recreate them), so targets are
//  layer kinds, and values are re-applied a few times per second like .tune.
//  The glass panel (.glassPanel) edits any layer you tap in its Layer mode.
//
//  Research / simulator use only — private Core Animation filters, never ship it.
//

#if canImport(UIKit)

import SwiftUI
import UIKit

// MARK: - Properties and values

/// What `.tuneLayers` can change on a layer.
enum LayerProperty: String, CaseIterable, Hashable {
    case opacity, hidden, cornerRadius, masksToBounds, backgroundColor, borderWidth, borderColor
    case shadowOpacity, shadowRadius, shadowOffset, shadowColor
    /// Degrees around the layer's centre; rotationX/Y tilt in 3D (see `perspective`).
    case rotation, rotationX, rotationY, scale, scaleX, scaleY, translationX, translationY
    /// Eye distance in points for rotationX/Y (default 500).
    case perspective
    /// `.blend(.difference)` – the layer's compositingFilter.
    case blendMode
    /// `.filters([...])` – added after any filter SwiftUI put there itself.
    case filters
    /// `.image(UIImage)` – replaces what SwiftUI drew (e.g. the text bitmap).
    case contents
    case contentsGravity

    static let transformProperties: Set<LayerProperty> =
        [.rotation, .rotationX, .rotationY, .scale, .scaleX, .scaleY, .translationX, .translationY, .perspective]

    /// The plain Core Animation key, for the properties that map 1:1.
    var key: String? {
        switch self {
        case .opacity, .hidden, .cornerRadius, .masksToBounds, .backgroundColor, .borderWidth, .borderColor,
             .shadowOpacity, .shadowRadius, .shadowOffset, .shadowColor, .contents, .contentsGravity:
            return rawValue
        case .blendMode: return "compositingFilter"
        default: return nil
        }
    }
}

enum LayerValue: ExpressibleByFloatLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral {
    case number(Double)
    case color(CGColor)
    case size(CGSize)
    case image(CGImage)
    case blend(LayerBlend)
    case filters([BoneFilter])
    case gravity(CALayerContentsGravity)

    init(floatLiteral v: Double) { self = .number(v) }
    init(integerLiteral v: Int) { self = .number(Double(v)) }
    init(booleanLiteral v: Bool) { self = .number(v ? 1 : 0) }
    static func color(_ c: UIColor) -> LayerValue { .color(c.cgColor) }
    static func size(_ w: Double, _ h: Double) -> LayerValue { .size(CGSize(width: w, height: h)) }
    /// Any UIImage, SF Symbols included (rasterised when it has no bitmap).
    static func image(_ i: UIImage) -> LayerValue {
        if let cg = i.cgImage { return .image(cg) }
        let r = UIGraphicsImageRenderer(size: i.size).image { _ in i.draw(at: .zero) }
        return r.cgImage.map { .image($0) } ?? .number(0)
    }

    var number: Double? { if case .number(let d) = self { return d }; return nil }

    /// What Core Animation expects for -setValue:forKey:.
    var object: Any? {
        switch self {
        case .number(let d): return NSNumber(value: d)
        case .color(let c): return c
        case .size(let s): return NSValue(cgSize: s)
        case .image(let i): return i
        case .blend(let b): return b.filterType
        case .gravity(let g): return g.rawValue
        case .filters: return nil
        }
    }
}

/// Blend modes for `.blendMode` (Core Animation's *BlendMode compositing filters).
enum LayerBlend: String, CaseIterable {
    case normal, multiply, screen, overlay, darken, lighten, colorDodge, colorBurn, softLight, hardLight,
         difference, exclusion, hue, saturation, color, luminosity, linearBurn, linearDodge, linearLight,
         pinLight, subtract, divide

    var filterType: String { BoneFilterTypes.resolve(rawValue.prefix(1).uppercased() + rawValue.dropFirst() + "BlendMode") }
}

/// Core Animation filters for `.filters([...])`.
enum BoneFilter {
    case gaussianBlur(Double)                       // radius
    case colorMatrix([Float])                       // 4×5, see BoneColorMatrix
    case colorInvert
    case colorSaturate(Double)                      // 1 = unchanged
    case colorHueRotate(Double)                     // radians
    case colorBrightness(Double)                    // 0 = unchanged
    case colorContrast(Double)                      // 1 = unchanged
    case colorMonochrome(UIColor, amount: Double = 1)
    case multiplyColor(UIColor)
    case luminanceToAlpha
    /// Any filter type the SDK exports (kCAFilter…), e.g. .raw("chromaticAberration", ["inputAmount": 4]).
    case raw(String, [String: Any] = [:])

    var type: String {
        switch self {
        case .gaussianBlur: return BoneFilterTypes.resolve("GaussianBlur")
        case .colorMatrix: return BoneFilterTypes.resolve("ColorMatrix")
        case .colorInvert: return BoneFilterTypes.resolve("ColorInvert")
        case .colorSaturate: return BoneFilterTypes.resolve("ColorSaturate")
        case .colorHueRotate: return BoneFilterTypes.resolve("ColorHueRotate")
        case .colorBrightness: return BoneFilterTypes.resolve("ColorBrightness")
        case .colorContrast: return BoneFilterTypes.resolve("ColorContrast")
        case .colorMonochrome: return BoneFilterTypes.resolve("ColorMonochrome")
        case .multiplyColor: return BoneFilterTypes.resolve("MultiplyColor")
        case .luminanceToAlpha: return BoneFilterTypes.resolve("LuminanceToAlpha")
        case .raw(let t, _): return t
        }
    }

    var inputs: [String: Any] {
        switch self {
        case .gaussianBlur(let r): return ["inputRadius": r]
        case .colorMatrix(let m): return ["inputColorMatrix": BoneColorMatrix.value(m)]
        case .colorSaturate(let a), .colorBrightness(let a), .colorContrast(let a): return ["inputAmount": a]
        case .colorHueRotate(let a): return ["inputAngle": a]
        case .colorMonochrome(let c, let a): return ["inputColor": c.cgColor, "inputAmount": a]
        case .multiplyColor(let c): return ["inputColor": c.cgColor]
        case .raw(_, let i): return i
        default: return [:]
        }
    }

    /// A new CAFilter, named so Bone can find its own filters again.
    func make(name: String) -> NSObject? {
        guard let f = BoneFilterTypes.filter(type: type) else { return nil }
        f.setValue(name, forKey: "name")
        for (k, v) in inputs { f.setValue(v, forKey: k) }
        return f
    }

    /// Swift source, for the panel's Copy Swift.
    var swift: String {
        let n = BoneSwiftLiteral.number
        switch self {
        case .gaussianBlur(let r): return ".gaussianBlur(\(n(r)))"
        case .colorMatrix(let m): return ".colorMatrix([\(m.map { n(Double($0)) }.joined(separator: ", "))])"
        case .colorInvert: return ".colorInvert"
        case .colorSaturate(let a): return ".colorSaturate(\(n(a)))"
        case .colorHueRotate(let a): return ".colorHueRotate(\(n(a)))"
        case .colorBrightness(let a): return ".colorBrightness(\(n(a)))"
        case .colorContrast(let a): return ".colorContrast(\(n(a)))"
        case .colorMonochrome(_, let a): return ".colorMonochrome(.gray, amount: \(n(a)))"
        case .multiplyColor: return ".multiplyColor(.red)"
        case .luminanceToAlpha: return ".luminanceToAlpha"
        case .raw(let t, _): return ".raw(\"\(t)\")"
        }
    }
}

enum BoneFilterTypes {
    /// The value of the SDK constant kCAFilter<suffix> ("GaussianBlur" → "gaussianBlur").
    static func resolve(_ suffix: String) -> String {
        if let p = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "kCAFilter" + suffix) {
            return p.load(as: Unmanaged<NSString>.self).takeUnretainedValue() as String
        }
        return suffix.prefix(1).lowercased() + suffix.dropFirst()
    }

    /// +[CAFilter filterWithType:] – CAFilter is private.
    static func filter(type: String) -> NSObject? {
        let sel = NSSelectorFromString("filterWithType:")
        guard let cls = NSClassFromString("CAFilter") as? NSObject.Type, cls.responds(to: sel) else { return nil }
        return cls.perform(sel, with: type)?.takeUnretainedValue() as? NSObject
    }
}

// MARK: - Tuning

/// A set of layer overrides: a dictionary literal, combined with `+`.
///
///     .tuneLayers([.rotation: 10, .blendMode: .blend(.multiply)], where: .text)
///     .tuneLayers(.outline + [.opacity: 0.6])
struct LayerTuning: ExpressibleByDictionaryLiteral {
    var values: [LayerProperty: LayerValue] = [:]
    /// Any other layer key or key path, e.g. "cornerCurve" or "filters.gaussianBlur.inputRadius".
    var raw: [String: Any] = [:]

    init(dictionaryLiteral elements: (LayerProperty, LayerValue)...) {
        for (k, v) in elements { values[k] = v }
    }
    init(values: [LayerProperty: LayerValue] = [:], raw: [String: Any] = [:]) {
        self.values = values
        self.raw = raw
    }

    static func + (l: LayerTuning, r: LayerTuning) -> LayerTuning {
        LayerTuning(values: l.values.merging(r.values) { _, new in new }, raw: l.raw.merging(r.raw) { _, new in new })
    }
    static func raw(_ d: [String: Any]) -> LayerTuning { LayerTuning(raw: d) }

    /// A pink border on every targeted layer – shows where SwiftUI's layers are.
    static let outline: LayerTuning = [.borderWidth: 1, .borderColor: .color(.systemPink)]

    var isEmpty: Bool { values.isEmpty && raw.isEmpty }
    var hasTransform: Bool { !LayerProperty.transformProperties.isDisjoint(with: values.keys) }

    func number(_ p: LayerProperty, _ fallback: Double) -> Double { values[p]?.number ?? fallback }

    /// Rotation/scale/translation about the layer's centre, whatever its anchor point.
    func transform(for layer: CALayer) -> CATransform3D {
        let rad = Double.pi / 180
        let s = number(.scale, 1)
        let cx = (0.5 - layer.anchorPoint.x) * layer.bounds.width
        let cy = (0.5 - layer.anchorPoint.y) * layer.bounds.height
        var t = CATransform3DMakeTranslation(cx, cy, 0)
        if values[.rotationX] != nil || values[.rotationY] != nil { t.m34 = -1 / max(1, number(.perspective, 500)) }
        t = CATransform3DTranslate(t, number(.translationX, 0), number(.translationY, 0), 0)
        t = CATransform3DRotate(t, number(.rotation, 0) * rad, 0, 0, 1)
        t = CATransform3DRotate(t, number(.rotationX, 0) * rad, 1, 0, 0)
        t = CATransform3DRotate(t, number(.rotationY, 0) * rad, 0, 1, 0)
        t = CATransform3DScale(t, number(.scaleX, 1) * s, number(.scaleY, 1) * s, 1)
        return CATransform3DTranslate(t, -cx, -cy, 0)
    }
}

/// Which layers `.tuneLayers` changes. Matched on the layer's class name.
struct LayerTarget {
    let name: String
    let matches: (CALayer) -> Bool

    /// Layers without sublayers that have a size – every drawn element (default).
    static let leaves = LayerTarget(name: ".leaves") { ($0.sublayers ?? []).isEmpty && $0.bounds.width > 0 && $0.bounds.height > 0 }
    static let all = LayerTarget(name: ".all") { _ in true }
    /// CGDrawingLayer – Text, button labels, anything SwiftUI draws with Core Graphics.
    static let text = className("CGDrawingLayer", name: ".text")
    /// ColorShapeLayer & co – SF Symbols, filled shapes.
    static let shape = className("ShapeLayer", name: ".shape")
    static let gradient = className("GradientLayer", name: ".gradient")
    /// The Liquid Glass backdrop (use .tune for its filter inputs).
    static let glass = LayerTarget(name: ".glass") { BoneGlassLayers.filters(on: $0).contains(where: \.isGlass) }

    static func className(_ fragment: String, name: String? = nil) -> LayerTarget {
        LayerTarget(name: name ?? ".className(\"\(fragment)\")") { String(describing: type(of: $0)).contains(fragment) }
    }
    static func custom(_ name: String, _ matches: @escaping (CALayer) -> Bool) -> LayerTarget {
        LayerTarget(name: name, matches: matches)
    }
    static func || (a: LayerTarget, b: LayerTarget) -> LayerTarget {
        LayerTarget(name: "\(a.name) || \(b.name)") { a.matches($0) || b.matches($0) }
    }

    /// The narrowest preset that matches a layer (for Copy Swift).
    static func preset(for layer: CALayer) -> LayerTarget {
        for t in [text, shape, gradient, glass] where t.matches(layer) { return t }
        return className(String(describing: type(of: layer)))
    }
}

// MARK: - Applying

/// Puts a LayerTuning on one layer – idempotent, so it can run every tick.
enum BoneLayerApplier {

    private final class State {
        var base = CATransform3DIdentity     // SwiftUI's own transform
        var applied: CATransform3D?          // what Bone last set
    }
    private static let states = NSMapTable<CALayer, State>.weakToStrongObjects()

    /// Returns a line per change (for logs).
    @discardableResult
    static func apply(_ t: LayerTuning, to layer: CALayer, generation: Int) -> [String] {
        var changes: [String] = []
        func set(_ key: String, _ value: Any?) {
            let current = layer.value(forKey: key)
            if let current, let value, BoneGlassLayers.same(current, value) { return }
            if current == nil, value == nil { return }
            layer.setValue(value, forKey: key)
            changes.append("\(key): \(current.map { "\($0)" } ?? "nil") → \(value.map { "\($0)" } ?? "nil")")
        }

        for (p, v) in t.values {
            guard let key = p.key else { continue }
            set(key, v.object)
        }

        // transform – composed with whatever SwiftUI set
        let state = states.object(forKey: layer) ?? { let s = State(); states.setObject(s, forKey: layer); return s }()
        let current = layer.transform
        if let applied = state.applied, !CATransform3DEqualToTransform(current, applied) { state.base = current }
        if state.applied == nil { state.base = current }
        if t.hasTransform {
            let final = CATransform3DConcat(t.transform(for: layer), state.base)
            if !CATransform3DEqualToTransform(current, final) {
                layer.transform = final
                changes.append("transform")
            }
            state.applied = final
        } else if state.applied != nil {
            if CATransform3DEqualToTransform(current, state.applied!) { layer.transform = state.base }
            state.applied = nil
        }

        // filters – ours are named "bone.<generation>.<i>", SwiftUI's are kept in front
        let existing = (layer.filters as? [NSObject]) ?? []
        let swiftUIs = existing.filter { !BoneGlassLayers.ident($0).name.hasPrefix("bone.") }
        let ours = existing.map { BoneGlassLayers.ident($0).name }.filter { $0.hasPrefix("bone.") }
        if case .filters(let list)? = t.values[.filters] {
            let names = list.indices.map { "bone.\(generation).\($0)" }
            if ours != names {
                layer.filters = swiftUIs + list.enumerated().compactMap { $1.make(name: names[$0]) }
                changes.append("filters: " + list.map(\.swift).joined(separator: ", "))
            }
        } else if !ours.isEmpty {
            layer.filters = swiftUIs.isEmpty ? nil : swiftUIs
        }

        for (k, v) in t.raw {
            let current = layer.value(forKeyPath: k)
            if let current, BoneGlassLayers.same(current, v) { continue }
            layer.setValue(v, forKeyPath: k)
            changes.append("\(k) → \(v)")
        }
        return changes
    }
}

// MARK: - Modifier

extension View {

    /// Overrides properties of the layers SwiftUI draws this view into.
    /// - Parameters:
    ///   - target: which layers – `.leaves` (default), `.text`, `.shape`, `.gradient`, `.glass`, `.all`, `.className("…")`.
    ///   - log: optional file name; writes what changed, once.
    func tuneLayers(_ tuning: LayerTuning, where target: LayerTarget = .leaves, log: String? = nil) -> some View {
        BoneLayerTuneHost(tuning: tuning, target: target, log: log) { self }
    }

    /// Writes the layer tree of this view – classes, frames, filters, which targets match.
    func dumpLayers(_ fileName: String, after delay: Double = 1.5) -> some View {
        BoneLayerDumpHost(fileName: fileName, delay: delay) { self }
    }
}

struct BoneLayerTuneHost<Content: View>: UIViewControllerRepresentable {
    let tuning: LayerTuning
    let target: LayerTarget
    let log: String?
    let content: Content

    init(tuning: LayerTuning, target: LayerTarget, log: String?, @ViewBuilder content: () -> Content) {
        self.tuning = tuning
        self.target = target
        self.log = log
        self.content = content()
    }

    func makeUIViewController(context: Context) -> UIHostingController<Content> {
        let hosting = UIHostingController(rootView: content)
        hosting.view.backgroundColor = .clear
        hosting.sizingOptions = [.intrinsicContentSize]
        context.coordinator.start(on: hosting.view, tuning: tuning, target: target, log: log)
        return hosting
    }

    func updateUIViewController(_ hosting: UIHostingController<Content>, context: Context) {
        hosting.rootView = content
        context.coordinator.update(tuning: tuning, target: target)
    }

    /// Size of the content, not of the space offered (keeps stacks tight).
    func sizeThatFits(_ proposal: ProposedViewSize, uiViewController: UIHostingController<Content>, context: Context) -> CGSize? {
        uiViewController.sizeThatFits(in: CGSize(width: proposal.width ?? .infinity, height: proposal.height ?? .infinity))
    }

    func makeCoordinator() -> BoneLayerTuner { BoneLayerTuner() }

    static func dismantleUIViewController(_ vc: UIHostingController<Content>, coordinator: BoneLayerTuner) {
        coordinator.stop()
    }
}

final class BoneLayerTuner {
    private var tuning: LayerTuning = [:]
    private var target = LayerTarget.leaves
    private var generation = 0
    private weak var root: UIView?
    private var link: CADisplayLink?
    private var log: String?
    private var logged = false

    func start(on view: UIView, tuning: LayerTuning, target: LayerTarget, log: String?) {
        root = view
        self.tuning = tuning
        self.target = target
        self.log = log
        let l = CADisplayLink(target: BoneLinkTarget { [weak self] in self?.tick() }, selector: #selector(BoneLinkTarget.step))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 4, maximum: 10, preferred: 8)
        l.add(to: .main, forMode: .common)
        link = l
    }

    func update(tuning: LayerTuning, target: LayerTarget) {
        self.tuning = tuning
        self.target = target
        generation += 1     // new filter objects for new inputs
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    private func tick() {
        guard let root else { stop(); return }
        var changes: [String] = []
        func walk(_ l: CALayer) {
            if target.matches(l), !BoneGlassPanelModel.shared.layerEditor.holds(l) {
                let c = BoneLayerApplier.apply(tuning, to: l, generation: generation)
                changes += c.map { "\(type(of: l)) \($0)" }
            }
            l.sublayers?.forEach(walk)
        }
        root.layer.sublayers?.forEach(walk)
        if let log, !logged, !changes.isEmpty {
            logged = true
            let text = "BONE · tuneLayers \(target.name)\nOS: \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)\n\n"
                + changes.joined(separator: "\n") + "\n"
            BoneCapture.writeData(Data(text.utf8), fileName: log)
        }
    }
}

// MARK: - Dump

struct BoneLayerDumpHost<Content: View>: UIViewControllerRepresentable {
    let fileName: String
    let delay: Double
    let content: Content

    init(fileName: String, delay: Double, @ViewBuilder content: () -> Content) {
        self.fileName = fileName
        self.delay = delay
        self.content = content()
    }

    func makeUIViewController(context: Context) -> UIHostingController<Content> {
        let hosting = UIHostingController(rootView: content)
        hosting.view.backgroundColor = .clear
        hosting.sizingOptions = [.intrinsicContentSize]
        let fileName = fileName
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak view = hosting.view] in
            guard let view else { return }
            BoneCapture.writeData(Data(BoneLayerDump.text(for: view.layer, in: view.window).utf8), fileName: fileName)
        }
        return hosting
    }

    func updateUIViewController(_ hosting: UIHostingController<Content>, context: Context) {
        hosting.rootView = content
    }

    /// Size of the content, not of the space offered (keeps stacks tight).
    func sizeThatFits(_ proposal: ProposedViewSize, uiViewController: UIHostingController<Content>, context: Context) -> CGSize? {
        uiViewController.sizeThatFits(in: CGSize(width: proposal.width ?? .infinity, height: proposal.height ?? .infinity))
    }
}

enum BoneLayerDump {
    static func text(for root: CALayer, in window: UIWindow?) -> String {
        var t = "BONE · dumpLayers\nOS: \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)\n"
        t += "targets: .text = CGDrawingLayer · .shape = *ShapeLayer · .gradient = GradientLayer · .glass · leaf = no sublayers\n\n"
        func line(_ l: CALayer, _ depth: Int) {
            let r = window.map { BoneGlassLayers.screenFrame(of: l, in: $0) } ?? l.frame
            var parts = ["\(type(of: l))"]
            if let d = l.delegate { parts.append("delegate=\(type(of: d))") }
            parts.append("\(Int(r.minX)),\(Int(r.minY)) \(Int(r.width))×\(Int(r.height))")
            if l.opacity < 1 { parts.append("opacity=\(l.opacity)") }
            if l.isHidden { parts.append("hidden") }
            if !CATransform3DIsIdentity(l.transform) { parts.append("transform") }
            if l.cornerRadius > 0 { parts.append("cornerRadius=\(l.cornerRadius)") }
            if l.borderWidth > 0 { parts.append("border=\(l.borderWidth)") }
            if l.shadowOpacity > 0 { parts.append("shadow=\(l.shadowOpacity)") }
            if let c = l.contents { parts.append("contents=\(CFCopyTypeIDDescription(CFGetTypeID(c as CFTypeRef)) ?? "?" as CFString)") }
            let fs = BoneGlassLayers.filters(on: l)
            if !fs.isEmpty { parts.append("filters=[\(fs.map(\.type).joined(separator: ", "))]") }
            if let cf = l.compositingFilter { parts.append("compositing=\(cf)") }
            if l.mask != nil { parts.append("mask") }
            var targets = [LayerTarget.text, .shape, .gradient, .glass].filter { $0.matches(l) }.map(\.name)
            if LayerTarget.leaves.matches(l) { targets.append(".leaves") }
            if !targets.isEmpty { parts.append("→ " + targets.joined(separator: " ")) }
            t += String(repeating: "  ", count: depth) + parts.joined(separator: "  ") + "\n"
            l.sublayers?.forEach { line($0, depth + 1) }
        }
        line(root, 0)
        return t
    }
}

#endif
