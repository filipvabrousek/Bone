//
//  BoneTune.swift
//  Bone-27
//
//  Manual tuning of Liquid Glass internals.
//
//      Button("Liquid") {}
//          .glassEffect()
//          .tune(excludeShadow: true, contentLensing: false)
//
//      Button("Liquid") {}
//          .glassEffect()
//          .tune(overrides: ["inputBlurRadius": 0, "inputFaceOpacity": 0.2])
//
//  How it works: Liquid Glass is drawn by a Core Animation filter of type
//  "glassBackground" (DesignLibrary's DLCAFilter) on SwiftUI's SDFLayer.
//  Its ~70 inputs (shadow, refraction, blur, highlight, ...) are the real
//  parameters — `.dumpGlass("glass.txt")` writes the full list with values.
//  `.tune` finds every layer carrying that filter and overwrites the chosen
//  inputs through the layer's key path "filters.<name>.<input>".
//  SwiftUI rebuilds the filter on updates (hover, press, state changes), so
//  the values are re-applied a few times per second while the view is alive.
//
//  Research / simulator use only — private Core Animation keys, never ship it.
//

#if canImport(UIKit)

import SwiftUI
import UIKit

// MARK: - Typed tuning (dictionary + presets)

/// A value for a glass input: write plain literals (`0`, `0.4`, `true`)
/// or `.color(...)` / `.size(...)` for the few non-numeric inputs.
enum GlassValue: ExpressibleByFloatLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral {
    case number(Double)
    case color(CGColor)
    case size(CGSize)

    init(floatLiteral v: Double) { self = .number(v) }
    init(integerLiteral v: Int) { self = .number(Double(v)) }
    init(booleanLiteral v: Bool) { self = .number(v ? 1 : 0) }
    static func color(_ c: UIColor) -> GlassValue { .color(c.cgColor) }
    static func size(_ w: Double, _ h: Double) -> GlassValue { .size(CGSize(width: w, height: h)) }

    /// What Core Animation expects for -setValue:forKeyPath:.
    var object: Any {
        switch self {
        case .number(let d): return NSNumber(value: d)
        case .color(let c):  return c
        case .size(let s):   return NSValue(cgSize: s)
        }
    }
}

/// A set of glass input overrides. Write it as a dictionary literal,
/// combine presets with `+` (the right side wins on conflicts):
///
///     .tune([.blurRadius: 0, .faceOpacity: 0.3])
///     .tune(.noShadow + .noLensing)
///     .tune(.noShadow + [.keyFillHighlightAmount: 1, .keyFillHighlightAngle: 0.8])
struct GlassTuning: ExpressibleByDictionaryLiteral {
    var values: [GlassInput: GlassValue] = [:]
    /// Keys not (yet) in GlassInput – e.g. inputs that appear in a newer OS.
    var raw: [String: Any] = [:]

    init(dictionaryLiteral elements: (GlassInput, GlassValue)...) {
        for (k, v) in elements { values[k] = v }
    }
    init(values: [GlassInput: GlassValue] = [:], raw: [String: Any] = [:]) {
        self.values = values
        self.raw = raw
    }

    static func + (l: GlassTuning, r: GlassTuning) -> GlassTuning {
        GlassTuning(values: l.values.merging(r.values) { _, new in new },
                    raw: l.raw.merging(r.raw) { _, new in new })
    }

    /// Escape hatch: Core Animation key names as strings.
    static func raw(_ d: [String: Any]) -> GlassTuning { GlassTuning(raw: d) }

    // Presets
    static let noShadow: GlassTuning = [.shadowOpacity: 0, .shadowAmount: 0, .sdrShadowOpacity: 0, .ringShadowOpacity: 0]
    static let noLensing: GlassTuning = [.innerRefractionAmount: 0, .outerRefractionAmount: 0, .refractionOpacity: 0]
    static let noBlur: GlassTuning = [.blurRadius: 0, .blurFillBlurRadius: 0]
    static let noHighlight: GlassTuning = [.keyFillHighlightAmount: 0]
    static let noBleed: GlassTuning = [.bleedOpacity: 0, .bleedAmount: 0]
    /// Everything off: a flat, clear pane – handy as a baseline.
    static let flat: GlassTuning = .noShadow + .noLensing + .noBlur + .noHighlight + .noBleed

    /// Flattened to Core Animation keys.
    var caValues: [String: Any] {
        var d = raw
        for (k, v) in values { d[k.rawValue] = v.object }
        return d
    }
}

extension View {

