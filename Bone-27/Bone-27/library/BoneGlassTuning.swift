//
//  BoneGlassTuning.swift
//  Bone-27
//
//  The glass types and helpers shared by iOS and watchOS: GlassValue and
//  GlassTuning (the .tune dictionary and presets), reading a CAFilter's input
//  keys, and formatting input values for .dumpGlass. Plain Foundation and
//  Core Graphics – the platform code that finds and changes the glass lives in
//  BoneTune.swift / BoneGlassDump.swift (iOS) and BoneWatch.swift (watchOS).
//
//  Research / simulator use only — private Core Animation keys, never ship it.
//

#if DEBUG   // Bone is private API: it compiles to nothing outside Debug builds

#if canImport(UIKit) || canImport(AppKit)

#if canImport(UIKit)
import UIKit
public typealias BonePlatformColor = UIColor
#else
import AppKit
public typealias BonePlatformColor = NSColor
#endif

/// One spelling for size values on every platform (UIKit: `cgSize`, AppKit: `size`).
extension NSValue {
    #if os(macOS)
    static func bone(size: CGSize) -> NSValue { NSValue(size: size) }
    var boneSize: CGSize { sizeValue }
    #else
    static func bone(size: CGSize) -> NSValue { NSValue(cgSize: size) }
    var boneSize: CGSize { cgSizeValue }
    #endif
}

// MARK: - Typed tuning (dictionary + presets)

/// A value for a glass input: write plain literals (`0`, `0.4`, `true`)
/// or `.color(...)` / `.size(...)` for the few non-numeric inputs.
public enum GlassValue: ExpressibleByFloatLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral {
    case number(Double)
    case color(CGColor)
    case size(CGSize)

    public init(floatLiteral v: Double) { self = .number(v) }
    public init(integerLiteral v: Int) { self = .number(Double(v)) }
    public init(booleanLiteral v: Bool) { self = .number(v ? 1 : 0) }
    public static func color(_ c: BonePlatformColor) -> GlassValue { .color(c.cgColor) }
    public static func size(_ w: Double, _ h: Double) -> GlassValue { .size(CGSize(width: w, height: h)) }

    /// What Core Animation expects for -setValue:forKeyPath:.
    public var object: Any {
        switch self {
        case .number(let d): return NSNumber(value: d)
        case .color(let c):  return c
        case .size(let s):
            #if canImport(UIKit)
            return NSValue.bone(size: s)
            #else
            return NSValue(size: s)
            #endif
        }
    }
}

/// A set of glass input overrides. Write it as a dictionary literal,
/// combine presets with `+` (the right side wins on conflicts):
///
///     .tune([.blurRadius: 0, .faceOpacity: 0.3])
///     .tune(.noShadow + .noLensing)
///     .tune(.noShadow + [.keyFillHighlightAmount: 1, .keyFillHighlightAngle: 0.8])
public struct GlassTuning: ExpressibleByDictionaryLiteral {
    public var values: [GlassInput: GlassValue] = [:]
    /// Keys not (yet) in GlassInput – e.g. inputs that appear in a newer OS.
    public var raw: [String: Any] = [:]

    public init(dictionaryLiteral elements: (GlassInput, GlassValue)...) {
        for (k, v) in elements { values[k] = v }
    }
    public init(values: [GlassInput: GlassValue] = [:], raw: [String: Any] = [:]) {
        self.values = values
        self.raw = raw
    }

    public static func + (l: GlassTuning, r: GlassTuning) -> GlassTuning {
        GlassTuning(values: l.values.merging(r.values) { _, new in new },
                    raw: l.raw.merging(r.raw) { _, new in new })
    }

    /// Escape hatch: Core Animation key names as strings.
    public static func raw(_ d: [String: Any]) -> GlassTuning { GlassTuning(raw: d) }

