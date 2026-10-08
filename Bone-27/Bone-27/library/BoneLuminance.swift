//
//  BoneLuminance.swift
//  Bone-27
//
//  Lists every place in a rendered SwiftUI view where luminance-related
//  state lives — the machinery behind Liquid Glass's adaptive luminance
//  (DesignLibrary: GlassMaterialProvider.HysteresisRange.Context(luminance:colorScheme:),
//  Configuration.adaptiveLuminance(...), ...).
//
//      Button("Hello") {}.getLuminence("lum.txt")
//      Button("Hello") {}.buttonStyle(.glass).getLuminence("lum.txt")
//      Text("Hi").getLuminence("hyst.txt", keywords: ["hysteresis", "adaptive"])
//
//  Three sources are searched, for every UIView and every CALayer in the tree:
//    1. Objective-C runtime: properties and ivars whose NAME matches a keyword
//       (values read safely: object ivars via object_getIvar, scalars by offset).
//    2. Core Animation filters: layer.filters / backgroundFilters /
//       compositingFilter — filter names and all input values (CAFilter is
//       where the glass's luminance curves and colour matrices live).
//    3. Swift reflection (Mirror) of each view, the hosting view (ViewGraph,
//       renderer, ...) and the SwiftUI root value — matches on property
//       labels AND on type names (e.g. GlassMaterialProvider.HysteresisRange).
//
//  Output: <name> in Documents and, in the simulator, <project>/captures/.
//  Research / simulator use only — private introspection, never ship it.
//

#if canImport(UIKit)

import SwiftUI
import UIKit
import ObjectiveC

// MARK: - Public API

extension View {

    /// Writes every luminance-related property, ivar, Core Animation filter
    /// input and Swift-reflected value found in this view's rendered tree.
    /// `after` = seconds to wait before capturing; glass measures the
    /// backdrop luminance only after it has rendered over real content.
    func getLuminence(_ fileName: String, keywords: [String] = ["lumin"], after delay: Double = 2.0) -> some View {
        BoneKeywordProbe(fileName: fileName, keywords: keywords, delay: delay) { self }
    }

    /// Correctly spelled alias of `getLuminence(_:)`.
    func getLuminance(_ fileName: String, keywords: [String] = ["lumin"], after delay: Double = 2.0) -> some View {
        getLuminence(fileName, keywords: keywords, after: delay)
    }
}

// MARK: - Hosting wrapper (same pattern as .bone(into:))

struct BoneKeywordProbe<Content: View>: View {
    let fileName: String
    let keywords: [String]
    let delay: Double
    let content: Content

    init(fileName: String, keywords: [String], delay: Double, @ViewBuilder content: () -> Content) {
        self.fileName = fileName
        self.keywords = keywords
        self.delay = delay
        self.content = content()
    }

    var body: some View {
        Host(fileName: fileName, keywords: keywords, delay: delay, content: content)
    }

    struct Host: UIViewRepresentable {
        let fileName: String
        let keywords: [String]
        let delay: Double
        let content: Content

        func makeUIView(context: Context) -> UIView {
            let container = UIView()
            container.backgroundColor = .clear
            let hosting = UIHostingController(rootView: content)
            hosting.view.backgroundColor = .clear
            container.addSubview(hosting.view)
            hosting.view.frame = container.bounds
            hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]

            // Glass, backdrops and their filters are set up only once the
            // view is in a window and has rendered — wait like .bone() does.
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                hosting.view.setNeedsLayout()
                hosting.view.layoutIfNeeded()
                let report = BoneKeywordScanner(keywords: keywords)
                    .scan(hostingView: hosting.view, swiftUIRoot: content)
                BoneCapture.writeData(Data(report.utf8), fileName: fileName)
            }
            return container
        }

        func updateUIView(_ uiView: UIView, context: Context) {}
    }
}

// MARK: - Scanner

struct BoneKeywordHit {
    var path: String       // where in the tree
    var source: String     // objc-property / objc-ivar / ca-filter / swift-mirror ...
    var name: String
    var type: String
    var value: String
}

final class BoneKeywordScanner {
    let keywords: [String]
    private(set) var hits: [BoneKeywordHit] = []
    private var mirrorBudget = 60_000          // max Mirror nodes visited in total
    private var visitedObjects = Set<ObjectIdentifier>()
    private var viewCount = 0, layerCount = 0, filterCount = 0
    private var filterTypes: [String: Int] = [:]

    init(keywords: [String]) {
        self.keywords = keywords.map { $0.lowercased() }
    }

