//
//  BoneTune.swift
//  Bone-27
//
//  Manual tuning of Liquid Glass internals (iOS and macOS; watchOS: BoneWatch.swift).
//
//      Button("Liquid") {}
//          .glassEffect()
//          .tune(excludeShadow: true, contentLensing: false)
//
//      Button("Liquid") {}
//          .glassEffect()
//          .tune(overrides: ["inputBlurRadius": 0, "inputFaceOpacity": 0.2])
//
//      Button("Liquid") {}
//          .glassEffect()
//          .tune(file: "glass-panel.json")   // saved by .glassPanel; re-read when it changes
//
//  Raw keys reach other filters of the glass with a prefix:
//  .tune(.raw(["vibrantColorMatrix.inputColorMatrix": BoneColorMatrix.value(BoneColorMatrix.invert)]))
//
//  How it works: Liquid Glass is drawn by a Core Animation filter of type
//  "glassBackground" (DesignLibrary's DLCAFilter) on SwiftUI's SDFLayer.
//  Its ~70 inputs (shadow, refraction, blur, highlight, ...) are the real
//  parameters — `.dumpGlass("glass.txt")` writes the full list with values.
//  `.tune` finds every layer carrying that filter and overwrites the chosen
//  inputs through the layer's key path "filters.<name>.<input>".
//  SwiftUI rebuilds the filter on updates (hover, press, state changes), so
//  the values are re-applied a few times per second while the view is alive.
//  The engine is BoneGlassEngine.swift.
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

    /// Overrides Liquid Glass filter inputs of this view.
    ///
    ///     Button("Liquid") {}.glassEffect().tune([.blurRadius: 0, .faceOpacity: 0.3])
    ///     Button("Liquid") {}.glassEffect().tune(.noShadow + .noLensing)
    ///
    /// - Parameter log: optional file name; writes what changed (before → after) once.
    public func tune(_ tuning: GlassTuning, log: String? = nil) -> some View {
        BoneTuneHost(values: tuning.caValues, log: log, file: nil) { self }
    }

    /// Overrides from a JSON file – the format `.glassPanel()` saves:
    /// `{"glassBackground": {"blurRadius": 0}, "vibrantColorMatrix": {"inputColorMatrix": {"matrix": [...]}}}`.
    /// In the simulator and on the Mac the file is `<project>/captures/<fileName>` and is re-read
    /// whenever it changes, so you can edit it and watch the glass.
    /// (A key you delete keeps its last value until SwiftUI rebuilds the glass.)
    public func tune(file fileName: String, log: String? = nil) -> some View {
        BoneTuneHost(values: [:], log: log, file: fileName) { self }
    }

    /// Shortcut kept for the first version of the API:
    /// `.tune(excludeShadow: true, contentLensing: false)` == `.tune(.noShadow + .noLensing)`.
    public func tune(excludeShadow: Bool = false,
              contentLensing: Bool = true,
              overrides: [String: Any] = [:],
              log: String? = nil) -> some View {
        var t: GlassTuning = [:]
        if excludeShadow { t = t + .noShadow }
        if !contentLensing { t = t + .noLensing }
        return tune(t + .raw(overrides), log: log)
    }
}

#if canImport(UIKit)

// MARK: - Hosting wrapper (iOS): the glass is everything under the hosting view

struct BoneTuneHost<Content: View>: UIViewControllerRepresentable {
    let values: [String: Any]
    let log: String?
    let file: String?
    let content: Content

    init(values: [String: Any], log: String?, file: String?, @ViewBuilder content: () -> Content) {
        self.values = values
        self.log = log
        self.file = file
        self.content = content()
    }

    final class Coordinator {
        var tuner: BoneGlassTuner?
    }

    func makeUIViewController(context: Context) -> UIHostingController<Content> {
        let hosting = UIHostingController(rootView: content)
        hosting.view.backgroundColor = .clear
        hosting.sizingOptions = [.intrinsicContentSize]
        let tuner = BoneGlassTuner(values: values, log: log, file: file) { [weak view = hosting.view] in
            view.map { BoneGlassEngine.found(under: $0.layer) }
        }
        context.coordinator.tuner = tuner
        tuner.start()
        return hosting
    }

    func updateUIViewController(_ hosting: UIHostingController<Content>, context: Context) {
        hosting.rootView = content
        if file == nil { context.coordinator.tuner?.values = values }
    }

    /// Size of the content, not of the space offered (keeps stacks tight).
    func sizeThatFits(_ proposal: ProposedViewSize, uiViewController: UIHostingController<Content>, context: Context) -> CGSize? {
        uiViewController.sizeThatFits(in: CGSize(width: proposal.width ?? .infinity, height: proposal.height ?? .infinity))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    static func dismantleUIViewController(_ vc: UIHostingController<Content>, coordinator: Coordinator) {
        coordinator.tuner?.stop()
    }
}

#else

// MARK: - Host (macOS): the glass whose centre lies inside the modified view

struct BoneTuneHost<Content: View>: View {
    let values: [String: Any]
    let log: String?
    let file: String?
    let content: Content

    init(values: [String: Any], log: String?, file: String?, @ViewBuilder content: () -> Content) {
        self.values = values
        self.log = log
        self.file = file
        self.content = content()
    }

    var body: some View {
        content.background(BoneMacAnchor { anchor in
            let tuner = BoneGlassTuner(values: values, log: log, file: file) { [weak anchor] in
                anchor.map(BoneMac.glassLayers(in:))
            }
            anchor.keepAlive = tuner
            tuner.start()
        })
    }
}

#endif

#endif

#endif   // DEBUG
