//
//  BoneMorphValues.swift
//  Bone-27
//
//  The values of a Liquid Glass morph, frame by frame, as CSV
//  (.dumpMorph(_:) – a take of .morphScrubber() that also writes them).
//
//  An AnimationKit morph hands its animated values to the render server
//  through CAPresentationModifiers on its InProcessAnimatableLayers
//  (coordinator → layerContext → animatablePropertyStore →
//  presentationModifiers, read with Mirror). While a take is recorded the
//  clock steps the morph one frame at a time, so every frame's values belong
//  exactly to its picture: the blob's bounds and position springing out, its
//  corner radii, the lensing layer's displacement amount and blur radius,
//  the lens container's transform.
//
//  Long format – one row per frame, layer, key and scalar:
//
//      frame,time,progress,layer,key,component,value
//      0,0.000000,0.0000,blob 1,bounds,height,235.486702
//
//  Research / simulator use only — private API, never ship it.
//

#if canImport(UIKit) && !os(visionOS)

import SwiftUI
import UIKit

extension View {

    /// `.morphScrubber()` that also writes the morph's animated values, frame by frame, to a
    /// CSV file (captures/ on the simulator, Documents on a device):
    ///
    ///     Menu { … } label: { … }
    ///         .buttonStyle(.glass)
    ///         .dumpMorph("menu-morph.csv")
    func dumpMorph(_ fileName: String = "morph-values.csv", trigger: Bool = true) -> some View {
        background(BoneTimelineAnchor(speed: 1, scrubber: true, trigger: trigger, csv: fileName))
    }
}

/// One frame's values: layer → key → (component, value).
struct BoneMorphFrame {
    var values: [(layer: String, key: String, component: String, value: String)] = []
}

enum BoneMorphValues {

    /// Reads every morph layer's presentation modifiers. `names` keeps unnamed layers'
    /// labels ("blob 1", "blob 2") stable for the whole take.
    @MainActor
    static func sample(_ windows: [UIWindow], names: inout [ObjectIdentifier: String]) -> BoneMorphFrame {
        var frame = BoneMorphFrame()
        func walk(_ l: CALayer) {
            if String(describing: type(of: l)).contains("InProcessAnimatable") {
                let modifiers = presentationModifiers(of: l)
                if !modifiers.isEmpty {
                    let id = ObjectIdentifier(l)
                    if names[id] == nil {
                        let unnamed = names.values.filter { $0.hasPrefix("blob ") }.count
                        names[id] = l.name.map { $0.replacingOccurrences(of: "LiquidMorphAnimation.", with: "") }
                            ?? "blob \(unnamed + 1)"
                    }
                    let layer = names[id]!
                    for (key, value) in modifiers.sorted(by: { $0.key < $1.key }) {
                        for (component, number) in components(value) {
                            frame.values.append((layer, key, component, number))
                        }
                    }
                }
            }
            l.sublayers?.forEach(walk)
        }
        windows.forEach { walk($0.layer) }
        return frame
    }

    /// keyPath → value of the layer's CAPresentationModifiers (empty when it has none).
    static func presentationModifiers(of layer: CALayer) -> [String: Any] {
        guard let ivar = class_getInstanceVariable(object_getClass(layer), "animationCoordinator"),
              let coordinator = object_getIvar(layer, ivar) as AnyObject?,
              let context = child(coordinator, "layerContext"),
              let store = child(context, "animatablePropertyStore"),
              let modifiers = child(store, "presentationModifiers") else { return [:] }
        var out: [String: Any] = [:]
        for entry in Mirror(reflecting: modifiers).children {
            let pair = Mirror(reflecting: entry.value).children.map(\.value)
            guard pair.count == 2, let modifier = pair[1] as? NSObject,
                  let keyPath = modifier.value(forKey: "keyPath") as? String,
                  let value = modifier.value(forKey: "value") else { continue }
            out[keyPath] = value
        }
        return out
    }

    /// A labelled child through Mirror, Optionals unwrapped.
    private static func child(_ any: Any, _ label: String) -> Any? {
        guard let value = Mirror(reflecting: any).children.first(where: { $0.label == label })?.value else { return nil }
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional { return mirror.children.first?.value }
        return value
    }

