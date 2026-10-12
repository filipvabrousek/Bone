//
//  IvarTests.swift
//  BoneTests
//
//  Bone's own ivar description (BoneIvars) on a real AppKit view: the
//  Objective-C levels read by type encoding, the Swift level by reflection.
//

#if os(macOS)

import AppKit
import Testing
@testable import Bone

final class IvarProbeView: NSView {
    struct Pair { var a = 1.5; var b = 2.0 }
    var count = 7
    var name = "probe"
    var size = CGSize(width: 3, height: 4)
    var pair = Pair()
    var mode: NSUserInterfaceLayoutDirection = .rightToLeft
    weak var buddy: NSView?
}

@Suite("Ivar description")
@MainActor
struct IvarTests {

    @Test("Swift subclass of NSView: Swift fields and AppKit ivars, level by level")
    func describesBothLevels() {
        let view = IvarProbeView(frame: CGRect(x: 1, y: 2, width: 30, height: 40))
        #expect(BoneIvars.hasSwiftLevel(view))
        #expect(!BoneIvars.hasSwiftLevel(NSView()))
        let text = BoneIvars.describe(view, maxLength: 100_000)
        #expect(text.contains("in BoneTests.IvarProbeView:\n"))
        #expect(text.contains("in NSView:\n") && text.contains("in NSResponder:\n"))
        #expect(text.contains("\tcount (Int): 7\n"))
        #expect(text.contains("\tname (String): \"probe\"\n"))
        #expect(text.contains("\tsize (CGSize): {3, 4}\n"))
        #expect(text.contains("\tpair (Pair): {a: 1.5, b: 2}\n"))
        #expect(text.contains("\tbuddy (Optional<NSView>): nil\n"))
        // NSView's own _frame, read from its type encoding (field names are quoted in it)
        let frame = text.split(separator: "\n").first { $0.hasPrefix("\t_frame ") }
        #expect(frame?.hasSuffix(": {1, 2, 30, 40}") == true, "\(frame ?? "no _frame line")")
    }
}

#endif
