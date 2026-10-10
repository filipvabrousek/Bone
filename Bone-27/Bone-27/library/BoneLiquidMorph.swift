//
//  BoneLiquidMorph.swift
//  Bone-27
//
//  Apple's own Liquid Glass morph between any two SwiftUI views:
//
//      Text("Hello")
//          .liquidMorph(to: Circle().foregroundStyle(.green).frame(width: 30, height: 30),
//                       isPresented: $on)
//
//  Both ends sit in public Liquid Glass (UIVisualEffectView + UIGlassEffect,
//  capsule corners); toggling `isPresented` morphs one into the other with
//  UIKit's _UIMagicMorphAnimation – the AnimationKit morph of the floating tab
//  bar and the search field: the glass stretches between the two shapes, the
//  contents blur across, the lensing refracts what is behind. It is driven
//  through its Objective-C door: morphTo:(UITargetedPreview) once for the
//  source (lifted into UIKit's MagicMorphView), once for the target.
//
//  (The menu's own LiquidMorphAnimation – the drop step – has only a Swift API
//  whose arguments are values of AnimationKit's private protocols; it cannot be
//  called from outside without forging them.)
//
//  The target appears centred on the source; layout keeps the source's size.
//  Without the class (before iOS 26) the two just cross-fade.
//
//  Research / simulator use only — private API, never ship it.
//

#if canImport(UIKit) && !os(visionOS)

import SwiftUI
import UIKit

extension View {

    /// Morphs this view into `target` (and back) with UIKit's Liquid Glass morph when
    /// `isPresented` changes. Both ends are shown in glass capsules.
    func liquidMorph<Target: View>(to target: Target, isPresented: Binding<Bool>,
                                   padding: EdgeInsets = EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16),
                                   targetPadding: EdgeInsets = EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)) -> some View {
        BoneLiquidMorphHost(source: self, target: target, presented: isPresented.wrappedValue,
                            padding: padding, targetPadding: targetPadding)
    }
}

struct BoneLiquidMorphHost<Source: View, Target: View>: UIViewRepresentable {
    let source: Source
    let target: Target
    let presented: Bool
    let padding: EdgeInsets
    let targetPadding: EdgeInsets

    func makeUIView(context: Context) -> BoneLiquidMorphView {
        let v = BoneLiquidMorphView()
        v.source.root = UIHostingController(rootView: AnyView(source))
        v.target.root = UIHostingController(rootView: AnyView(target))
        v.install(presented: presented)
        return v
    }

    func updateUIView(_ v: BoneLiquidMorphView, context: Context) {
        v.source.root?.rootView = AnyView(source)
        v.target.root?.rootView = AnyView(target)
        v.source.padding = UIEdgeInsets(padding)
        v.target.padding = UIEdgeInsets(targetPadding)
        v.setNeedsLayout()
        v.set(presented: presented)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: BoneLiquidMorphView, context: Context) -> CGSize? {
        uiView.source.padding = UIEdgeInsets(padding)
        return uiView.source.fittingSize()                 // layout keeps the source's size
    }
}

private extension UIEdgeInsets {
    init(_ e: EdgeInsets) { self.init(top: e.top, left: e.leading, bottom: e.bottom, right: e.trailing) }
}

/// One end of the morph: a glass capsule hosting a SwiftUI view.
final class BoneMorphEnd {
    let glass = UIVisualEffectView(effect: UIGlassEffect())
    var padding = UIEdgeInsets.zero
    var root: UIHostingController<AnyView>? {
        didSet {
            oldValue?.view.removeFromSuperview()
            guard let root else { return }
            root.view.backgroundColor = .clear
            root.sizingOptions = .intrinsicContentSize
            glass.contentView.addSubview(root.view)
        }
    }

    init() {
        glass.cornerConfiguration = .capsule()
    }

