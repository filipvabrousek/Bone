//
//  BoneGlassDump.swift
//  Bone-27
//
//  Dumps Liquid Glass rendering parameters – the inputs of the
//  "glassBackground" Core Animation filter – to a text file.
//
//      Button("Liquid") {}.glassEffect().dumpGlass("glass.txt")
//      Button("Liquid") {}.glassEffect().dumpGlass("glass.txt", only: [.blurRadius, .shadowOpacity])
//
//      // verify a tuning: dump AFTER .tune
//      Button("Liquid") {}.glassEffect()
//          .tune(.noShadow)
//          .dumpGlass("tuned.txt", only: [.shadowOpacity, .ringShadowOpacity])
//
//  Same keys as .tune (GlassInput). Without `only:` every input of every
//  glass filter is written, plus the other filters on the same layers
//  (e.g. vibrantColorMatrix). Output: Documents and, in the simulator,
//  <project>/captures/.
//
//  Research / simulator use only — private Core Animation keys, never ship it.
//

#if canImport(UIKit)

import SwiftUI
import UIKit

extension View {

    /// Writes the Liquid Glass filter inputs of this view to `fileName`.
    /// - Parameters:
    ///   - only: just these inputs; `nil` (default) writes all of them.
    ///   - after: seconds to wait, so the glass has rendered (and `.tune` has applied).
    func dumpGlass(_ fileName: String, only: [GlassInput]? = nil, after delay: Double = 1.5) -> some View {
        BoneGlassDumpHost(fileName: fileName, only: only, delay: delay) { self }
    }
}

// MARK: - Hosting wrapper

struct BoneGlassDumpHost<Content: View>: UIViewControllerRepresentable {
    let fileName: String
    let only: [GlassInput]?
    let delay: Double
    let content: Content

    init(fileName: String, only: [GlassInput]?, delay: Double, @ViewBuilder content: () -> Content) {
        self.fileName = fileName
        self.only = only
        self.delay = delay
        self.content = content()
    }

    func makeUIViewController(context: Context) -> UIHostingController<Content> {
        let hosting = UIHostingController(rootView: content)
        hosting.view.backgroundColor = .clear
        hosting.sizingOptions = [.intrinsicContentSize]
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak view = hosting.view] in
            guard let view else { return }
            let text = BoneGlassDumper(only: only).dump(view)
            BoneCapture.writeData(Data(text.utf8), fileName: fileName)
        }
        return hosting
    }

    func updateUIViewController(_ hosting: UIHostingController<Content>, context: Context) {
        hosting.rootView = content
    }
}

// MARK: - Dumper

struct BoneGlassDumper {
    let only: [GlassInput]?

    private struct Found {
        var layer: String
        var slot: String
        var filterType: String
        var isGlass: Bool
        var inputs: [(key: String, value: Any?)]
    }

    func dump(_ root: UIView) -> String {
        var found: [Found] = []
        collect(root.layer, path: String(describing: type(of: root.layer)), into: &found)

        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var t = "BONE · dumpGlass\n"
        t += "OS: \(UIDevice.current.systemName) \(UIDevice.current.systemVersion) · captured: \(df.string(from: Date()))\n"
        t += "inputs: " + (only.map { $0.map(\.caseName).joined(separator: ", ") } ?? "all") + "\n"
        let glass = found.filter(\.isGlass)
        t += "glass filters: \(glass.count)\n"
        if glass.isEmpty {
            t += "\n(no glass filter found – is .glassEffect() / a glass style applied, and has it rendered?)\n"
        }

        let wanted = only.map { Set($0.map(\.rawValue)) }
        for (i, f) in found.enumerated() where f.isGlass || wanted == nil {
            t += "\n===== [\(i)] \(f.filterType)  (\(f.slot) on \(f.layer)) =====\n"
            let rows = f.inputs.filter { wanted == nil || wanted!.contains($0.key) }
            if rows.isEmpty { t += "   (none of the requested inputs)\n"; continue }
            let width = rows.map { label($0.key).count }.max() ?? 0
            for r in rows {
                let l = label(r.key)
                t += "   " + l + String(repeating: " ", count: width - l.count) + " = " + format(r.value) + "\n"
            }
        }
        return t
    }

    /// "blurRadius (inputBlurRadius)" for known keys, raw key otherwise.
    private func label(_ key: String) -> String {
        if let g = GlassInput(rawValue: key) { return "\(g.caseName)  (\(key))" }
        return key
    }

    private func collect(_ layer: CALayer, path: String, into found: inout [Found]) {
        for slot in ["filters", "backgroundFilters"] {
            guard let filters = layer.value(forKey: slot) as? [NSObject] else { continue }
            for f in filters {
                let type = (f.value(forKey: "type") as? String) ?? String(describing: Swift.type(of: f))
                let keys = BoneFilterInputs.keys(of: f)
                found.append(Found(layer: path, slot: slot, filterType: type,
                                   isGlass: type.lowercased().contains("glass"),
                                   inputs: keys.map { ($0, f.value(forKey: $0)) }))
            }
        }
        for (i, sub) in (layer.sublayers ?? []).enumerated() {
            collect(sub, path: "\(path) ▹ [\(i)]\(type(of: sub))", into: &found)
        }
    }

    private func format(_ v: Any?) -> String {
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
            let s = val.cgSizeValue
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

#endif