    private func matches(_ s: String) -> Bool {
        let l = s.lowercased()
        return keywords.contains { l.contains($0) }
    }

    private func short(_ any: Any, _ max: Int = 400) -> String {
        let s = String(describing: any).replacingOccurrences(of: "\n", with: " ")
        return s.count > max ? String(s.prefix(max)) + "…" : s
    }

    private func typeName(_ any: Any) -> String {
        String(reflecting: type(of: any))
    }

    // MARK: Entry

    func scan(hostingView: UIView, swiftUIRoot: Any) -> String {
        scanView(hostingView, path: String(describing: type(of: hostingView)))
        mirror(swiftUIRoot, path: "SwiftUI root value", depth: 0, maxDepth: 14)
        return report(root: hostingView)
    }

    // MARK: Views and layers

    private func scanView(_ view: UIView, path: String) {
        viewCount += 1
        objcMembers(of: view, path: path)
        mirror(view, path: path, depth: 0, maxDepth: 8)
        scanLayer(view.layer, path: path + " ▸ layer")
        for (i, sub) in view.subviews.enumerated() {
            scanView(sub, path: "\(path) > [\(i)]\(type(of: sub))")
        }
    }

    private func scanLayer(_ layer: CALayer, path: String) {
        layerCount += 1
        let p = "\(path)<\(type(of: layer))>"
        objcMembers(of: layer, path: p)
        // Swift CALayer subclasses (SwiftUI's SDFLayer, ...) keep their state
        // in Swift stored properties — visible to Mirror, not to the ObjC runtime.
        if NSStringFromClass(Swift.type(of: layer)).contains(".") {
            mirror(layer, path: p, depth: 0, maxDepth: 6)
        }
        if let name = layer.name, matches(name) {
            hits.append(.init(path: p, source: "layer-name", name: "name", type: "String", value: name))
        }
        scanFilters(layer.filters, slot: "filters", path: p)
        scanFilters(layer.backgroundFilters, slot: "backgroundFilters", path: p)
        if let cf = layer.compositingFilter {
            scanFilters([cf], slot: "compositingFilter", path: p)
        }
        for (i, sub) in (layer.sublayers ?? []).enumerated() where !(sub.delegate is UIView) {
            // sublayers backing a UIView are visited through scanView
            scanLayer(sub, path: "\(p) ▹ [\(i)]")
        }
    }

    // MARK: Core Animation filters (CAFilter is private; read through KVC)

    private func scanFilters(_ filters: [Any]?, slot: String, path: String) {
        guard let filters else { return }
        for (i, f) in filters.enumerated() {
            filterCount += 1
            guard let obj = f as? NSObject else {
                let s = short(f)
                if matches(s) {
                    hits.append(.init(path: path, source: "ca-\(slot)", name: "\(slot)[\(i)]", type: typeName(f), value: s))
                }
                continue
            }
            let name = (obj.responds(to: NSSelectorFromString("name")) ? obj.value(forKey: "name") : nil).map { short($0) } ?? "?"
            let type = (obj.responds(to: NSSelectorFromString("type")) ? obj.value(forKey: "type") : nil).map { short($0) } ?? String(describing: Swift.type(of: obj))
            var inputs: [String] = []
            if obj.responds(to: NSSelectorFromString("inputKeys")),
               let keys = obj.value(forKey: "inputKeys") as? [String] {
                for k in keys {
                    let v = obj.value(forKey: k).map { short($0, 160) } ?? "nil"
                    inputs.append("\(k)=\(v)")
                }
            } else {
                // No -inputKeys (CAFilter keeps inputs in a private dictionary):
                // archive the filter (CAFilter supports NSCoding) and read every
                // encoded parameter back from the keyed archive.
                inputs = archivedParameters(obj)
                if inputs.isEmpty, NSStringFromClass(Swift.type(of: obj)).contains("Filter") {
                    inputs = filterGetterValues(obj)
                }
            }
            filterTypes["\(slot): \(type)", default: 0] += 1
            let all = "type=\(type) name=\(name) " + inputs.joined(separator: " ")
            if matches(all) {
                hits.append(.init(path: path, source: "ca-\(slot)", name: "\(slot)[\(i)] \(type)",
                                  type: String(describing: Swift.type(of: obj)),
                                  value: inputs.isEmpty ? "(no inputs)" : inputs.joined(separator: " · ")))
            }
        }
    }

