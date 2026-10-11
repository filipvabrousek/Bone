//
//  PublicAPITests.swift
//  BoneTests
//
//  The documented API, written the way the docs write it, through a plain
//  `import Bone`: if something the docs show is not public, this file does not
//  compile. Building the views runs no Bone code.
//

import CoreGraphics
import SwiftUI
import Testing
import Bone

@Suite("Public API")
@MainActor
struct PublicAPITests {

    @Test("every documented modifier is reachable from outside the module")
    func documentedModifiers() {
        var views: [AnyView] = [
            AnyView(Text("Hello").bone(into: "output.txt")),
            AnyView(Button("Liquid") {}.glassEffect().tune(.noShadow + .noLensing)),
            AnyView(Button("Liquid") {}.glassEffect().tune([.blurRadius: 0, .faceOpacity: 0.3, .keyFillHighlightAmount: 1])),
            AnyView(Button("Liquid") {}.glassEffect().tune(.flat + .aberration, log: "tune.txt")),
            AnyView(Button("Liquid") {}.glassEffect().tune(.raw(["vibrantColorMatrix.inputColorMatrix": BoneColorMatrix.value(BoneColorMatrix.invert)]))),
            AnyView(Button("Liquid") {}.glassEffect().tune([.shadowOffset: .size(0, 8), .faceColorMatrixFillColor: .color(.red)])),
            AnyView(Button("Liquid") {}.glassEffect().dumpGlass("glass.txt", only: [.blurRadius, .shadowOpacity])),
            AnyView(Button("Liquid") {}.glassEffect().probeGlass("glass-probe.txt")),
            AnyView(Text("Hello").tuneLayers([.rotationY: 35, .shadowOpacity: 1, .shadowRadius: 8], where: .text)),
            AnyView(Text("Go").tuneLayers([.filters: .filters([.colorHueRotate(2.2), .gaussianBlur(2), .colorInvert])])),
            AnyView(Image(systemName: "star.fill").tuneLayers([.blendMode: .blend(.difference)], where: .shape || .gradient)),
            AnyView(VStack {}.tuneLayers(.outline + [.opacity: 0.6], where: .all)),
            AnyView(Text("Hi").tuneLayers(.raw(["cornerCurve": "continuous"]), where: .className("CGDrawing"))),
            AnyView(VStack {}.dumpLayers("layers.txt")),
            AnyView(Text("Hi").dumpShaders("shaders.txt", matching: "glass")),
            AnyView(Text("App").boneInspector()),
            AnyView(Text("App").glassPanel()),
        ]
        #if os(iOS)
        views += [
            AnyView(Text("Hello").bone(into: "output.json", fromRoot: true)),
            AnyView(Button("Liquid") {}.glassEffect().tune(file: "glass-panel.json")),
            AnyView(Button("Liquid") {}.glassEffect().tune(excludeShadow: true, contentLensing: false)),
            AnyView(Button("Liquid") {}.glassEffect().dumpGlass("glass-full.txt", full: true)),
            AnyView(Button("Liquid") {}.buttonStyle(.glass).glassFlex()),
            AnyView(Menu("Options") { Button("Copy") {} }.morphTimeline(speed: 0.1)),
            AnyView(Menu("Options") { Button("Copy") {} }.morphScrubber()),
            AnyView(Menu("Options") { Button("Copy") {} }.dumpMorph("menu-morph.csv")),
            AnyView(Text("Small").liquidMorph(to: Text("Big"), isPresented: .constant(false))),
        ]
        #endif
        #expect(views.count > 10)

        BoneCapture.maxIvarLength = 20_000
        BoneCapture.captureIvarDescriptions = true
        _ = BoneCapture.ivarDenylist
        #expect(GlassInput.allCases.count >= 69)
        #expect(LayerProperty.allCases.contains(.blendMode))
    }
}
