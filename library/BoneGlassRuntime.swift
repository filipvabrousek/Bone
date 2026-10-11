//
//  BoneGlassRuntime.swift
//  Bone-27
//
//  .dumpGlass and .tune for the platforms where Bone reaches Liquid Glass
//  through the Objective-C runtime instead of UIKit: watchOS (UIKit and
//  CALayer exist but are hidden from the SDK) and macOS (AppKit hosts the same
//  SwiftUI glass). On all three platforms a glass shape is the same tree –
//  SDFLayer → CABackdropLayer with a glassBackground filter → CASDFElementLayer –
//  so one engine walks it: find the layers carrying filters, read every input,
//  write overrides through "filters.<name>.<input>". The platform files decide
//  which windows to walk and which layers lie in the modified view
//  (BoneWatch.swift, BoneMac.swift).
//
//  Research / simulator use only — private Core Animation keys, never ship it.
//

#if os(watchOS) || os(macOS)

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
        #if os(watchOS)
        let name = "watchOS"
        #else
        let name = "macOS"
        #endif
        return "\(name) \(os.majorVersion).\(os.minorVersion)"
    }

    /// The .dumpGlass report, in the iOS format.
    static func dumpGlass(_ layers: [Found], only: [GlassInput]?) -> String {
        struct Row { var path: String; var slot: String; var type: String; var isGlass: Bool; var inputs: [(String, Any?)] }
        var found: [Row] = []
        for (layer, path) in layers {
            for f in filters(on: layer) {
                found.append(Row(path: path, slot: f.slot, type: f.type, isGlass: f.type.lowercased().contains("glass"),
                                 inputs: BoneFilterInputs.keys(of: f.filter).map { ($0, f.filter.value(forKey: $0)) }))
            }
        }
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var t = "BONE · dumpGlass\nOS: \(osLine) · captured: \(df.string(from: Date()))\n"
        t += "inputs: " + (only.map { $0.map(\.caseName).joined(separator: ", ") } ?? "all") + "\n"
        let glass = found.filter(\.isGlass)
        t += "glass filters: \(glass.count)\n"
        if glass.isEmpty { t += "\n(no glass filter found – is a glass style applied, and has it rendered?)\n" }
        let wanted = only.map { Set($0.map(\.rawValue)) }
        func label(_ key: String) -> String { GlassInput(rawValue: key).map { "\($0.caseName)  (\(key))" } ?? key }
        for (i, f) in found.enumerated() where f.isGlass || wanted == nil {
            t += "\n===== [\(i)] \(f.type)  (\(f.slot) on \(f.path)) =====\n"
            let rows = f.inputs.filter { wanted == nil || wanted!.contains($0.0) }
            if rows.isEmpty { t += "   (none of the requested inputs)\n"; continue }
            let width = rows.map { label($0.0).count }.max() ?? 0
            for (key, value) in rows {
                let l = label(key)
                t += "   " + l + String(repeating: " ", count: width - l.count) + " = " + BoneGlassFormat.value(value) + "\n"
            }
        }
        return t
    }

    /// Writes `values` into every matching filter input; returns what changed.
    static func apply(_ values: [String: Any], to layers: [Found]) -> [String] {
        var changes: [String] = []
        for (layer, _) in layers {
            for f in filters(on: layer) {
                for (key, newValue) in values {
                    guard let input = input(key, name: f.name, type: f.type) else { continue }
                    let path = "\(f.slot).\(f.name).\(input)"
                    let current = layer.value(forKeyPath: path)
                    if let current, same(current, newValue) { continue }
                    layer.setValue(newValue, forKeyPath: path)
                    changes.append("\(className(layer)) \(path): \(current.map { BoneGlassFormat.value($0) } ?? "nil") → \(BoneGlassFormat.value(newValue))")
                }
            }
        }
        return changes
    }

    /// "inputBlurRadius" → every glass filter; "vibrantColorMatrix.inputColorMatrix" → that filter only.
    static func input(_ key: String, name: String, type: String) -> String? {
        if let dot = key.firstIndex(of: ".") {
            let target = key[..<dot]
            return target == name || target == type ? String(key[key.index(after: dot)...]) : nil
        }
        return type.lowercased().contains("glass") ? key : nil
    }

    /// Whether a filter input already holds a value (numbers by value, colours with CFEqual).
    static func same(_ a: Any, _ b: Any) -> Bool {
        if let x = a as? NSNumber, let y = b as? NSNumber { return abs(x.doubleValue - y.doubleValue) < 1e-9 }
        if CFGetTypeID(a as CFTypeRef) == CGColor.typeID, CFGetTypeID(b as CFTypeRef) == CGColor.typeID {
            return CFEqual(a as CFTypeRef, b as CFTypeRef)
        }
        if let x = a as? NSObject, let y = b as? NSObject { return x.isEqual(y) }
        return false
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
        let text = "BONE · tune\nOS: \(BoneGlassRuntime.osLine)\n"
            + "requested: \(values.keys.sorted().map { "\($0)=\(BoneGlassFormat.value(values[$0]))" }.joined(separator: ", "))\n\n"
            + changes.joined(separator: "\n") + "\n"
        write(text, log)
    }
}

#endif
