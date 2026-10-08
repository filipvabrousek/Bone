//
//  BoneGlassCore.swift
//  Bone-27
//
//  Shared plumbing for the Liquid Glass tools (.tune, .probeGlass,
//  .glassPanel): finding glass layers and their filters, value kinds,
//  colour matrices, JSON values and capturing the composited screen.
//
//  Research / simulator use only — private Core Animation keys, never ship it.
//

#if canImport(UIKit)

import UIKit

// MARK: - Filters on a layer

/// One Core Animation filter, addressed the way -setValue:forKeyPath: wants
/// it: "<slot>.<name>.<inputKey>".
struct BoneFilterRef {
    weak var layer: CALayer?
    let slot: String          // "filters" or "backgroundFilters"
    let name: String          // filter name (the type, unless renamed)
    let type: String          // e.g. "glassBackground", "vibrantColorMatrix"

    var isGlass: Bool { type.lowercased().contains("glass") }
    func path(_ key: String) -> String { "\(slot).\(name).\(key)" }
    func value(_ key: String) -> Any? { layer?.value(forKeyPath: path(key)) }
    func set(_ key: String, _ value: Any) { layer?.setValue(value, forKeyPath: path(key)) }
    /// Removes an input again (the filter falls back to its default).
    func remove(_ key: String) { layer?.setValue(nil, forKeyPath: path(key)) }

    var filter: NSObject? {
        (layer?.value(forKey: slot) as? [NSObject])?.first { BoneGlassLayers.ident($0).name == name }
    }
    /// Input keys currently set on the filter.
    var keys: [String] { filter.map { BoneFilterInputs.keys(of: $0) } ?? [] }
}

enum BoneGlassLayers {

    static func ident(_ f: NSObject) -> (name: String, type: String) {
        let type = (f.value(forKey: "type") as? String) ?? String(describing: Swift.type(of: f))
        return ((f.value(forKey: "name") as? String) ?? type, type)
    }

    static func filters(on layer: CALayer) -> [BoneFilterRef] {
        var out: [BoneFilterRef] = []
        for slot in ["filters", "backgroundFilters"] {
            guard let list = layer.value(forKey: slot) as? [NSObject] else { continue }
            for f in list {
                let (name, type) = ident(f)
                out.append(BoneFilterRef(layer: layer, slot: slot, name: name, type: type))
            }
        }
        return out
    }

    /// Layers carrying a Liquid Glass filter, in drawing order (back to front).
    static func glassLayers(in root: CALayer) -> [CALayer] {
        var out: [CALayer] = []
        func walk(_ l: CALayer) {
            if filters(on: l).contains(where: \.isGlass) { out.append(l) }
            l.sublayers?.forEach(walk)
        }
        walk(root)
        return out
    }

    /// The glass element: the layer holding the backdrop (glassBackground) and
    /// its sibling CASDFLayer (vibrantColorMatrix).
    static func element(of glassLayer: CALayer) -> CALayer { glassLayer.superlayer ?? glassLayer }

    /// Every filter in an element, glass filters first.
    static func filterRefs(inElement element: CALayer) -> [BoneFilterRef] {
        var all: [BoneFilterRef] = []
        func walk(_ l: CALayer) { all += filters(on: l); l.sublayers?.forEach(walk) }
        walk(element)
        return all.filter(\.isGlass) + all.filter { !$0.isGlass }
    }

    /// Frame of a layer in screen points.
    static func screenFrame(of layer: CALayer, in window: UIWindow) -> CGRect {
        layer.convert(layer.bounds, to: window.layer).offsetBy(dx: window.frame.minX, dy: window.frame.minY)
    }

    static func isAttached(_ layer: CALayer, to window: UIWindow) -> Bool {
        var l: CALayer? = layer
        while let c = l { if c === window.layer { return true }; l = c.superlayer }
        return false
    }

    static func same(_ a: Any, _ b: Any) -> Bool {
        if let x = a as? NSNumber, let y = b as? NSNumber { return x.doubleValue == y.doubleValue }
        return (a as AnyObject).isEqual(b)
    }
}

// MARK: - Value kinds

enum BoneValueKind: String {
    case number, toggle, color, size, matrix, rect, image, array, string, unknown

