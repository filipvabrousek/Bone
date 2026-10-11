//
//  BoneGlassFlex.swift
//  Bone-27
//
//  Exaggerates the Liquid Glass button's flex – the swell when pressed and
//  the stretch toward the finger while held and dragged:
//
//      Button("Glass") {}
//          .buttonStyle(.glass)
//          .glassFlex(stretch: 6, follow: 12)
//
//  SwiftUI's flex interaction (UIPlatformGlassFlexInteraction) drives two
//  layer branches every frame, measured on an iPhone 14 Pro:
//
//  • the content – the layer of UIPlatformGlassInteractionView (label, glow):
//    setTransform:/setAffineTransform: (the scale, from the top-left corner,
//    anchor point 0,0) and setPosition: (−(s − 1)·size/2 + finger shift);
//  • the glass outline – every layer under SwiftUI's SDFLayer host outside the
//    content (container, CABackdropLayer, CASDFLayer, SDFPortalLayer …): each
//    gets the shape's setBounds: (61×39 → 78×50 when pressed) and setPosition:
//    (the same recentring) every frame;
//  • the shape element (CASDFElementLayer) – a rounded rectangle with its own
//    setCornerRadius: (19.7 → 25.2) while pressed; while dragged it switches to
//    a distance-field bitmap of the stretched blob in a frame ~9.5 pt larger than
//    the shape. It is scaled about the shape, so the blob lands on the amplified
//    shape and a capsule stays one.
//
//  Stock: press 1.19×, drag 1.23 × 1.13, shift +4 pt for a 170 pt drag.
//  Both branches get the same mapping, so outline and content stay together:
//  the scale (or the growth of the size) × stretch, recentred, and the finger
//  shift × follow. On release UIKit stops setting the content for ~1 s while the
//  outline still springs back frame by frame: the content then follows the
//  outline. CALayer's setters are swapped once; only layers of a glass
//  button inside a .glassFlex view are changed, each value mapped exactly once
//  (nested setter calls pass through).
//
//  Research / simulator use only — private API, never ship it.
//

#if canImport(UIKit) && !os(visionOS) && !os(watchOS)

import SwiftUI
import UIKit

extension View {

    /// Exaggerates the glass flex of the glass controls in this view: `stretch` multiplies
    /// the swell and the drag stretch (1 = stock), `follow` the shift toward the finger.
    func glassFlex(stretch: CGFloat = 6, follow: CGFloat = 12) -> some View {
        background(BoneGlassFlexAnchor(stretch: stretch, follow: follow))
    }
}

struct BoneGlassFlexAnchor: UIViewRepresentable {
    let stretch: CGFloat
    let follow: CGFloat

    func makeUIView(context: Context) -> BoneGlassFlexAnchorView {
        BoneGlassFlex.install()
        let v = BoneGlassFlexAnchorView()
        v.stretch = stretch
        v.follow = follow
        BoneGlassFlex.anchors.add(v)
        return v
    }

    func updateUIView(_ v: BoneGlassFlexAnchorView, context: Context) {
        v.stretch = stretch
        v.follow = follow
    }
}

/// Marks the area of a .glassFlex view; glass views centred inside it are amplified.
final class BoneGlassFlexAnchorView: UIView {
    var stretch: CGFloat = 1
    var follow: CGFloat = 1

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

enum BoneGlassFlex {

    static let anchors = NSHashTable<BoneGlassFlexAnchorView>.weakObjects()
    private static var installed = false
    private static let glassViewClass: AnyClass? = NSClassFromString("_TtC5UIKitP33_F83AB3ECBB2C378B4FCEB681A4D7DB7430UIPlatformGlassInteractionView")
    private static let elementClass: AnyClass? = NSClassFromString("CASDFElementLayer")
    /// > 0 while one of the swapped setters runs: nested calls pass through unchanged.
    private static var depth = 0
    /// The stock scale last set, per content layer.
    private static var rawScale: [ObjectIdentifier: CGSize] = [:]
    /// The stock frame of the glass shape last set (position + size of the outline layers), per host.
    private static var shape: [ObjectIdentifier: CGRect] = [:]
    /// The stock frame and corner radius last set, per shape element.
    private static var element: [ObjectIdentifier: CGRect] = [:]
    private static var elementRadius: [ObjectIdentifier: CGFloat] = [:]
    /// When a content layer last got its own setter: on release UIKit goes quiet for ~1 s.
    private static var contentSetAt: [ObjectIdentifier: CFTimeInterval] = [:]

