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
//  .tuneLayers and .dumpLayers work too (the layer types are shared with iOS,
//  BoneLayerTune.swift); here they act on the layers lying inside the modified
//  view's frame:
//
//      Text("Hello").tuneLayers([.rotation: -8, .shadowOpacity: 1], where: .text)
//      VStack { … }.dumpLayers("mac-layers.txt")
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
        (v.keepAlive as? BoneStoppable)?.stop()
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

/// Something an anchor keeps alive and stops when its view goes away.
protocol BoneStoppable: AnyObject { func stop() }
extension BoneGlassRuntimeTuner: BoneStoppable {}

// MARK: - Layers: .tuneLayers and .dumpLayers

extension View {

    /// Changes the layers SwiftUI draws this view into (macOS), like .tuneLayers on iOS.
    func tuneLayers(_ tuning: LayerTuning, where target: LayerTarget = .leaves, log: String? = nil) -> some View {
        background(BoneMacAnchor { anchor in
            let tuner = BoneMacLayerTuner(anchor: anchor, tuning: tuning, target: target, log: log)
            anchor.keepAlive = tuner
            tuner.start()
        })
    }

    /// Writes the layers SwiftUI draws this view into (macOS), like .dumpLayers on iOS.
    func dumpLayers(_ fileName: String, after delay: Double = 1.5) -> some View {
        background(BoneMacAnchor { anchor in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak anchor] in
                guard let anchor, let anchorLayer = anchor.layer else { return }
                // every top-level layer inside the view, each with its subtree; frames in the view's space
                var text = ""
                for (i, top) in BoneMac.topLayers(in: anchor).enumerated() {
                    let part = BoneLayerDump.text(for: top, os: BoneGlassRuntime.osLine) { l in
                        l.convert(l.bounds, to: anchorLayer)
                    }
                    text += i == 0 ? part : part.components(separatedBy: "\n").dropFirst(4).joined(separator: "\n")
                }
                BoneCapture.writeData(Data(text.utf8), fileName: fileName)
            }
        })
    }
}

final class BoneMacLayerTuner: BoneStoppable {
    private weak var anchor: BoneMacAnchorView?
    private let tuning: LayerTuning
    private let target: LayerTarget
    private let log: String?
    private var timer: Timer?
    private var logged = false

    init(anchor: BoneMacAnchorView, tuning: LayerTuning, target: LayerTarget, log: String?) {
        self.anchor = anchor
        self.tuning = tuning
        self.target = target
        self.log = log
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.125, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func tick() {
        guard let anchor else { stop(); return }
        var changes: [String] = []
        for l in BoneMac.layers(in: anchor) where target.matches(l) {
            changes += BoneLayerApplier.apply(tuning, to: l, generation: 0).map { "\(type(of: l)) \($0)" }
        }
        if let log, !logged, !changes.isEmpty {
            logged = true
            let text = "BONE · tuneLayers \(target.name)\nOS: \(BoneGlassRuntime.osLine)\n\n" + changes.joined(separator: "\n") + "\n"
            BoneCapture.writeData(Data(text.utf8), fileName: log)
        }
    }
}

enum BoneMac {

    static func rootLayer(of anchor: NSView) -> CALayer? {
        anchor.window?.contentView?.superview?.layer ?? anchor.window?.contentView?.layer
    }

    /// Every layer of the anchor's window lying inside the anchor (not the anchor's own layers).
    static func layers(in anchor: BoneMacAnchorView) -> [CALayer] {
        guard let root = rootLayer(of: anchor), let anchorLayer = anchor.layer else { return [] }
        let area = anchor.bounds
        var out: [CALayer] = []
        func walk(_ l: CALayer) {
            // Bone's own anchor views (and AppKit's hosts around them) are not the app's layers
            if let v = l.delegate as? NSView,
               v is BoneMacAnchorView || (v.subviews.count == 1 && v.subviews[0] is BoneMacAnchorView) { return }
            let r = l.convert(l.bounds, to: anchorLayer)
            // centre inside, and not much larger (a rotated label's bounding box grows a little)
            if r.width > 0, r.height > 0, area.insetBy(dx: -2, dy: -2).contains(CGPoint(x: r.midX, y: r.midY)),
               r.width <= area.width * 1.25 + 4, r.height <= area.height * 1.25 + 4 { out.append(l) }
            l.sublayers?.forEach(walk)
        }
        walk(root)
        return out
    }

    /// The layers inside the anchor whose superlayer is not – the roots of the view's own subtrees.
    static func topLayers(in anchor: BoneMacAnchorView) -> [CALayer] {
        let inside = layers(in: anchor)
        let set = Set(inside.map(ObjectIdentifier.init))
        return inside.filter { l in l.superlayer.map { !set.contains(ObjectIdentifier($0)) } ?? true }
    }

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