    /// Content size plus padding. A flexible dimension (a Circle with only a width) takes
    /// the other one: square.
    func fittingSize() -> CGSize {
        guard let root else { return .zero }
        var s = root.sizeThatFits(in: CGSize(width: 2000, height: 2000))
        if s.width >= 2000 { s.width = s.height < 2000 ? s.height : 44 }
        if s.height >= 2000 { s.height = s.width }
        return CGSize(width: ceil(s.width + padding.left + padding.right), height: ceil(s.height + padding.top + padding.bottom))
    }

    func layout(centeredAt center: CGPoint) {
        let size = fittingSize()
        glass.bounds = CGRect(origin: .zero, size: size)
        glass.center = center
        root?.view.frame = glass.bounds.inset(by: padding)
    }
}

final class BoneLiquidMorphView: UIView {
    let source = BoneMorphEnd()
    let target = BoneMorphEnd()
    private(set) var presented = false
    private var morph: NSObject?
    private var morphing = false
    private var pending: Bool?

    func install(presented: Bool) {
        clipsToBounds = false
        backgroundColor = .clear
        addSubview(source.glass)
        addSubview(target.glass)
        self.presented = presented
        source.glass.isHidden = presented
        target.glass.isHidden = !presented
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !morphing else { return }                    // the morph owns the frames meanwhile
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        source.layout(centeredAt: center)
        target.layout(centeredAt: center)
    }

    func set(presented new: Bool) {
        guard new != presented else { return }
        guard !morphing else { pending = new; return }     // after the running morph
        presented = new
        let (from, to) = new ? (source, target) : (target, source)
        guard window != nil, let cls = NSClassFromString("_UIMagicMorphAnimation") as? NSObject.Type else {
            UIView.transition(with: self, duration: 0.3, options: .transitionCrossDissolve) {
                from.glass.isHidden = true
                to.glass.isHidden = false
            }
            return
        }
        layoutIfNeeded()
        morphing = true
        let m = cls.init()
        morph = m
        m.perform(NSSelectorFromString("setClientContainerView:"), with: self)
        // 1. lift the current end into UIKit's morph view, 2. morph it to the other end
        Self.morphTo(m, preview(from), reparent: true, completion: nil)
        to.glass.isHidden = false
        Self.morphTo(m, preview(to), reparent: false) { [weak self] in
            guard let self else { return }
            from.glass.isHidden = true
            to.glass.isHidden = false
            self.morphing = false
            self.morph = nil
            self.setNeedsLayout()
            if let next = self.pending { self.pending = nil; self.set(presented: next) }
        }
    }

    private func preview(_ end: BoneMorphEnd) -> UITargetedPreview {
        let parameters = UIPreviewParameters()
        let r = end.glass.bounds
        parameters.visiblePath = UIBezierPath(roundedRect: r, cornerRadius: min(r.width, r.height) / 2)
        parameters.backgroundColor = .clear
        return UITargetedPreview(view: end.glass, parameters: parameters,
                                 target: UIPreviewTarget(container: self, center: end.glass.center))
    }

    private typealias MorphTo = @convention(c) (AnyObject, Selector, AnyObject, Bool,
                                                @convention(block) () -> Void, @convention(block) () -> Void) -> Void

    /// -[_UIMagicMorphAnimation morphTo:reparentWithoutAnimation:alongsideAnimations:completion:]
    private static func morphTo(_ morph: NSObject, _ preview: UITargetedPreview, reparent: Bool, completion: (() -> Void)?) {
        let sel = NSSelectorFromString("morphTo:reparentWithoutAnimation:alongsideAnimations:completion:")
        guard let method = class_getInstanceMethod(object_getClass(morph), sel) else { completion?(); return }
        let call = unsafeBitCast(method_getImplementation(method), to: MorphTo.self)
        // plain blocks: an optional Swift closure turned into an optional block crashed the compiler
        let alongside: @convention(block) () -> Void = {}
        let done: @convention(block) () -> Void = { completion?() }
        call(morph, sel, preview, reparent, alongside, done)
    }
}

#endif
