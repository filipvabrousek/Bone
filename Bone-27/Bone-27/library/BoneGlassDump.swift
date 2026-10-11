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
//  Output: Documents and, in the simulator and on the Mac, <project>/captures/.
//  iOS and macOS; the engine is BoneGlassEngine.swift (watchOS: BoneWatch.swift).
//
//      Button("Liquid") {}.glassEffect().dumpGlass("glass-full.txt", full: true)
//
//  Research / simulator use only — private Core Animation keys, never ship it.
//

#if DEBUG   // Bone is private API: it compiles to nothing outside Debug builds

#if (canImport(UIKit) && !os(watchOS)) || os(macOS)

import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

extension View {

    /// Writes the Liquid Glass filter inputs of this view to `fileName`.
    /// - Parameters:
    ///   - only: just these inputs; `nil` (default) writes all of them.
    ///   - after: seconds to wait, so the glass has rendered (and `.tune` has applied).
    ///   - full: also the layer tree of the glass and the parameters of the glass shaders themselves.
    public func dumpGlass(_ fileName: String, only: [GlassInput]? = nil, after delay: Double = 1.5, full: Bool = false) -> some View {
        BoneGlassDumpHost(fileName: fileName, only: only, delay: delay, full: full) { self }
    }
}

enum BoneGlassDumpWriter {
    /// The report, plus (`full`) the layer tree and the glass shaders' parameters.
    static func write(_ found: [BoneGlassFound], only: [GlassInput]?, full: Bool, layerTree: () -> String, to fileName: String) {
        let text = BoneGlassEngine.dump(found, only: only)
        guard full else { BoneCapture.writeData(Data(text.utf8), fileName: fileName); return }
        let withTree = text + "\n\n" + layerTree()
        BoneShaderDump.text(matching: "glass") { shaders in
            BoneCapture.writeData(Data((withTree + "\n\n" + shaders).utf8), fileName: fileName)
        }
    }
}

#if canImport(UIKit)

// MARK: - Hosting wrapper (iOS)

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
        let (full, only, fileName) = (full, only, fileName)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak view = hosting.view] in
            guard let view else { return }
            BoneGlassDumpWriter.write(BoneGlassEngine.found(under: view.layer), only: only, full: full,
                                      layerTree: { BoneLayerDump.text(for: view.layer, in: view.window) }, to: fileName)
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

#else

// MARK: - Host (macOS): the glass whose centre lies inside the modified view

struct BoneGlassDumpHost<Content: View>: View {
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

    var body: some View {
        let (full, only, fileName, delay) = (full, only, fileName, delay)
        return content.background(BoneMacAnchor { anchor in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak anchor] in
                guard let anchor else { return }
                BoneGlassDumpWriter.write(BoneMac.glassLayers(in: anchor), only: only, full: full,
                                          layerTree: { BoneMac.layerTree(in: anchor) }, to: fileName)
            }
        })
    }
}

#endif

#endif

#endif   // DEBUG
