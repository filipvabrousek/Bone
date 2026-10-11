//
//  DumpTests.swift
//  BoneTests
//
//  The brief dump format (.bone(into:)), read back from a real iOS 27 dump,
//  and the text helpers the walk uses.
//

import Foundation
import Testing
@testable import Bone

@Suite("Brief dump")
struct BriefDumpTests {

    @Test("a real dump parses into its view tree")
    func parsesRealDump() throws {
        let (roots, os) = BoneBriefDumpParser.parse(try Fixture.text("ios-brief.txt"))
        #expect(os == "iOS:27")
        let root = try #require(roots.first)
        #expect(roots.count == 1)
        #expect(root.name == "_UIHostingView<Sample>")
        #expect(root.attributes.first { $0.key == "superclass" }?.value == "UIView")

        // the List's collection view, two levels down, with its data source
        let host = try #require(root.children.first)
        let collection = try #require(host.children.first)
        #expect(collection.name == "UpdateCoalescingCollectionView")
        #expect(collection.depth == 2)
        #expect(collection.attributes.contains { $0.key == "DataSource" && $0.value.hasPrefix("SwiftUI.ShadowListDataSource") })
    }

    @Test("every node line of the file becomes a node")
    func nodeCount() throws {
        let text = try Fixture.text("ios-brief.txt")
        let nodeLines = text.split(separator: "\n").filter { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            return t.hasSuffix(":") && !t.dropLast().contains(": ") && (t.first?.isUppercase == true || t.first == "_" || t.first == "-")
        }
        let roots = BoneBriefDumpParser.parse(text).roots
        #expect(roots.reduce(0) { $0 + $1.subtreeCount } == nodeLines.count)
    }

    @Test("brief text → parse and JSON → decode keep the tree")
    func roundTrips() throws {
        let roots = BoneBriefDumpParser.parse(try Fixture.text("ios-brief.txt")).roots
        func shape(_ n: BoneDumpNode) -> String {
            "\(n.depth) \(n.name) \(n.attributes.map { "\($0.key)=\($0.value)" })[\(n.children.map(shape).joined(separator: ","))]"
        }
        let again = BoneBriefDumpParser.parse(BoneDumpSerializer.briefText(roots: roots)).roots
        #expect(again.map(shape) == roots.map(shape))
        let decoded = try BoneDumpSerializer.rootsFromJSON(try BoneDumpSerializer.json(roots: roots))
        #expect(decoded.map(shape) == roots.map(shape))
    }
}

@Suite("Dump text helpers")
struct DumpTextTests {

    @Test func brackets() {
        #expect(BoneDumpText.brackets(in: "Optional(<CABackingStore 0x1 (buffer [62 32] A8)>)") == "<CABackingStore 0x1 (buffer [62 32] A8)>")
        #expect(BoneDumpText.brackets(in: "nil") == nil)
    }

    @Test("word(after:) reads a type name out of dump text")
    func wordAfter() {
        let text = "▿ Optional(…)\n  - dataSource: SwiftUI.ShadowListDataSource<X>; #0\n  - super: Base;"
        #expect(BoneDumpText.word(after: "dataSource:", offset: 1, in: text, ifContains: "dataSource:")
                == "SwiftUI.ShadowListDataSource<X>")
        #expect(BoneDumpText.word(after: "super:", offset: 1, in: text, ifContains: "super:") == "Base")
        #expect(BoneDumpText.word(after: "base:", offset: 1, in: text, ifContains: "base:") == "")
    }

    @Test("layerInfo finds SwiftUI layer classes")
    func layerInfo() {
        let info = BoneDumpText.layerInfo(in: "<SwiftUI.CGDrawingLayer: 0x1; delegate = SwiftUI.Host: 0x2>")
        #expect(info.layers == ["SwiftUI.CGDrawingLayer: "])
        #expect(info.delegates == ["SwiftUI.Host: "])
    }

    @Test("matches(for:) drops the key it matched on")
    func matches() {
        #expect(BoneDumpText.matches(for: "contents = <[a-zA-Z].*", in: "x contents = <CABackingStore 1>") == [" <CABackingStore 1>"])
        #expect(BoneDumpText.matchBetween(pattern: "layer: <(SwiftUI[^:]*)", in: "layer: <SwiftUI.CGDrawingLayer: 0x1")
                == ["layer: <SwiftUI.CGDrawingLayer"])
    }

    @Test func hexColors() {
        let c = BoneDumpStore.color(hex: "#3498DB").cgColor.components ?? []
        #expect(c.map { ($0 * 255).rounded() } == [52, 152, 219, 255])
        #expect(BoneDumpStore.colors.count == 16)
    }
}

#if os(macOS)
import AppKit

@Suite("macOS hierarchy walk", .serialized)
@MainActor
struct MacDumpWalkTests {

    @Test("16 views or more: colours repeat instead of running off the palette")
    func manyViews() {
        BoneDumpStore.items = []
        BoneDumpStore.formatted = ""
        BoneDumpStore.idx = 0
        let root = NSView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        for _ in 0..<20 { root.addSubview(NSView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))) }
        root.boneDumpSubviews()
        #expect(BoneDumpStore.items.count == 21)
        // the index counts up before each view, so item k has colour k + 1
        #expect(BoneDumpStore.items[17].color == BoneDumpStore.colors[18 % BoneDumpStore.colors.count])
        // the superclass is the word after "super:" in the dump (it keeps the line break after it)
        #expect(BoneDumpStore.items.allSatisfy { $0.superclass.trimmingCharacters(in: .whitespacesAndNewlines) == "NSResponder" })
        #expect(BoneDumpStore.formatted.contains("->NSView: NSResponder"))
    }
}
#endif
