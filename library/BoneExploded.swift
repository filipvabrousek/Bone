//
//  BoneExploded.swift
//  Bone-27
//
//  3D exploded view of what SwiftUI drew, inside the inspector (.boneInspector):
//  tap the pink drop → 3D. Every drawn layer – text, shapes, gradients, glass –
//  becomes a plane at its screen position, pushed back by its depth in the
//  layer tree. Drag to orbit, two fingers to move, pinch to zoom, double-tap
//  to reset. Tap a plane to tune that layer with sliders (the glass inputs for
//  glass); the edit goes to the real layer and is previewed on the plane.
//  Hold the eye to peek at the real app underneath.
//
//  Planes are Core Animation layers in a CATransformLayer (real perspective,
//  GPU-composited); taps are picked by projecting each plane's corners with
//  the same matrix. Text, shapes and gradients are rendered on their own
//  (sublayers hidden for the render, nothing on screen changes); glass and
//  anything only the render server draws is cut from a screenshot taken
//  just before the view opens.
//
//  Research / simulator use only — private API, never ship it.
//

#if canImport(UIKit)

import SwiftUI
import UIKit

/// One plane: a layer of the app, frozen as an image.
final class BoneExplodedNode {
    weak var source: CALayer?
    weak var window: UIWindow?
    let frame: CGRect          // screen points
    let depth: Int             // depth in the layer tree
    let order: Int             // drawing order
    let isGlass: Bool
    let container = CALayer()  // placed in 3D
    let content = CALayer()    // the image; tuning previews go here

    init(source: CALayer, window: UIWindow, frame: CGRect, depth: Int, order: Int, isGlass: Bool) {
        self.source = source
        self.window = window
        self.frame = frame
        self.depth = depth
        self.order = order
        self.isGlass = isGlass
    }
}

final class BoneExplodedView: UIView {

    var onPick: ((BoneExplodedNode) -> Void)?
    /// The tuning to preview on the selected plane (nil = none).
    var tuningSource: (() -> (LayerTuning, Int)?)?
    private(set) var nodes: [BoneExplodedNode] = []
    weak var selected: BoneExplodedNode? {
        didSet {
            oldValue?.container.borderColor = Self.edge
            oldValue?.container.borderWidth = 0.5
            selected?.container.borderColor = UIColor.systemPink.cgColor
            selected?.container.borderWidth = 2
        }
    }
    var spacing: CGFloat = 30 {
        didSet { if spacing != oldValue { placeDepths(animated: false) } }
    }

    private let world = CATransformLayer()
    private var yaw: CGFloat = 0, pitch: CGFloat = 0, zoom: CGFloat = 1
    private var offset = CGPoint.zero
    private var link: CADisplayLink?
    private static let edge = UIColor(white: 1, alpha: 0.35).cgColor
    private static let home = (yaw: CGFloat(-0.55), pitch: CGFloat(0.35), zoom: CGFloat(0.7))

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(white: 0.07, alpha: 0.97)
        layer.addSublayer(world)