    private enum Role { case content, outline(host: CALayer), element(host: CALayer) }

    /// Content: the glass view's own layer. Outline: a layer under an SDFLayer, outside the content
    /// (container, backdrop, SDF, portal – all get the shape's bounds and position every frame);
    /// the shape element (CASDFElementLayer) among them is mapped on its own.
    private static func role(of layer: CALayer) -> Role? {
        guard anchors.count > 0, depth == 0 else { return nil }
        if let d = layer.delegate, let cls = glassViewClass, object_getClass(d) == cls { return .content }
        var c = layer.superlayer, n = 1
        while let x = c, n <= 6 {
            if isSDFLayer(x) {
                if let e = elementClass, layer.isKind(of: e) { return .element(host: x) }
                return .outline(host: x)
            }
            if let d = x.delegate, let cls = glassViewClass, object_getClass(d) == cls { return nil }
            c = x.superlayer; n += 1
        }
        return nil
    }

    /// SwiftUI's SDFLayer is a Swift class: NSClassFromString("SDFLayer") does not find it, its name does.
    private static var sdfClasses: [ObjectIdentifier: Bool] = [:]
    private static func isSDFLayer(_ layer: CALayer) -> Bool {
        let cls: AnyClass = object_getClass(layer) ?? CALayer.self
        if let known = sdfClasses[ObjectIdentifier(cls)] { return known }
        let yes = String(describing: cls) == "SDFLayer"
        sdfClasses[ObjectIdentifier(cls)] = yes
        return yes
    }

    /// The .glassFlex area a layer's resting rectangle sits in.
    private static func anchor(around layer: CALayer, restSize: CGSize) -> BoneGlassFlexAnchorView? {
        guard let parent = layer.superlayer else { return nil }
        let center = parent.convert(CGPoint(x: restSize.width / 2, y: restSize.height / 2), to: nil)
        return anchors.allObjects.first { a in
            guard let w = a.window, a.stretch != 1 || a.follow != 1 else { return false }
            return a.convert(a.bounds, to: w).insetBy(dx: -8, dy: -8).contains(center)
        }
    }

    /// The content layer of the glass button an outline host belongs to (a sibling subtree).
    private static func content(in host: CALayer) -> CALayer? {
        guard let cls = glassViewClass else { return nil }
        for l in host.sublayers ?? [] {
            for x in [l] + (l.sublayers ?? []) {
                if let d = x.delegate, object_getClass(d) == cls { return x }
            }
        }
        return nil
    }

    /// The shape elements under a host.
    private static func elements(in host: CALayer) -> [CALayer] {
        guard let cls = elementClass else { return [] }
        var out: [CALayer] = []
        func walk(_ l: CALayer, _ n: Int) {
            if l.isKind(of: cls) { out.append(l) }
            if n < 6 { l.sublayers?.forEach { walk($0, n + 1) } }
        }
        walk(host, 0)
        return out
    }

    private static func scaled(_ s: CGFloat, _ k: CGFloat) -> CGFloat { 1 + k * (s - 1) }

    /// The stock scale of a shape: its size over the resting size.
    private static func raw(_ size: CGSize, rest: CGSize) -> CGSize {
        CGSize(width: size.width / max(rest.width, 1), height: size.height / max(rest.height, 1))
    }

    /// origin = −(s − 1)·rest/2 + shift  →  recentred for the amplified scale, shift × follow.
    private static func origin(_ p: CGPoint, raw: CGSize, rest: CGSize, _ a: BoneGlassFlexAnchorView) -> CGPoint {
        let shift = CGPoint(x: p.x + (raw.width - 1) * rest.width / 2, y: p.y + (raw.height - 1) * rest.height / 2)
        return CGPoint(x: -(scaled(raw.width, a.stretch) - 1) * rest.width / 2 + a.follow * shift.x,
                       y: -(scaled(raw.height, a.stretch) - 1) * rest.height / 2 + a.follow * shift.y)
    }

    /// The amplified shape frame for a stock one.
    private static func mapped(_ shape: CGRect, rest: CGSize, _ a: BoneGlassFlexAnchorView) -> CGRect {
        let r = raw(shape.size, rest: rest)
        return CGRect(origin: origin(shape.origin, raw: r, rest: rest, a),
                      size: CGSize(width: rest.width * scaled(r.width, a.stretch), height: rest.height * scaled(r.height, a.stretch)))
    }

