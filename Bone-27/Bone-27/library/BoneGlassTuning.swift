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

#if canImport(UIKit) || canImport(AppKit)

#if canImport(UIKit)
import UIKit
typealias BonePlatformColor = UIColor
#else
import AppKit
typealias BonePlatformColor = NSColor
#endif

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
    static func color(_ c: BonePlatformColor) -> GlassValue { .color(c.cgColor) }
    static func size(_ w: Double, _ h: Double) -> GlassValue { .size(CGSize(width: w, height: h)) }

    /// What Core Animation expects for -setValue:forKeyPath:.
    var object: Any {
        switch self {
        case .number(let d): return NSNumber(value: d)
        case .color(let c):  return c
        case .size(let s):
            #if canImport(UIKit)
            return NSValue(cgSize: s)
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
    /// Hidden input SwiftUI never sets: chromatic dispersion (rainbow fringes).
    static let aberration: GlassTuning = [.aberrationAmount: 12, .aberrationHeight: 20]
    /// Everything off: a flat, clear pane – handy as a baseline.
    static let flat: GlassTuning = .noShadow + .noLensing + .noBlur + .noHighlight + .noBleed

    /// Flattened to Core Animation keys.
    var caValues: [String: Any] {
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
            let s = val.cgSizeValue
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
