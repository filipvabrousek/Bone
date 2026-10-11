//
//  LayerTests.swift
//  BoneTests
//
//  LayerTuning's transform and LayerTarget's matching. Layer class names
//  are the ones SwiftUI really uses (captures/mac-layers.txt, layers.txt).
//

import QuartzCore
import Testing
@testable import Bone

/// Stand-ins named like SwiftUI's private layer classes; targets match on the class name.
final class CGDrawingLayer: CALayer {}
final class ColorShapeLayer: CALayer {}

@Suite("Layer tuning")
struct LayerTuningTests {

    @Test("+ merges, the right side wins")
    func plus() {
        let t: LayerTuning = [.opacity: 1, .rotation: 10] + [.rotation: 20]
        #expect(t.values[.rotation]?.number == 20)
        #expect(t.values[.opacity]?.number == 1)
        #expect(LayerTuning.outline.values[.borderWidth]?.number == 1)
    }

    @Test("no transform values: identity")
    func identity() {
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 100, height: 40)
        #expect(CATransform3DIsIdentity(LayerTuning(values: [.opacity: 0.5]).transform(for: layer)))
        #expect(!LayerTuning(values: [.opacity: 0.5]).hasTransform)
        #expect(LayerTuning(values: [.rotation: 5]).hasTransform)
    }

    @Test("rotation turns about the layer's centre, whatever its anchor point")
    func rotatesAboutCentre() {
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 100, height: 40)
        layer.anchorPoint = .zero
        let t = LayerTuning(values: [.rotation: 90]).transform(for: layer)
        let affine = CATransform3DGetAffineTransform(t)
        // in anchor-relative coordinates the centre is (50, 20): it must stay put
        let centre = CGPoint(x: 50, y: 20).applying(affine)
        #expect(abs(centre.x - 50) < 1e-9 && abs(centre.y - 20) < 1e-9)
        let corner = CGPoint(x: 0, y: 0).applying(affine)
        #expect(abs(corner.x - 70) < 1e-9 && abs(corner.y + 30) < 1e-9)
    }

    @Test("3D tilt gets the perspective")
    func perspective() {
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 10, height: 10)
        // m34 = -1/eye is set first, then the Y rotation is applied on top: -cos(angle)/eye
        let cos30 = cos(30 * Double.pi / 180)
        #expect(abs(LayerTuning(values: [.rotationY: 30]).transform(for: layer).m34 + cos30 / 500) < 1e-12)
        #expect(abs(LayerTuning(values: [.rotationY: 30, .perspective: 1000]).transform(for: layer).m34 + cos30 / 1000) < 1e-12)
        #expect(LayerTuning(values: [.rotation: 30]).transform(for: layer).m34 == 0)       // flat rotation: no perspective
    }
}

@Suite("Layer targets")
struct LayerTargetTests {

    @Test func classNames() {
        let text = CGDrawingLayer(), shape = ColorShapeLayer(), plain = CALayer()
        #expect(LayerTarget.text.matches(text) && !LayerTarget.text.matches(shape))
        #expect(LayerTarget.shape.matches(shape) && !LayerTarget.shape.matches(text))
        #expect((LayerTarget.text || .shape).matches(shape))
        #expect(!(LayerTarget.text || .shape).matches(plain))
        #expect(LayerTarget.preset(for: text).name == ".text")
    }

    @Test("leaves: drawn layers without sublayers")
    func leaves() {
        let parent = CALayer(), child = CALayer()
        parent.bounds = CGRect(x: 0, y: 0, width: 10, height: 10)
        child.bounds = parent.bounds
        parent.addSublayer(child)
        #expect(!LayerTarget.leaves.matches(parent))
        #expect(LayerTarget.leaves.matches(child))
        #expect(!LayerTarget.leaves.matches(CALayer()))          // no size
    }
}