    /// Runs a setter with nested setter calls passing through.
    private static func guarded(_ body: () -> Void) { depth += 1; body(); depth -= 1 }

    typealias SetTransform = @convention(c) (CALayer, Selector, CATransform3D) -> Void
    typealias SetAffine = @convention(c) (CALayer, Selector, CGAffineTransform) -> Void
    typealias SetPoint = @convention(c) (CALayer, Selector, CGPoint) -> Void
    typealias SetRect = @convention(c) (CALayer, Selector, CGRect) -> Void
    typealias SetFloat = @convention(c) (CALayer, Selector, CGFloat) -> Void
    private static let transformSel = #selector(setter: CALayer.transform), affineSel = #selector(CALayer.setAffineTransform(_:))
    private static let positionSel = #selector(setter: CALayer.position), boundsSel = #selector(setter: CALayer.bounds)
    private static let radiusSel = #selector(setter: CALayer.cornerRadius)
    private static var setTransform: SetTransform!
    private static var setAffine: SetAffine!
    private static var setPosition: SetPoint!
    private static var setBounds: SetRect!
    private static var setRadius: SetFloat!

    /// The shape element: in bounds mode it is the shape (rounded rectangle, corner radius); while
    /// dragged it switches to contents mode – a 3× distance-field bitmap of the stretched blob in a
    /// frame ~9.5 pt larger than the shape (94×70 at −16,−14 around 74.8×51.1 at −6.7,−4.6). Both are
    /// scaled about the shape: element′ = shape′.origin + (element − shape.origin)·k, size·k, with
    /// k = shape′/shape. Mapped again when the shape's own values of the frame arrive (the element
    /// gets its values first).
    private static func mapElement(_ e: CALayer, host: CALayer, _ a: BoneGlassFlexAnchorView) {
        let id = ObjectIdentifier(e)
        guard let stock = element[id], let s = shape[ObjectIdentifier(host)], s.width > 0, s.height > 0 else { return }
        let rest = host.bounds.size
        let m = mapped(s, rest: rest, a)
        let k = CGSize(width: m.width / s.width, height: m.height / s.height)
        let position = CGPoint(x: m.minX + (stock.minX - s.minX) * k.width, y: m.minY + (stock.minY - s.minY) * k.height)
        setBounds(e, boundsSel, CGRect(origin: .zero, size: CGSize(width: stock.width * k.width, height: stock.height * k.height)))
        setPosition(e, positionSel, position)
        if let c = elementRadius[id] { setRadius(e, radiusSel, c * min(m.width, m.height) / min(s.width, s.height)) }   // a capsule stays one
    }