    /// Overrides Liquid Glass filter inputs of this view.
    ///
    ///     Button("Liquid") {}.glassEffect().tune([.blurRadius: 0, .faceOpacity: 0.3])
    ///     Button("Liquid") {}.glassEffect().tune(.noShadow + .noLensing)
    ///
    /// - Parameter log: optional file name; writes what changed (before → after) once.
    func tune(_ tuning: GlassTuning, log: String? = nil) -> some View {
        BoneTuneHost(values: tuning.caValues, log: log) { self }
    }

    /// Shortcut kept for the first version of the API:
    /// `.tune(excludeShadow: true, contentLensing: false)` == `.tune(.noShadow + .noLensing)`.
    func tune(excludeShadow: Bool = false,
              contentLensing: Bool = true,
              overrides: [String: Any] = [:],
              log: String? = nil) -> some View {
        var t: GlassTuning = [:]
        if excludeShadow { t = t + .noShadow }
        if !contentLensing { t = t + .noLensing }
        return tune(t + .raw(overrides), log: log)
    }
}

// MARK: - Hosting wrapper

struct BoneTuneHost<Content: View>: UIViewControllerRepresentable {
    let values: [String: Any]
    let log: String?
    let content: Content

    init(values: [String: Any], log: String?, @ViewBuilder content: () -> Content) {
        self.values = values
        self.log = log
        self.content = content()
    }

    func makeUIViewController(context: Context) -> UIHostingController<Content> {
        let hosting = UIHostingController(rootView: content)
        hosting.view.backgroundColor = .clear
        hosting.sizingOptions = [.intrinsicContentSize]
        context.coordinator.start(on: hosting.view, values: values, log: log)
        return hosting
    }

    func updateUIViewController(_ hosting: UIHostingController<Content>, context: Context) {
        hosting.rootView = content
        context.coordinator.values = values
    }

    func makeCoordinator() -> BoneGlassTuner { BoneGlassTuner() }

    static func dismantleUIViewController(_ vc: UIHostingController<Content>, coordinator: BoneGlassTuner) {
        coordinator.stop()
    }
}

// MARK: - Tuner

final class BoneGlassTuner: NSObject {

    var values: [String: Any] = [:]
    private weak var root: UIView?
    private var link: CADisplayLink?
    private var log: String?
    private var logged = false
    private(set) var appliedCount = 0

    func start(on view: UIView, values: [String: Any], log: String?) {
        self.root = view
        self.values = values
        self.log = log
        guard !values.isEmpty else { return }
        let l = CADisplayLink(target: self, selector: #selector(tick))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 4, maximum: 10, preferred: 8)
        l.add(to: .main, forMode: .common)
        link = l
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick() {
        guard let root else { stop(); return }
        var changes: [String] = []
        apply(to: root.layer, changes: &changes)
        if !changes.isEmpty { appliedCount += 1 }
        if let log, !logged, !changes.isEmpty {
            logged = true
            let text = "BONE · tune\nOS: \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)\n"
                + "requested: \(values.keys.sorted().map { "\($0)=\(values[$0]!)" }.joined(separator: ", "))\n\n"
                + changes.joined(separator: "\n") + "\n"
            BoneCapture.writeData(Data(text.utf8), fileName: log)
        }
    }

    /// Walks the whole layer tree and patches every glass filter it finds.
    private func apply(to layer: CALayer, changes: inout [String]) {
        for slot in ["filters", "backgroundFilters"] {
            guard let filters = layer.value(forKey: slot) as? [NSObject] else { continue }
            for f in filters {
                let filterType = (f.value(forKey: "type") as? String) ?? ""
                guard filterType.lowercased().contains("glass") else { continue }
                let name = (f.value(forKey: "name") as? String) ?? filterType
                for (key, newValue) in values {
                    let path = "\(slot).\(name).\(key)"
                    let current = layer.value(forKeyPath: path)
                    if let current, Self.same(current, newValue) { continue }
                    layer.setValue(newValue, forKeyPath: path)
                    changes.append("\(type(of: layer)) \(path): \(current.map { "\($0)" } ?? "nil") → \(newValue)")
                }
            }
        }
        for sub in layer.sublayers ?? [] { apply(to: sub, changes: &changes) }
    }

    private static func same(_ a: Any, _ b: Any) -> Bool {
        if let x = a as? NSNumber, let y = b as? NSNumber { return x.doubleValue == y.doubleValue }
        return (a as AnyObject).isEqual(b)
    }
}

#endif