        let orbit = UIPanGestureRecognizer(target: self, action: #selector(orbit(_:)))
        orbit.maximumNumberOfTouches = 2
        addGestureRecognizer(orbit)
        addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:))))
        let reset = UITapGestureRecognizer(target: self, action: #selector(resetCamera))
        reset.numberOfTapsRequired = 2
        addGestureRecognizer(reset)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tap(_:)))
        tap.require(toFail: reset)
        addGestureRecognizer(tap)

        let l = CADisplayLink(target: BoneLinkTarget { [weak self] in self?.tick() }, selector: #selector(BoneLinkTarget.step))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 4, maximum: 10, preferred: 8)
        l.add(to: .main, forMode: .common)
        link = l
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func removeFromSuperview() {
        link?.invalidate()
        link = nil
        super.removeFromSuperview()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        world.bounds = bounds
        CATransaction.commit()
        applyCamera(animated: false)
    }

    // MARK: Building

    /// Freezes the scene's windows (except `panel`) into planes.
    func build(scene: UIWindowScene?, excluding panel: UIWindow?, screenshot: CGImage?) {
        nodes.forEach { $0.container.removeFromSuperlayer() }
        nodes = []
        guard let scene else { return }
        var order = 0
        let windows = scene.windows.filter { $0 !== panel && !$0.isHidden }
            .sorted { $0.windowLevel.rawValue < $1.windowLevel.rawValue }
        for w in windows {
            func walk(_ l: CALayer, _ depth: Int) {
                guard !l.isHidden, l.opacity > 0.01, nodes.count < 600 else { return }
                if l !== w.layer, Self.draws(l) {
                    let f = BoneGlassLayers.screenFrame(of: l, in: w)
                    if f.width >= 1, f.height >= 1, f.intersects(w.frame) {
                        nodes.append(BoneExplodedNode(source: l, window: w, frame: f, depth: depth, order: order,
                                                      isGlass: Self.isGlass(l)))
                        order += 1
                    }
                }
                if Self.isGlass(l) { return }     // the glass plane already shows its insides
                l.sublayers?.forEach { walk($0, depth + 1) }
            }
            walk(w.layer, 0)
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for n in nodes {
            n.container.bounds = CGRect(origin: .zero, size: n.frame.size)
            n.container.position = CGPoint(x: n.frame.midX, y: n.frame.midY)
            n.container.borderWidth = 0.5
            n.container.borderColor = Self.edge
            n.content.frame = n.container.bounds
            n.content.contentsGravity = .resize
            n.content.contents = snapshot(n, screenshot: screenshot)
            n.container.addSublayer(n.content)
            world.addSublayer(n.container)
        }
        CATransaction.commit()
        explodeIn()
    }

    /// Starts flat (looks like the app), then opens up.
    private func explodeIn() {
        let target = spacing
        yaw = 0; pitch = 0; zoom = 1; offset = .zero
        spacing = 0
        applyCamera(animated: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.yaw = Self.home.yaw
            self.pitch = Self.home.pitch
            self.zoom = Self.home.zoom
            self.spacing = target
            self.placeDepths(animated: true)
            self.applyCamera(animated: true)
        }
    }

    static func isGlass(_ l: CALayer) -> Bool { BoneGlassLayers.filters(on: l).contains(where: \.isGlass) }

    /// Layers that draw something of their own (containers and glass internals are skipped).
    static func draws(_ l: CALayer) -> Bool {
        let name = String(describing: type(of: l))
        if name.contains("SDF") || name.contains("Portal") || l is CATransformLayer { return false }
        if isGlass(l) || l.contents != nil || l.borderWidth > 0 { return true }
        if let bg = l.backgroundColor, bg.alpha > 0.01 { return true }
        return name.contains("Shape") || name.contains("Gradient")
    }

    private func snapshot(_ n: BoneExplodedNode, screenshot: CGImage?) -> CGImage? {
        guard let l = n.source else { return nil }
        if n.isGlass { return crop(screenshot, n.frame, n.window) }
        let size = l.bounds.size
        guard size.width * size.height < 6_000_000 else { return crop(screenshot, n.frame, n.window) }
        // render just this layer: hide its sublayers for the render (same transaction, nothing hits the screen)
        let subs = l.sublayers ?? []
        let wasHidden = subs.map(\.isHidden)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        subs.forEach { $0.isHidden = true }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            ctx.cgContext.translateBy(x: -l.bounds.minX, y: -l.bounds.minY)
            l.render(in: ctx.cgContext)
        }
        for (s, h) in zip(subs, wasHidden) { s.isHidden = h }
        CATransaction.commit()
        // only the render server draws some layers – take them from the screenshot
        return Self.isBlank(image) ? crop(screenshot, n.frame, n.window) : image.cgImage
    }

    private func crop(_ shot: CGImage?, _ frame: CGRect, _ window: UIWindow?) -> CGImage? {
        guard let shot, let window else { return nil }
        let s = CGFloat(shot.width) / BoneScreen.width(of: window)
        return shot.cropping(to: CGRect(x: frame.minX * s, y: frame.minY * s, width: frame.width * s, height: frame.height * s).integral)
    }

    private static func isBlank(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage else { return true }
        var px = [UInt8](repeating: 0, count: 16 * 16 * 4)
        let drawn: Bool = px.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 64,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 16, height: 16))
            return true
        }
        guard drawn else { return true }
        return !stride(from: 3, to: px.count, by: 4).contains { px[$0] > 4 }
    }

    // MARK: Camera

    private var cameraTransform: CATransform3D {
        var perspective = CATransform3DIdentity
        perspective.m34 = -1 / 1200
        let rotation = CATransform3DConcat(CATransform3DMakeRotation(yaw, 0, 1, 0), CATransform3DMakeRotation(pitch, 1, 0, 0))
        return CATransform3DConcat(CATransform3DConcat(CATransform3DMakeScale(zoom, zoom, zoom), rotation), perspective)
    }

    private func applyCamera(animated: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        if animated { CATransaction.setAnimationDuration(0.7) }
        world.transform = cameraTransform
        world.position = CGPoint(x: bounds.midX + offset.x, y: bounds.midY + offset.y)
        CATransaction.commit()
    }

    private func placeDepths(animated: Bool) {
        let ranks = Dictionary(uniqueKeysWithValues: Set(nodes.map(\.depth)).sorted().enumerated().map { ($1, $0) })
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        if animated { CATransaction.setAnimationDuration(0.7) }
        for n in nodes {
            n.container.zPosition = CGFloat(ranks[n.depth] ?? 0) * spacing + CGFloat(n.order) * 0.02
        }
        CATransaction.commit()
    }

    @objc private func orbit(_ g: UIPanGestureRecognizer) {
        let t = g.translation(in: self)
        g.setTranslation(.zero, in: self)
        if g.numberOfTouches >= 2 {
            offset.x += t.x
            offset.y += t.y
        } else {
            yaw += t.x * 0.004
            pitch = max(-1.4, min(1.4, pitch - t.y * 0.004))
        }
        applyCamera(animated: false)
    }

    @objc private func pinch(_ g: UIPinchGestureRecognizer) {
        zoom = max(0.15, min(4, zoom * g.scale))
        g.scale = 1
        applyCamera(animated: false)
    }

    @objc func resetCamera() {
        yaw = Self.home.yaw
        pitch = Self.home.pitch
        zoom = Self.home.zoom
        offset = .zero
        applyCamera(animated: true)
    }

    // MARK: Picking

    @objc private func tap(_ g: UITapGestureRecognizer) {
        guard let n = node(at: g.location(in: self)) else { return }
        selected = n
        onPick?(n)
    }

    /// The frontmost plane under a point – each plane's corners projected with the world matrix.
    func node(at p: CGPoint) -> BoneExplodedNode? {
        let m = world.transform
        let anchor = CGPoint(x: world.bounds.midX, y: world.bounds.midY)
        let origin = world.position
        var best: (node: BoneExplodedNode, w: CGFloat)?
        for n in nodes {
            let f = n.frame, z = n.container.zPosition
            var corners: [CGPoint] = []
            var wSum: CGFloat = 0
            for c in [CGPoint(x: f.minX, y: f.minY), CGPoint(x: f.maxX, y: f.minY),
                      CGPoint(x: f.maxX, y: f.maxY), CGPoint(x: f.minX, y: f.maxY)] {
                let x = c.x - anchor.x, y = c.y - anchor.y
                let X = x * m.m11 + y * m.m21 + z * m.m31 + m.m41
                let Y = x * m.m12 + y * m.m22 + z * m.m32 + m.m42
                let W = x * m.m14 + y * m.m24 + z * m.m34 + m.m44
                guard W > 0.01 else { corners = []; break }
                corners.append(CGPoint(x: X / W + origin.x, y: Y / W + origin.y))
                wSum += W
            }
            guard corners.count == 4, Self.inside(p, corners) else { continue }
            if best == nil || wSum < best!.w { best = (n, wSum) }     // smaller w = closer to the eye
        }
        return best?.node
    }

    private static func inside(_ p: CGPoint, _ quad: [CGPoint]) -> Bool {
        var sign: CGFloat = 0
        for i in 0..<quad.count {
            let a = quad[i], b = quad[(i + 1) % quad.count]
            let cross = (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
            if cross == 0 { continue }
            if sign == 0 { sign = cross } else if (sign > 0) != (cross > 0) { return false }
        }
        return true
    }

    // MARK: Preview

    private func tick() {
        guard let sel = selected, !sel.isGlass, let (tuning, generation) = tuningSource?() else { return }
        BoneLayerApplier.apply(tuning, to: sel.content, generation: generation)
    }
}

