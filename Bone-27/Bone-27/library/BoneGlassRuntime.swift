//
//  BoneGlassRuntime.swift
//  Bone-27
//
//  .dumpGlass and .tune on watchOS, where UIKit and CALayer exist but are
//  hidden from the SDK, so Bone reaches Liquid Glass through the Objective-C
//  runtime. The glass is the same tree as on iOS and macOS – SDFLayer →
//  CABackdropLayer with a glassBackground filter → CASDFElementLayer – and the
//  report, the log and the rules for applying values are shared with their
//  engine (BoneGlassReport in BoneGlassTuning.swift; BoneGlassEngine.swift).
//  BoneWatch.swift decides which layers lie in the modified view.
//
//  Research / simulator use only — private Core Animation keys, never ship it.
//

#if DEBUG   // Bone is private API: it compiles to nothing outside Debug builds

#if os(watchOS)

import Foundation
import ObjectiveC
import CoreGraphics

enum BoneGlassRuntime {

    typealias Found = (layer: NSObject, path: String)

    /// -valueForKey: only when the object answers the getter (an unknown key raises).
    static func get(_ object: NSObject, _ key: String) -> NSObject? {
        guard object.responds(to: NSSelectorFromString(key)) else { return nil }
        return object.value(forKey: key) as? NSObject
    }

    static func className(_ object: NSObject) -> String {
        object_getClass(object).map { NSStringFromClass($0) } ?? "?"
    }

    /// (slot, filter, name, type) for every filter on a layer.
    static func filters(on layer: NSObject) -> [(slot: String, filter: NSObject, name: String, type: String)] {
        var out: [(String, NSObject, String, String)] = []
        for slot in ["filters", "backgroundFilters"] {
            for f in (get(layer, slot) as? [NSObject]) ?? [] {
                let type = (get(f, "type") as? String) ?? className(f)
                out.append((slot, f, (get(f, "name") as? String) ?? type, type))
            }
        }
        return out.map { (slot: $0.0, filter: $0.1, name: $0.2, type: $0.3) }
    }

    /// Layers carrying filters under `roots` for which `keep(layer, root)` holds, with a path
    /// like the iOS dump ("UIWindowLayer ▹ [0]CALayer ▹ …").
    static func filterLayers(roots: [NSObject], keep: (NSObject, NSObject) -> Bool) -> [Found] {
        var out: [Found] = []
        for root in roots {
            func walk(_ layer: NSObject, _ path: String, _ depth: Int) {
                guard depth < 80 else { return }
                if !filters(on: layer).isEmpty, keep(layer, root) { out.append((layer, path)) }
                for (i, sub) in ((get(layer, "sublayers") as? [NSObject]) ?? []).enumerated() {
                    walk(sub, "\(path) ▹ [\(i)]\(className(sub))", depth + 1)
                }
            }
            walk(root, className(root), 0)
        }
        return out
    }

    /// The layer's bounds in `root`'s coordinates, through CALayer's own -convertRect:toLayer:.
    static func rect(of layer: NSObject, in root: NSObject) -> CGRect {
        typealias Convert = @convention(c) (NSObject, Selector, CGRect, NSObject?) -> CGRect
        let sel = NSSelectorFromString("convertRect:toLayer:")
        guard let cls = object_getClass(layer), let m = class_getInstanceMethod(cls, sel),
              let v = get(layer, "bounds") as? NSValue, String(cString: v.objCType).hasPrefix("{CGRect") else { return .null }
        var bounds = CGRect.zero
        v.getValue(&bounds, size: MemoryLayout<CGRect>.size)
        return unsafeBitCast(method_getImplementation(m), to: Convert.self)(layer, sel, bounds, root)
    }

    static var osLine: String {
        let os = ProcessInfo().operatingSystemVersion
        return "watchOS \(os.majorVersion).\(os.minorVersion)"
    }

    /// The .dumpGlass report, in the iOS format.
    static func dumpGlass(_ layers: [Found], only: [GlassInput]?) -> String {
        var rows: [BoneGlassFilterRow] = []
        for (layer, path) in layers {
            for f in filters(on: layer) {
                rows.append(BoneGlassFilterRow(path: path, slot: f.slot, type: f.type,
                                               inputs: BoneFilterInputs.keys(of: f.filter).map { ($0, f.filter.value(forKey: $0)) }))
            }
        }
        return BoneGlassReport.dump(rows, only: only, os: osLine)
    }

    /// Writes `values` into every matching filter input; returns what changed.
    static func apply(_ values: [String: Any], to layers: [Found]) -> [String] {
        var changes: [String] = []
        for (layer, _) in layers {
            for f in filters(on: layer) {
                for (key, newValue) in values {
                    guard let input = BoneGlassReport.input(key, name: f.name, type: f.type) else { continue }
                    let path = "\(f.slot).\(f.name).\(input)"
                    let current = layer.value(forKeyPath: path)
                    if let current, BoneGlassReport.same(current, newValue) { continue }
                    layer.setValue(newValue, forKeyPath: path)
                    changes.append(BoneGlassReport.change(layer: className(layer), path: path, from: current, to: newValue))
                }
            }
        }
        return changes
    }
}

/// Re-applies a tuning 8× a second (SwiftUI rebuilds the filter) and logs the first changes once.
final class BoneGlassRuntimeTuner {
    let values: [String: Any]
    let log: String?
    let collect: () -> [BoneGlassRuntime.Found]
    let write: (String, String) -> Void
    private var timer: Timer?
    private var logged = false

    init(values: [String: Any], log: String?,
         collect: @escaping () -> [BoneGlassRuntime.Found], write: @escaping (String, String) -> Void) {
        self.values = values
        self.log = log
        self.collect = collect
        self.write = write
    }

    func start() {
        guard !values.isEmpty, timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.125, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func tick() {
        let changes = BoneGlassRuntime.apply(values, to: collect())
        guard let log, !logged, !changes.isEmpty else { return }
        logged = true
        write(BoneGlassReport.tuneLog(values: values, changes: changes, os: BoneGlassRuntime.osLine), log)
    }
}

#endif

#endif   // DEBUG
