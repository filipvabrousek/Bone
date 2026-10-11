//
//  GlassTests.swift
//  BoneTests
//
//  GlassInput, GlassTuning and the value formats, checked against real
//  .dumpGlass captures from iOS, macOS and watchOS.
//

import CoreGraphics
import Foundation
import Testing
@testable import Bone

extension GlassValue {
    var number: Double? { if case .number(let d) = self { return d }; return nil }
}

@Suite("Glass inputs")
struct GlassInputTests {

    @Test("every input a real dump names maps to its GlassInput case", arguments: ["ios-glass.txt", "mac-glass.txt", "watch-glass.txt"])
    func dumpNamesMatchCases(file: String) throws {
        let lines = try Fixture.glassLines(file).filter { $0.filter == "glassBackground" }
        #expect(lines.count >= 60, "a glass button sets ~70 inputs; got \(lines.count)")
        for l in lines {
            let input = try #require(GlassInput(rawValue: l.key), "\(l.key) in \(file) has no GlassInput case")
            #expect(input.caseName == l.caseName)
        }
    }

    @Test("the 69 inputs SwiftUI set on iOS 27 are all cases")
    func iOSInputsAreCovered() throws {
        let keys = Set(try Fixture.glassLines("ios-glass.txt").filter { $0.filter == "glassBackground" }.map(\.key))
        let known = Set(GlassInput.allCases.map(\.rawValue))
        #expect(keys.isSubset(of: known))
        #expect(keys.count >= 69)
    }

    @Test("dump values are written the way BoneGlassFormat writes them")
    func formatMatchesDump() throws {
        // numbers in the real dump: integers bare, the rest to 4 places
        for l in try Fixture.glassLines("ios-glass.txt") {
            guard let d = Double(l.value) else { continue }
            #expect(BoneGlassFormat.value(NSNumber(value: d)) == l.value, "\(l.caseName) = \(l.value)")
        }
        #expect(BoneGlassFormat.value(NSNumber(value: 5)) == "5")
        #expect(BoneGlassFormat.value(NSNumber(value: -39.83333)) == "-39.8333")
        #expect(BoneGlassFormat.value(nil) == "nil")
    }

    @Test("named(_:) takes case names; Core Animation keys pass through tunerValues as they are")
    func named() throws {
        #expect(GlassInput.named("blurRadius") == .blurRadius)
        #expect(GlassInput.named("inputBlurRadius") == nil)
        let values = try #require(BoneGlassJSON.tunerValues(from: Data(#"{"blurRadius": 1, "inputFaceOpacity": 0.5}"#.utf8)))
        #expect(Set(values.keys) == ["inputBlurRadius", "inputFaceOpacity"])
    }
}

@Suite("Glass tuning")
struct GlassTuningTests {

    @Test("+ merges, the right side wins")
    func plusRightWins() {
        let t: GlassTuning = [.blurRadius: 1, .faceOpacity: 0.5] + [.blurRadius: 0]
        #expect(t.values[.blurRadius]?.number == 0)
        #expect(t.values[.faceOpacity]?.number == 0.5)
    }

    @Test("flat is every preset together")
    func flatCoversPresets() {
        let parts: [GlassTuning] = [.noShadow, .noLensing, .noBlur, .noHighlight, .noBleed]
        let keys = parts.reduce(into: Set<GlassInput>()) { $0.formUnion($1.values.keys) }
        #expect(Set(GlassTuning.flat.values.keys) == keys)
        #expect(GlassTuning.flat.values.values.allSatisfy { $0.number == 0 })
    }

    @Test("caValues uses Core Animation keys and keeps raw ones")
    func caValues() {
        let t = GlassTuning(values: [.blurRadius: 3], raw: ["inputSomethingNew": 1])
        let ca = t.caValues
        #expect((ca["inputBlurRadius"] as? NSNumber)?.doubleValue == 3)
        #expect((ca["inputSomethingNew"] as? Int) == 1)
    }

    @Test("sizes and colours become what Core Animation expects")
    func valueObjects() {
        let size = GlassValue.size(0, 8).object as? NSValue
        #expect(size?.boneSize == CGSize(width: 0, height: 8))
        let color = GlassValue.color(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)).object
        #expect(CFGetTypeID(color as CFTypeRef) == CGColor.typeID)
        #expect((GlassValue(booleanLiteral: true).object as? NSNumber)?.doubleValue == 1)
    }
}

@Suite("Glass JSON (inspector Save → .tune(file:))")
struct GlassJSONTests {

    @Test("the panel's saved file loads as Core Animation keys")
    func panelFile() throws {
        let file = try Fixture.data("glass-panel.json")
        let values = try #require(BoneGlassJSON.tunerValues(from: file))
        let amount = try #require(values["inputAberrationAmount"] as? NSNumber)
        #expect(abs(amount.doubleValue - 52.2971) < 0.001)
    }