// MARK: - SwiftUI

struct BoneExplodedRepresentable: UIViewRepresentable {
    @ObservedObject var model: BoneGlassPanelModel

    func makeUIView(context: Context) -> BoneExplodedView {
        let v = BoneExplodedView(frame: .zero)
        let model = model
        v.onPick = { [weak model] node in model?.pickExploded(node) }
        v.tuningSource = { [weak model] in model?.explodedTuning() }
        v.spacing = CGFloat(model.explodeSpacing)
        model.explodedView = v
        DispatchQueue.main.async { model.buildExploded() }
        return v
    }

    func updateUIView(_ v: BoneExplodedView, context: Context) {
        v.spacing = CGFloat(model.explodeSpacing)
    }
}

struct BoneExplodedScreen: View {
    @ObservedObject var model: BoneGlassPanelModel

    var body: some View {
        ZStack {
            BoneExplodedRepresentable(model: model)
                .ignoresSafeArea()
                .opacity(model.peeking ? 0 : 1)
            VStack(spacing: 6) {
                HStack(spacing: 12) {
                    Text("3D · \(model.explodeInfo)").font(.caption.bold())
                    Image(systemName: "square.3.layers.3d.down.right").font(.caption)
                    Slider(value: $model.explodeSpacing, in: 0...120).frame(width: 100)
                    Image(systemName: model.peeking ? "eye.fill" : "eye")
                        .onLongPressGesture(minimumDuration: 30, pressing: { model.peeking = $0 }, perform: {})
                    Button { model.refreshExploded() } label: { Image(systemName: "arrow.clockwise") }
                    Button { model.closeExploded() } label: { Image(systemName: "xmark.circle.fill") }
                }
                .font(.title3)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                Text("drag orbit · 2 fingers move · pinch zoom · double-tap reset · tap a plane to tune · hold 👁 to peek")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.75))
                    .opacity(model.peeking ? 0 : 1)
                Spacer(minLength: 0)
                if model.isOpen {
                    Group {
                        if model.showing == .layer {
                            BoneLayerCard(model: model, editor: model.layerEditor)
                        } else {
                            BoneGlassCard(model: model)
                        }
                    }
                    .containerRelativeFrame(.vertical) { h, _ in h * 0.42 }
                }
            }
            .padding(.horizontal, 8)
        }
    }
}

#endif