    /// CAFilter keeps its inputs in a private dictionary with no public way to
    /// list the keys. CAFilter supports NSCoding, so archive it, take the key
    /// NAMES of "CAFilterInputs" from the keyed archive, then read the LIVE
    /// values with -valueForKey:.
    private func archivedParameters(_ obj: NSObject) -> [String] {
        guard obj.conforms(to: NSCoding.self),
              let data = try? NSKeyedArchiver.archivedData(withRootObject: obj, requiringSecureCoding: false),
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
              let inputsBox = deref(root["CAFilterInputs"]) as? [String: Any],
              let dict = deref(inputsBox["dict"] ?? inputsBox["NS.keys"].map { _ in inputsBox }) as? [String: Any],
              let keyRefs = dict["NS.keys"] as? [Any] else { return [] }

        let keys = keyRefs.compactMap { deref($0) as? String }.sorted()
        return keys.map { k in "\(k)=\(obj.value(forKey: k).map { short($0, 240) } ?? "nil")" }
    }

    /// Method names per filter class, reported once in the context section.
    private var filterClassMethods: [String: [String]] = [:]

    private func filterGetterValues(_ obj: NSObject) -> [String] {
        let interesting = ["input", "lumin", "matrix", "amount", "radius", "color", "bias", "scale", "curve", "tint", "saturation", "brightness"]
        var out: [String] = []
        var cls: AnyClass? = Swift.type(of: obj)
        var seen = Set<String>()
        while let c = cls, c != NSObject.self {
            var count: UInt32 = 0
            if let methods = class_copyMethodList(c, &count) {
                var names: [String] = []
                for i in 0..<Int(count) {
                    let sel = NSStringFromSelector(method_getName(methods[i]))
                    names.append(sel)
                    let l = sel.lowercased()
                    guard !sel.contains(":"), !sel.hasPrefix("_"), !sel.hasPrefix("set"),
                          !sel.hasPrefix("init"), !sel.hasPrefix("copy"), !sel.hasPrefix("dealloc"),
                          !sel.hasPrefix("mutable"), interesting.contains(where: { l.contains($0) }),
                          seen.insert(sel).inserted else { continue }
                    let v = obj.value(forKey: sel).map { short($0, 200) } ?? "nil"
                    out.append("\(sel)=\(v)")
                }
                free(methods)
                filterClassMethods[NSStringFromClass(c)] = names.sorted()
            }
            cls = class_getSuperclass(c)
        }
        return out
    }

    // MARK: Objective-C properties and ivars (whole class chain)

    private func objcMembers(of obj: NSObject, path: String) {
        var cls: AnyClass? = Swift.type(of: obj)
        var seen = Set<String>()
        while let c = cls, c != NSObject.self {
            let className = NSStringFromClass(c)

            var pCount: UInt32 = 0
            if let props = class_copyPropertyList(c, &pCount) {
                for i in 0..<Int(pCount) {
                    let name = String(cString: property_getName(props[i]))
                    guard matches(name), seen.insert(name).inserted else { continue }
                    let attrs = property_getAttributes(props[i]).map { String(cString: $0) } ?? ""
                    var value = "(not read)"
                    if obj.responds(to: NSSelectorFromString(name)) {
                        value = obj.value(forKey: name).map { short($0) } ?? "nil"
                    }
                    hits.append(.init(path: path, source: "objc-property (\(className))", name: name,
                                      type: objcType(fromAttributes: attrs), value: value))
                }
                free(props)
            }

            var iCount: UInt32 = 0
            if let ivars = class_copyIvarList(c, &iCount) {
                for i in 0..<Int(iCount) {
                    let iv = ivars[i]
                    guard let n = ivar_getName(iv) else { continue }
                    let name = String(cString: n)
                    guard matches(name), seen.insert(name).inserted else { continue }
                    let enc = ivar_getTypeEncoding(iv).map { String(cString: $0) } ?? "?"
                    if enc.isEmpty, let (t, v) = swiftStoredValue(of: obj, named: name) {
                        // Swift stored property: the ObjC runtime has no type for it
                        hits.append(.init(path: path, source: "swift-ivar (\(className))", name: name, type: t, value: v))
                    } else {
                        hits.append(.init(path: path, source: "objc-ivar (\(className))", name: name,
                                          type: enc, value: readIvar(obj, iv, encoding: enc)))
                    }
                }
                free(ivars)
            }
            cls = class_getSuperclass(c)
        }
    }

    private func swiftStoredValue(of obj: AnyObject, named name: String) -> (String, String)? {
        var m: Mirror? = Mirror(reflecting: obj)
        while let cur = m {
            if let c = cur.children.first(where: { $0.label == name }) {
                return (typeName(c.value), short(c.value, 600))
            }
            m = cur.superclassMirror
        }
        return nil
    }