    /// From the current value when there is one, otherwise from the key name.
    static func of(key: String, current: Any?) -> BoneValueKind {
        if let v = current {
            if v is NSNumber { return isToggle(key) ? .toggle : .number }
            let typeID = CFGetTypeID(v as CFTypeRef)
            if typeID == CGColor.typeID { return .color }
            if typeID == CGImage.typeID { return .image }
            if BoneColorMatrix.floats(from: v) != nil { return .matrix }
            if let n = v as? NSValue {
                let t = String(cString: n.objCType)
                if t.contains("CGSize") || t.contains("CGPoint") { return .size }
                if t.contains("CGRect") { return .rect }
                return .unknown
            }
            if v is NSString { return .string }
            if v is NSArray { return .array }
            return .unknown
        }
        if key == "inputSourceSublayerName" { return .string }
        if key.hasSuffix("Image") || key == "inputColorMap" { return .image }
        if key.hasSuffix("Values") && key != "inputPremultipliedValues" { return .array }
        if key == "inputColorMatrix" { return .matrix }
        if key.hasSuffix("Bounds") { return .rect }
        if let g = GlassInput(rawValue: key) {
            if g.valueKind == "color" { return .color }
            if g.valueKind == "size" { return .size }
        }
        if key.hasSuffix("Color") || key.range(of: "Color[0-9]$", options: .regularExpression) != nil { return .color }
        return isToggle(key) ? .toggle : .number
    }

    static func isToggle(_ key: String) -> Bool {
        ["Enabled", "Adaptive", "AllowsGroup", "BackdropAware", "Dither", "HSVSpace", "HardEdges",
         "NormalizeEdges", "ExtendEdges", "Linear", "Reversed", "PremultipliedValues", "Mask", "PreserveHue"]
            .contains { key.hasSuffix($0) }
    }
}

// MARK: - Colour matrix

/// CAColorMatrix: 4 rows (R, G, B, A out) × 5 (r, g, b, a, bias), boxed in an NSValue.
enum BoneColorMatrix {
    static let objCType = "{CAColorMatrix=ffffffffffffffffffff}"
    static let identity: [Float] = [1, 0, 0, 0, 0,  0, 1, 0, 0, 0,  0, 0, 1, 0, 0,  0, 0, 0, 1, 0]
    static let grayscale: [Float] = [0.2126, 0.7152, 0.0722, 0, 0,  0.2126, 0.7152, 0.0722, 0, 0,
                                     0.2126, 0.7152, 0.0722, 0, 0,  0, 0, 0, 1, 0]
    static let invert: [Float] = [-1, 0, 0, 0, 1,  0, -1, 0, 0, 1,  0, 0, -1, 0, 1,  0, 0, 0, 1, 0]
    static let swapRedBlue: [Float] = [0, 0, 1, 0, 0,  0, 1, 0, 0, 0,  1, 0, 0, 0, 0,  0, 0, 0, 1, 0]

    static func value(_ m: [Float]) -> NSValue {
        let f = Array((m + Array(repeating: 0, count: 20)).prefix(20))
        return f.withUnsafeBytes { NSValue(bytes: $0.baseAddress!, objCType: objCType) }
    }

    static func floats(from v: Any) -> [Float]? {
        guard let val = v as? NSValue, !(v is NSNumber),
              String(cString: val.objCType).hasPrefix("{CAColorMatrix=") else { return nil }
        var f = [Float](repeating: 0, count: 20)
        f.withUnsafeMutableBytes { val.getValue($0.baseAddress!, size: $0.count) }
        return f
    }
}

// MARK: - JSON values

/// Filter input values as JSON: numbers stay numbers, the rest are tagged –
/// {"color": [r, g, b, a]}, {"size": [w, h]}, {"matrix": [20 numbers]}.
enum BoneGlassJSON {