    // Presets
    public static let noShadow: GlassTuning = [.shadowOpacity: 0, .shadowAmount: 0, .sdrShadowOpacity: 0, .ringShadowOpacity: 0]
    public static let noLensing: GlassTuning = [.innerRefractionAmount: 0, .outerRefractionAmount: 0, .refractionOpacity: 0]
    public static let noBlur: GlassTuning = [.blurRadius: 0, .blurFillBlurRadius: 0]
    public static let noHighlight: GlassTuning = [.keyFillHighlightAmount: 0]
    public static let noBleed: GlassTuning = [.bleedOpacity: 0, .bleedAmount: 0]
    /// Hidden input SwiftUI never sets: chromatic dispersion (rainbow fringes).
    public static let aberration: GlassTuning = [.aberrationAmount: 12, .aberrationHeight: 20]
    /// Everything off: a flat, clear pane – handy as a baseline.
    public static let flat: GlassTuning = .noShadow + .noLensing + .noBlur + .noHighlight + .noBleed

    /// Flattened to Core Animation keys.
    public var caValues: [String: Any] {
        var d = raw
        for (k, v) in values { d[k.rawValue] = v.object }
        return d
    }
}

// MARK: - Reading CAFilter inputs

enum BoneFilterInputs {

    /// CAFilter keeps its inputs in a private dictionary and has no API to list
    /// the keys. It supports NSCoding, so archive it and read the key NAMES of
    /// "CAFilterInputs" from the keyed archive; values are then read live with
    /// -valueForKey: by the caller.
    static func keys(of filter: NSObject) -> [String] {
        guard filter.conforms(to: NSCoding.self),
              let data = try? NSKeyedArchiver.archivedData(withRootObject: filter, requiringSecureCoding: false),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let objects = plist["$objects"] as? [Any] else { return [] }

        // CFKeyedArchiverUID prints as "<CFKeyedArchiverUID 0x… [0x…]>{value = N}"
        func deref(_ v: Any?) -> Any? {
            guard let v else { return nil }
            let d = String(describing: v)
            guard d.contains("CFKeyedArchiverUID"), let r = d.range(of: "value = "),
                  let n = Int(d[r.upperBound...].prefix { $0.isNumber }), n < objects.count else { return v }
            return objects[n]
        }

        guard let root = objects.compactMap({ $0 as? [String: Any] }).first(where: { $0["CAFilterInputs"] != nil }),
              let box = deref(root["CAFilterInputs"]) as? [String: Any],
              let dict = (box["NS.keys"] != nil ? box : deref(box["dict"])) as? [String: Any],
              let keyRefs = dict["NS.keys"] as? [Any] else { return [] }
        return keyRefs.compactMap { deref($0) as? String }.sorted()
    }
}

extension GlassInput {
    /// Swift case name, e.g. "blurRadius".
    var caseName: String { String(describing: self) }
}

// MARK: - Reports shared by every platform's glass engine

/// One filter, as the .dumpGlass report lists it.
struct BoneGlassFilterRow {
    var path: String                       // "CALayer ▹ [0]SDFLayer ▹ [1]CALayer ▹ [0]CABackdropLayer"
    var slot: String                       // "filters" or "backgroundFilters"
    var type: String                       // "glassBackground", "vibrantColorMatrix", …
    var inputs: [(key: String, value: Any?)]
    var isGlass: Bool { type.lowercased().contains("glass") }
}

/// The text of .dumpGlass and of .tune's log, and the rules .tune applies values by –
/// the same on iOS, macOS (BoneGlassEngine.swift) and watchOS (BoneGlassRuntime.swift).
enum BoneGlassReport {

    static func dump(_ rows: [BoneGlassFilterRow], only: [GlassInput]?, os: String) -> String {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var t = "BONE · dumpGlass\n"
        t += "OS: \(os) · captured: \(df.string(from: Date()))\n"
        t += "inputs: " + (only.map { $0.map(\.caseName).joined(separator: ", ") } ?? "all") + "\n"
        let glass = rows.filter(\.isGlass)
        t += "glass filters: \(glass.count)\n"
        if glass.isEmpty {
            t += "\n(no glass filter found – is .glassEffect() / a glass style applied, and has it rendered?)\n"
        }
        let wanted = only.map { Set($0.map(\.rawValue)) }
        func label(_ key: String) -> String { GlassInput(rawValue: key).map { "\($0.caseName)  (\(key))" } ?? key }
        for (i, f) in rows.enumerated() where f.isGlass || wanted == nil {
            t += "\n===== [\(i)] \(f.type)  (\(f.slot) on \(f.path)) =====\n"
            let inputs = f.inputs.filter { wanted == nil || wanted!.contains($0.key) }
            if inputs.isEmpty { t += "   (none of the requested inputs)\n"; continue }
            let width = inputs.map { label($0.key).count }.max() ?? 0
            for r in inputs {
                let l = label(r.key)
                t += "   " + l + String(repeating: " ", count: width - l.count) + " = " + BoneGlassFormat.value(r.value) + "\n"
            }
        }
        return t
    }