    private func objcType(fromAttributes a: String) -> String {
        // "T@\"NSNumber\",R,N" -> NSNumber ; "Td,N" -> d
        guard let t = a.split(separator: ",").first, t.hasPrefix("T") else { return a }
        return String(t.dropFirst()).replacingOccurrences(of: "@\"", with: "").replacingOccurrences(of: "\"", with: "")
    }

    private func readIvar(_ obj: NSObject, _ iv: Ivar, encoding enc: String) -> String {
        if enc.hasPrefix("@") {
            return object_getIvar(obj, iv).map { short($0) } ?? "nil"
        }
        let base = UnsafeRawPointer(Unmanaged.passUnretained(obj).toOpaque())
        let p = base + ivar_getOffset(iv)
        switch enc.first {
        case "f": return "\(p.load(as: Float.self))"
        case "d": return "\(p.load(as: Double.self))"
        case "B": return "\(p.load(as: Bool.self))"
        case "c": return "\(p.load(as: Int8.self))"
        case "i": return "\(p.load(as: Int32.self))"
        case "q": return "\(p.load(as: Int64.self))"
        case "Q": return "\(p.load(as: UInt64.self))"
        default:  return "(\(enc) – not decoded)"
        }
    }

    // MARK: Swift reflection

    private func mirror(_ value: Any, path: String, depth: Int, maxDepth: Int) {
        guard depth <= maxDepth, mirrorBudget > 0 else { return }
        mirrorBudget -= 1

        // cycle guard for class instances
        if Swift.type(of: value) is AnyClass {
            let id = ObjectIdentifier(value as AnyObject)
            if depth > 0 && !visitedObjects.insert(id).inserted { return }
        }

        let m = Mirror(reflecting: value)
        var children = Array(m.children)
        var sup = m.superclassMirror
        while let s = sup { children += s.children; sup = s.superclassMirror }

        for (i, child) in children.enumerated() {
            let label = child.label ?? "[\(i)]"
            let tName = typeName(child.value)
            if matches(label) || matches(tName) {
                hits.append(.init(path: path, source: "swift-mirror", name: label, type: tName, value: short(child.value, 600)))
            }
            // don't descend into UIViews/CALayers — scanView/scanLayer cover them
            if child.value is UIView || child.value is CALayer { continue }
            mirror(child.value, path: "\(path).\(label)", depth: depth + 1, maxDepth: maxDepth)
        }
    }

    // MARK: Report

    private func report(root: UIView) -> String {
        var seenHit = Set<String>()
        hits = hits.filter { seenHit.insert("\($0.path)|\($0.name)|\($0.value)").inserted }
        let os = "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var t = "BONE · keyword probe\n"
        t += "keywords: \(keywords.joined(separator: ", "))\n"
        t += "OS: \(os) · captured: \(df.string(from: Date()))\n"
        t += "scanned: \(viewCount) views, \(layerCount) layers, \(filterCount) CA filters, \(60_000 - mirrorBudget) Swift mirror nodes\n"
        t += "hits: \(hits.count)\n"

        let bySource = Dictionary(grouping: hits, by: { $0.source.components(separatedBy: " ").first ?? $0.source })
        for (s, h) in bySource.sorted(by: { $0.key < $1.key }) { t += "  \(s): \(h.count)\n" }

        // Distinct names first — the quick answer to "where is luminance used?"
        t += "\n===== distinct names =====\n"
        let names = Dictionary(grouping: hits, by: { "\($0.name)  [\($0.type)]" })
        for (n, h) in names.sorted(by: { $0.key < $1.key }) { t += "\(h.count)×  \(n)\n" }

        if !filterTypes.isEmpty {
            t += "\n===== Core Animation filters seen (context) =====\n"
            for (f, n) in filterTypes.sorted(by: { $0.key < $1.key }) { t += "\(n)×  \(f)\n" }
        }

        if !filterClassMethods.isEmpty {
            t += "\n===== filter classes and their methods (for discovering parameters) =====\n"
            for (c, m) in filterClassMethods.sorted(by: { $0.key < $1.key }) {
                t += "\(c): \(m.joined(separator: " "))\n"
            }
        }

        t += "\n===== all hits (path · source · name : type = value) =====\n"
        for h in hits {
            t += "\n\(h.path)\n   \(h.source) · \(h.name) : \(h.type)\n   = \(h.value)\n"
        }
        if hits.isEmpty {
            t += "\n(no matches – the view may not use glass, or it was not rendered yet)\n"
        }
        return t
    }
}

#endif