    static func encode(_ v: Any) -> Any? {
        if let n = v as? NSNumber { return n }
        if CFGetTypeID(v as CFTypeRef) == CGColor.typeID {
            let c = v as! CGColor
            let srgb = c.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil) ?? c
            return ["color": (srgb.components ?? []).map { Double($0) }]
        }
        if let m = BoneColorMatrix.floats(from: v) { return ["matrix": m.map { Double($0) }] }
        if let val = v as? NSValue, String(cString: val.objCType).contains("CGSize") {
            return ["size": [Double(val.cgSizeValue.width), Double(val.cgSizeValue.height)]]
        }
        return nil
    }

    static func decode(_ j: Any) -> Any? {
        if let n = j as? NSNumber { return n }
        guard let d = j as? [String: Any] else { return nil }
        if let c = (d["color"] as? [NSNumber])?.map(\.doubleValue), c.count >= 3 {
            return CGColor(srgbRed: c[0], green: c[1], blue: c[2], alpha: c.count > 3 ? c[3] : 1)
        }
        if let s = (d["size"] as? [NSNumber])?.map(\.doubleValue), s.count == 2 {
            return NSValue(cgSize: CGSize(width: s[0], height: s[1]))
        }
        if let m = (d["matrix"] as? [NSNumber])?.map(\.floatValue), m.count == 20 {
            return BoneColorMatrix.value(m)
        }
        return nil
    }

    /// Reads {"glassBackground": {"blurRadius": 0, …}, "vibrantColorMatrix": {…}}
    /// (what the panel saves) into tuner keys. Keys may be GlassInput case
    /// names or Core Animation keys; top-level values apply to glass filters.
    static func tunerValues(from data: Data) -> [String: Any]? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func caKey(_ k: String) -> String { GlassInput.named(k)?.rawValue ?? k }
        var out: [String: Any] = [:]
        for (k, v) in obj {
            if let section = v as? [String: Any], decode(section) == nil {
                let glass = k.lowercased().contains("glass")
                for (ik, iv) in section {
                    if let value = decode(iv) { out[glass ? caKey(ik) : "\(k).\(caKey(ik))"] = value }
                }
            } else if let value = decode(v) {
                out[caKey(k)] = value
            }
        }
        return out
    }
}

// MARK: - Screen capture

enum BoneScreen {

    /// The composited screen – every window, backdrop and filter – via UIKit's
    /// private _UICreateScreenUIImage. (drawHierarchy does not reproduce Liquid
    /// Glass; this matches `simctl io screenshot` pixel for pixel.)
    static func capture() -> CGImage? {
        typealias Create = @convention(c) () -> Unmanaged<UIImage>?
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_UICreateScreenUIImage") else { return nil }
        return unsafeBitCast(sym, to: Create.self)()?.takeRetainedValue().cgImage
    }

    static func width(of window: UIWindow) -> CGFloat {
        #if os(visionOS)
        return window.bounds.width
        #else
        return window.windowScene?.screen.bounds.width ?? window.bounds.width
        #endif
    }
}

/// RGBA pixels of a region, for counting what changed.
struct BonePixels {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    init?(_ image: CGImage, crop: CGRect) {
        guard let cut = image.cropping(to: crop) else { return nil }
        let w = cut.width, h = cut.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let ok: Bool = buf.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cut, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        width = w; height = h; bytes = buf
    }

    /// Pixels whose largest channel difference exceeds `tolerance`.
    func changed(from other: BonePixels, tolerance: Int = 8) -> Int {
        guard other.bytes.count == bytes.count else { return width * height }
        var n = 0
        bytes.withUnsafeBufferPointer { a in
            other.bytes.withUnsafeBufferPointer { b in
                var i = 0
                while i < a.count {
                    if abs(Int(a[i]) - Int(b[i])) > tolerance
                        || abs(Int(a[i + 1]) - Int(b[i + 1])) > tolerance
                        || abs(Int(a[i + 2]) - Int(b[i + 2])) > tolerance { n += 1 }
                    i += 4
                }
            }
        }
        return n
    }

    func image() -> CGImage? {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

// MARK: - GlassInput helpers

extension GlassInput {
    static let byCaseName: [String: GlassInput] = Dictionary(uniqueKeysWithValues: allCases.map { ($0.caseName, $0) })
    static func named(_ caseName: String) -> GlassInput? { byCaseName[caseName] }

    /// Section in the panel.
    var group: String {
        let groups: [(String, String)] = [
            ("aberration", "Aberration"), ("bleed", "Bleed"), ("blurFill", "Blur fill"), ("blur", "Blur"),
            ("clamp", "Clamp"), ("faceColorMatrix", "Face colour matrix"), ("face", "Face"),
            ("innerRefraction", "Refraction"), ("outerRefraction", "Refraction"), ("refraction", "Refraction"),
            ("keyFillHighlight", "Highlight"), ("maxHeadroom", "HDR"), ("ringShadow", "Ring shadow"),
            ("sdr", "SDR"), ("shadow", "Shadow"),
        ]
        return groups.first { caseName.hasPrefix($0.0) }?.1 ?? "Other"
    }
}

#endif