    /// A value split into named scalars: points, sizes, rects, transforms (m11…m44) and
    /// other structs of doubles (corner radii: size1…size4, each width/height).
    static func components(_ value: Any) -> [(String, String)] {
        func f(_ d: Double) -> String { String(format: "%.6f", d) }
        func f(_ d: CGFloat) -> String { f(Double(d)) }
        if let n = value as? NSNumber { return [("", f(n.doubleValue))] }
        if let v = value as? NSValue {
            // the outer struct only: a CGRect's encoding, {CGRect={CGPoint=dd}{CGSize=dd}}, contains CGPoint
            let type = String(cString: v.objCType)
            if type.hasPrefix("{CGRect") {
                let r = v.cgRectValue
                return [("x", f(r.minX)), ("y", f(r.minY)), ("width", f(r.width)), ("height", f(r.height))]
            }
            if type.hasPrefix("{CGPoint") { let p = v.cgPointValue; return [("x", f(p.x)), ("y", f(p.y))] }
            if type.hasPrefix("{CGSize") { let s = v.cgSizeValue; return [("width", f(s.width)), ("height", f(s.height))] }
            if type.hasPrefix("{CATransform3D") { return transform(doubles(of: v.caTransform3DValue)) }
            // any other struct of doubles (cornerRadii: {CACornerRadii={CGSize=dd}{CGSize=dd}{CGSize=dd}{CGSize=dd}})
            if let d = structDoubles(v, type) { return labelled(d, type) }
        }
        if let data = value as? Data, data.count % 8 == 0 {
            let d: [Double] = data.withUnsafeBytes { Array($0.bindMemory(to: Double.self)) }
            if d.count == 16 { return transform(d) }
            return d.enumerated().map { ("[\($0.offset)]", f($0.element)) }
        }
        return [("", "\"" + String(describing: value).replacingOccurrences(of: "\"", with: "'") + "\"")]
    }

    /// The doubles of an NSValue whose struct is made of doubles only.
    private static func structDoubles(_ v: NSValue, _ type: String) -> [Double]? {
        // the type codes only: struct names ("{CACornerRadii=") have letters of their own
        let fields = type.replacingOccurrences(of: #"\{[^=}]*="#, with: "", options: .regularExpression)
            .filter { $0 != "}" }
        guard !fields.isEmpty, fields.allSatisfy({ $0 == "d" }) else { return nil }
        var d = [Double](repeating: 0, count: fields.count)
        d.withUnsafeMutableBytes { v.getValue($0.baseAddress!, size: $0.count) }
        return d
    }

    /// Names for a struct's doubles: its nested CGSize / CGPoint fields in order
    /// ("size1.width", "point2.y"), else [0], [1], …
    private static func labelled(_ d: [Double], _ type: String) -> [(String, String)] {
        var names: [String] = []
        var sizes = 0, points = 0
        var rest = Substring(type)
        while true {
            let size = rest.range(of: "{CGSize=dd}"), point = rest.range(of: "{CGPoint=dd}")
            if let s = size, point.map({ s.lowerBound < $0.lowerBound }) ?? true {
                sizes += 1
                names += ["size\(sizes).width", "size\(sizes).height"]
                rest = rest[s.upperBound...]
            } else if let p = point {
                points += 1
                names += ["point\(points).x", "point\(points).y"]
                rest = rest[p.upperBound...]
            } else { break }
        }
        if names.count != d.count { names = d.indices.map { "[\($0)]" } }
        return zip(names, d).map { ($0, String(format: "%.6f", $1)) }
    }

    private static func doubles(of t: CATransform3D) -> [Double] {
        [t.m11, t.m12, t.m13, t.m14, t.m21, t.m22, t.m23, t.m24,
         t.m31, t.m32, t.m33, t.m34, t.m41, t.m42, t.m43, t.m44].map(Double.init)
    }

    private static func transform(_ d: [Double]) -> [(String, String)] {
        d.enumerated().map { ("m\($0.offset / 4 + 1)\($0.offset % 4 + 1)", String(format: "%.6f", $0.element)) }
    }

    /// The take as CSV; time and progress (0 … 1) per frame.
    static func csv(_ frames: [BoneMorphFrame], step: Double) -> String {
        var out = "frame,time,progress,layer,key,component,value\n"
        let last = max(frames.count - 1, 1)
        for (i, frame) in frames.enumerated() {
            let head = String(format: "%d,%.6f,%.4f", i, Double(i) * step, Double(i) / Double(last))
            for v in frame.values {
                out += "\(head),\(v.layer),\(v.key),\(v.component),\(v.value)\n"
            }
        }
        return out
    }
}

#endif