    static func install() {
        guard !installed else { return }
        installed = true
        guard let transformM = class_getInstanceMethod(CALayer.self, transformSel),
              let affineM = class_getInstanceMethod(CALayer.self, affineSel),
              let positionM = class_getInstanceMethod(CALayer.self, positionSel),
              let boundsM = class_getInstanceMethod(CALayer.self, boundsSel),
              let radiusM = class_getInstanceMethod(CALayer.self, radiusSel) else { return }
        setTransform = unsafeBitCast(method_getImplementation(transformM), to: SetTransform.self)
        setAffine = unsafeBitCast(method_getImplementation(affineM), to: SetAffine.self)
        setPosition = unsafeBitCast(method_getImplementation(positionM), to: SetPoint.self)
        setBounds = unsafeBitCast(method_getImplementation(boundsM), to: SetRect.self)
        setRadius = unsafeBitCast(method_getImplementation(radiusM), to: SetFloat.self)

        // content scale
        let transformBlock: @convention(block) (CALayer, CATransform3D) -> Void = { layer, t in
            guard case .content? = role(of: layer),
                  let a = anchor(around: layer, restSize: layer.bounds.size) else { return setTransform(layer, transformSel, t) }
            rawScale[ObjectIdentifier(layer)] = CGSize(width: t.m11, height: t.m22)
            contentSetAt[ObjectIdentifier(layer)] = CACurrentMediaTime()
            var m = t
            m.m11 = scaled(t.m11, a.stretch)
            m.m22 = scaled(t.m22, a.stretch)
            guarded { setTransform(layer, transformSel, m) }
        }
        let affineBlock: @convention(block) (CALayer, CGAffineTransform) -> Void = { layer, t in
            guard case .content? = role(of: layer),
                  let a = anchor(around: layer, restSize: layer.bounds.size) else { return setAffine(layer, affineSel, t) }
            rawScale[ObjectIdentifier(layer)] = CGSize(width: t.a, height: t.d)
            contentSetAt[ObjectIdentifier(layer)] = CACurrentMediaTime()
            var m = t
            m.a = scaled(t.a, a.stretch)
            m.d = scaled(t.d, a.stretch)
            guarded { setAffine(layer, affineSel, m) }
        }
        // outline size: rest + stretch·(size − rest); the element scaled about the shape
        let boundsBlock: @convention(block) (CALayer, CGRect) -> Void = { layer, r in
            switch role(of: layer) {
            case .outline(let host)?:
                guard r.width > 0, r.height > 0, let a = anchor(around: layer, restSize: host.bounds.size) else { break }
                let rest = host.bounds.size
                let hid = ObjectIdentifier(host)
                let stockOrigin = shape[hid]?.origin ?? .zero
                shape[hid] = CGRect(origin: stockOrigin, size: r.size)
                let m = mapped(CGRect(origin: r.origin, size: r.size), rest: rest, a)
                // the stock origin mirrors the position (children cancel it): map it the same way
                let o = r.origin == .zero ? r.origin : m.origin
                return guarded {
                    setBounds(layer, boundsSel, CGRect(origin: o, size: m.size))
                    if layer.superlayer === host { elements(in: host).forEach { mapElement($0, host: host, a) } }
                }
            case .element(let host)?:
                guard let a = anchor(around: layer, restSize: host.bounds.size) else { break }
                let id = ObjectIdentifier(layer)
                element[id] = CGRect(origin: element[id]?.origin ?? .zero, size: r.size)
                return guarded { mapElement(layer, host: host, a) }
            default:
                break
            }
            setBounds(layer, boundsSel, r)
        }
        let radiusBlock: @convention(block) (CALayer, CGFloat) -> Void = { layer, c in
            guard case .element(let host)? = role(of: layer),
                  let a = anchor(around: layer, restSize: host.bounds.size) else { return setRadius(layer, radiusSel, c) }
            elementRadius[ObjectIdentifier(layer)] = c
            guarded { mapElement(layer, host: host, a) }
        }
        // position of all: recentred, finger shift × follow
        let positionBlock: @convention(block) (CALayer, CGPoint) -> Void = { layer, p in
            switch role(of: layer) {
            case .content?:
                guard let a = anchor(around: layer, restSize: layer.bounds.size) else { break }
                let raw = rawScale[ObjectIdentifier(layer)] ?? CGSize(width: 1, height: 1)
                let mapped = origin(p, raw: raw, rest: layer.bounds.size, a)
                return guarded { setPosition(layer, positionSel, mapped) }
            case .outline(let host)?:
                guard let a = anchor(around: layer, restSize: host.bounds.size) else { break }
                let rest = host.bounds.size
                let hid = ObjectIdentifier(host)
                let size = shape[hid]?.size ?? rest
                shape[hid] = CGRect(origin: p, size: size)
                let r = raw(size, rest: rest)
                guarded {
                    setPosition(layer, positionSel, origin(p, raw: r, rest: rest, a))
                    guard layer.superlayer === host else { return }
                    elements(in: host).forEach { mapElement($0, host: host, a) }
                    // the content gets no setters while it springs back: follow the outline
                    if let content = content(in: host),
                       CACurrentMediaTime() - (contentSetAt[ObjectIdentifier(content)] ?? 0) > 0.05 {
                        var t = CGAffineTransform.identity
                        t.a = scaled(r.width, a.stretch)
                        t.d = scaled(r.height, a.stretch)
                        setAffine(content, affineSel, t)
                        setPosition(content, positionSel, origin(p, raw: r, rest: content.bounds.size, a))
                    }
                }
                return
            case .element(let host)?:
                guard let a = anchor(around: layer, restSize: host.bounds.size) else { break }
                let id = ObjectIdentifier(layer)
                element[id] = CGRect(origin: p, size: element[id]?.size ?? host.bounds.size)
                return guarded { mapElement(layer, host: host, a) }
            case nil:
                break
            }
            setPosition(layer, positionSel, p)
        }
        method_setImplementation(transformM, imp_implementationWithBlock(transformBlock))
        method_setImplementation(affineM, imp_implementationWithBlock(affineBlock))
        method_setImplementation(boundsM, imp_implementationWithBlock(boundsBlock))
        method_setImplementation(positionM, imp_implementationWithBlock(positionBlock))
        method_setImplementation(radiusM, imp_implementationWithBlock(radiusBlock))
    }
}

#endif
