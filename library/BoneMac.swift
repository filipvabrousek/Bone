//
//  BoneMac.swift
//  Bone-27
//
//  .dumpGlass and .tune on macOS. SwiftUI on macOS 26+ draws Liquid Glass
//  exactly as on iOS and watchOS – SDFLayer → CABackdropLayer with a
//  glassBackground filter → CASDFElementLayer – inside AppKit's layer-backed
//  windows, so the shared runtime engine (BoneGlassRuntime.swift) works on it:
//
//      Button("Glass") {}.buttonStyle(.glass).dumpGlass("mac-glass.txt")
//      Text("Panel").padding().glassEffect().tune(.noShadow + [.blurRadius: 0])
//
//  The modified view is marked by an anchor NSView in its background; a glass
//  layer belongs to it when the layer's centre, converted into the anchor's own
//  layer, lies inside the anchor (no flipped-coordinate guesswork). Files go to
//  Documents and <project>/captures/ (App Sandbox off), as BoneCapture does.
//
//  Research use only — private Core Animation keys, never ship it.
//

#if os(macOS)

import SwiftUI
import AppKit

extension View {

    /// Writes the glass filter inputs of the glass in this view (macOS), like .dumpGlass on iOS.
    func dumpGlass(_ fileName: String, only: [GlassInput]? = nil, after delay: Double = 1.5) -> some View {
        background(BoneMacAnchor { anchor in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak anchor] in
                guard let anchor else { return }
                let text = BoneGlassRuntime.dumpGlass(BoneMac.filterLayers(in: anchor), only: only)
                BoneCapture.writeData(Data(text.utf8), fileName: fileName)
            }
        })
    }

    /// Overrides Liquid Glass filter inputs of the glass in this view (macOS), like .tune on iOS.
    func tune(_ tuning: GlassTuning, log: String? = nil) -> some View {
        background(BoneMacAnchor { anchor in
            let tuner = BoneGlassRuntimeTuner(values: tuning.caValues, log: log,
                                              collect: { [weak anchor] in anchor.map(BoneMac.filterLayers(in:)) ?? [] },
                                              write: { BoneCapture.writeData(Data($0.utf8), fileName: $1) })
            anchor.keepAlive = tuner
            tuner.start()
        })
    }
}

/// A transparent, layer-backed view behind the modified content; `onWindow` runs once it is in a window.
struct BoneMacAnchor: NSViewRepresentable {
    let onWindow: (BoneMacAnchorView) -> Void

    func makeNSView(context: Context) -> BoneMacAnchorView {
        let v = BoneMacAnchorView()
        v.onWindow = onWindow
        return v
    }

    func updateNSView(_ v: BoneMacAnchorView, context: Context) {}

    static func dismantleNSView(_ v: BoneMacAnchorView, coordinator: ()) {
        (v.keepAlive as? BoneGlassRuntimeTuner)?.stop()
    }
}

final class BoneMacAnchorView: NSView {
    var onWindow: ((BoneMacAnchorView) -> Void)?
    var keepAlive: AnyObject?
    private var started = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, !started else { return }
        started = true
        onWindow?(self)
    }
}

enum BoneMac {

    /// Layers carrying filters in the anchor's window whose centre lies inside the anchor.
    static func filterLayers(in anchor: BoneMacAnchorView) -> [BoneGlassRuntime.Found] {
        guard let window = anchor.window, let anchorLayer = anchor.layer,
              let root = window.contentView?.superview?.layer ?? window.contentView?.layer else { return [] }
        let area = anchor.bounds.insetBy(dx: -8, dy: -8)
        return BoneGlassRuntime.filterLayers(roots: [root]) { layer, _ in
            let r = BoneGlassRuntime.rect(of: layer, in: anchorLayer)
            return !r.isNull && area.contains(CGPoint(x: r.midX, y: r.midY))
        }
    }
}

#endif