    @Test("colour, size and matrix survive encode → decode")
    func roundTrip() throws {
        let color = CGColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 0.8)
        let encodedColor = try #require(BoneGlassJSON.encode(color))
        let decodedColor = try #require(BoneGlassJSON.decode(encodedColor))
        #expect(CFGetTypeID(decodedColor as CFTypeRef) == CGColor.typeID)
        #expect((decodedColor as! CGColor).components?.map { ($0 * 100).rounded() } == [20, 40, 60, 80])

        let size = NSValue.bone(size: CGSize(width: 3, height: 4))
        let encodedSize = try #require(BoneGlassJSON.encode(size))
        let decodedSize = try #require(BoneGlassJSON.decode(encodedSize) as? NSValue)
        #expect(decodedSize.boneSize == CGSize(width: 3, height: 4))

        let matrix = BoneColorMatrix.value(BoneColorMatrix.invert)
        let encodedMatrix = try #require(BoneGlassJSON.encode(matrix))
        let decodedMatrix = try #require(BoneGlassJSON.decode(encodedMatrix))
        #expect(BoneColorMatrix.floats(from: decodedMatrix) == BoneColorMatrix.invert)
    }

    @Test("a short matrix is padded to 4×5")
    func matrixPadding() throws {
        let floats = try #require(BoneColorMatrix.floats(from: BoneColorMatrix.value([1, 2, 3])))
        #expect(floats.count == 20)
        #expect(Array(floats.prefix(4)) == [1, 2, 3, 0])
    }
}

@Suite("Glass report (shared by iOS, macOS and watchOS)")
struct GlassReportTests {

    @Test("a .tune log line comes out as in a real watchOS 27 log")
    func changeLine() throws {
        let log = try Fixture.text("watch-tune.txt")
        let line = BoneGlassReport.change(layer: "CABackdropLayer", path: "filters.glassBackground.inputBleedAmount",
                                          from: NSNumber(value: 18.375), to: NSNumber(value: 0))
        #expect(log.contains(line + "\n"), "\(line)")
        #expect(log.hasPrefix(BoneGlassReport.tuneLog(values: [:], changes: [], os: "watchOS 27.0").prefix(25)))
    }

    @Test("plain keys go to glass filters, prefixed keys to the named filter")
    func inputRouting() {
        #expect(BoneGlassReport.input("inputBlurRadius", name: "glassBackground", type: "glassBackground") == "inputBlurRadius")
        #expect(BoneGlassReport.input("inputBlurRadius", name: "vibrantColorMatrix", type: "vibrantColorMatrix") == nil)
        #expect(BoneGlassReport.input("vibrantColorMatrix.inputColorMatrix", name: "vibrantColorMatrix", type: "vibrantColorMatrix")
                == "inputColorMatrix")
        #expect(BoneGlassReport.input("vibrantColorMatrix.inputColorMatrix", name: "glassBackground", type: "glassBackground") == nil)
    }

    @Test("values already in place are not written again")
    func same() {
        #expect(BoneGlassReport.same(NSNumber(value: 0.1 + 0.2), NSNumber(value: 0.3)))
        #expect(!BoneGlassReport.same(NSNumber(value: 1), NSNumber(value: 0)))
        let red = CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
        #expect(BoneGlassReport.same(red, CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)))
        #expect(!BoneGlassReport.same(red, CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)))
    }

    @Test("the dump report lists glass filters, labelled with their GlassInput case")
    func dumpText() {
        let rows = [BoneGlassFilterRow(path: "CALayer ▹ [0]CABackdropLayer", slot: "filters", type: "glassBackground",
                                       inputs: [("inputBlurRadius", NSNumber(value: 5)), ("inputSomethingNew", NSNumber(value: 1))]),
                    BoneGlassFilterRow(path: "CALayer ▹ [2]CASDFLayer", slot: "filters", type: "vibrantColorMatrix", inputs: [])]
        let all = BoneGlassReport.dump(rows, only: nil, os: "iOS 27.0")
        #expect(all.contains("glass filters: 1\n"))
        #expect(all.contains("===== [0] glassBackground  (filters on CALayer ▹ [0]CABackdropLayer) ====="))
        #expect(all.contains("   blurRadius  (inputBlurRadius) = 5\n"))
        #expect(all.contains("   inputSomethingNew             = 1\n"))
        #expect(all.contains("===== [1] vibrantColorMatrix"))
        let some = BoneGlassReport.dump(rows, only: [.blurRadius], os: "iOS 27.0")
        #expect(!some.contains("vibrantColorMatrix") && !some.contains("inputSomethingNew"))
    }
}