    /// One line of .tune's log.
    static func change(layer: String, path: String, from current: Any?, to value: Any) -> String {
        "\(layer) \(path): \(BoneGlassFormat.value(current)) → \(BoneGlassFormat.value(value))"
    }

    static func tuneLog(values: [String: Any], changes: [String], os: String) -> String {
        "BONE · tune\nOS: \(os)\n"
            + "requested: \(values.keys.sorted().map { "\($0)=\(BoneGlassFormat.value(values[$0]))" }.joined(separator: ", "))\n\n"
            + changes.joined(separator: "\n") + "\n"
    }

    /// "inputBlurRadius" → every glass filter; "vibrantColorMatrix.inputColorMatrix" → that filter only.
    static func input(_ key: String, name: String, type: String) -> String? {
        if let dot = key.firstIndex(of: ".") {
            let target = key[..<dot]
            return target == name || target == type ? String(key[key.index(after: dot)...]) : nil
        }
        return type.lowercased().contains("glass") ? key : nil
    }

    /// Whether an input already holds a value (numbers by value, colours with CFEqual).
    static func same(_ a: Any, _ b: Any) -> Bool {
        if let x = a as? NSNumber, let y = b as? NSNumber { return abs(x.doubleValue - y.doubleValue) < 1e-9 }
        if CFGetTypeID(a as CFTypeRef) == CGColor.typeID, CFGetTypeID(b as CFTypeRef) == CGColor.typeID {
            return CFEqual(a as CFTypeRef, b as CFTypeRef)
        }
        if let x = a as? NSObject, let y = b as? NSObject { return x.isEqual(y) }
        return false
    }
}

// MARK: - Formatting input values

enum BoneGlassFormat {

    static func value(_ v: Any?) -> String {
        guard let v else { return "nil" }
        if let n = v as? NSNumber {
            let d = n.doubleValue
            return d == d.rounded() && abs(d) < 1e15 ? String(Int(d)) : String(format: "%.4f", d)
        }
        if CFGetTypeID(v as CFTypeRef) == CGColor.typeID {
            let c = (v as! CGColor)
            let comps = (c.components ?? []).map { String(format: "%.3f", $0) }.joined(separator: ", ")
            return "CGColor(\(comps))"
        }
        if let val = v as? NSValue, String(cString: val.objCType).contains("CGSize") {
            #if canImport(UIKit)
            let s = val.boneSize
            #else
            let s = val.sizeValue
            #endif
            return "size(\(s.width), \(s.height))"
        }
        // struct of floats, e.g. CAColorMatrix "{CAColorMatrix=ffff…}" (4 rows × 5)
        if let val = v as? NSValue {
            let enc = String(cString: val.objCType)
            if let eq = enc.firstIndex(of: "="), enc.hasSuffix("}") {
                let fields = enc[enc.index(after: eq)..<enc.index(before: enc.endIndex)]
                if !fields.isEmpty, fields.allSatisfy({ $0 == "f" }) {
                    var floats = [Float](repeating: 0, count: fields.count)
                    floats.withUnsafeMutableBytes { val.getValue($0.baseAddress!, size: $0.count) }
                    let cols = floats.count == 20 ? 5 : floats.count
                    let rows = stride(from: 0, to: floats.count, by: cols).map {
                        floats[$0..<min($0 + cols, floats.count)].map { String(format: "%7.4f", $0) }.joined(separator: " ")
                    }
                    let name = enc.dropFirst().prefix { $0 != "=" }
                    return "\(name) [" + rows.joined(separator: " | ") + "]"
                }
            }
        }
        if let data = v as? Data, data.count % 4 == 0, data.count <= 128 {   // e.g. a 4×5 colour matrix
            let floats = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
            return "[" + floats.map { String(format: "%.4f", $0) }.joined(separator: ", ") + "]"
        }
        return String(describing: v).replacingOccurrences(of: "\n", with: " ")
    }
}

#endif

#endif   // DEBUG
