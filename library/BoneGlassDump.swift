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
//  (e.g. vibrantColorMatrix). `full: true` adds the glass element's layer
//  tree and the glass shaders' own parameters (see BoneShaderDump).
//  Output: Documents and, in the simulator, <project>/captures/.
//
//      Button("Liquid") {}.glassEffect().dumpGlass("glass-full.txt", full: true)
//
//  Research / simulator use only — private Core Animation keys, never ship it.
//

#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import UIKit

extension View {

    /// Writes the Liquid Glass filter inputs of this view to `fileName`.
    /// - Parameters:
    ///   - only: just these inputs; `nil` (default) writes all of them.
    ///   - after: seconds to wait, so the glass has rendered (and `.tune` has applied).
    ///   - full: also the layer tree of the glass and the parameters of the glass shaders themselves.
    func dumpGlass(_ fileName: String, only: [GlassInput]? = nil, after delay: Double = 1.5, full: Bool = false) -> some View {
        BoneGlassDumpHost(fileName: fileName, only: only, delay: delay, full: full) { self }
    }
}

// MARK: - Hosting wrapper

struct BoneGlassDumpHost<Content: View>: UIViewControllerRepresentable {
    let fileName: String
    let only: [GlassInput]?
    let delay: Double
    var full = false
    let content: Content

    init(fileName: String, only: [GlassInput]?, delay: Double, full: Bool = false, @ViewBuilder content: () -> Content) {
        self.fileName = fileName
        self.only = only
        self.delay = delay
        self.full = full
        self.content = content()
    }

    func makeUIViewController(context: Context) -> UIHostingController<Content> {
        let hosting = UIHostingController(rootView: content)
        hosting.view.backgroundColor = .clear
        hosting.sizingOptions = [.intrinsicContentSize]
        let full = full
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak view = hosting.view] in
            guard let view else { return }
            var text = BoneGlassDumper(only: only).dump(view)
            guard full else { BoneCapture.writeData(Data(text.utf8), fileName: fileName); return }
            text += "\n\n" + BoneLayerDump.text(for: view.layer, in: view.window)
            BoneShaderDump.text(matching: "glass") { shaders in
                BoneCapture.writeData(Data((text + "\n\n" + shaders).utf8), fileName: fileName)
            }
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

    private func format(_ v: Any?) -> String { BoneGlassFormat.value(v) }
}

#endif
