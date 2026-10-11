//
//  TimelineTests.swift
//  BoneTests
//
//  The timeline's contact sheet and change detection (iOS and macOS). The
//  frames are synthetic: this checks Bone's own layout, not the system.
//

#if !os(watchOS) && !os(visionOS)

import CoreGraphics
import ImageIO
import Testing
@testable import Bone

@Suite("Timeline")
struct TimelineTests {

    /// A solid frame whose red channel is its index.
    static func frame(_ i: Int, width: Int = 300, height: Int = 600) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: CGFloat(i) / 255, green: 0.5, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    /// RGBA at (x, y) from the top-left.
    static func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> [UInt8] {
        var px = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
        return px
    }

    @Test("12 evenly spaced frames, six to a row at a third of their size, label band above each")
    func contactSheetLayout() throws {
        let png = try #require(BoneTimelineKit.contactSheet(count: 34, frame: { Self.frame($0) }, label: { "\($0)" }))
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let sheet = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(sheet.width == 6 * 100 && sheet.height == 2 * (200 + 28))
        // picks: 0, 3, 6, … 33 (k * 33 / 11); cell k's centre carries that frame's red
        let picks = (0..<12).map { $0 * 33 / 11 }
        for (k, frame) in picks.enumerated() {
            let x = (k % 6) * 100 + 50, y = (k / 6) * 228 + 28 + 100
            let red = Int(Self.pixel(sheet, x, y)[0])
            #expect(abs(red - frame) <= 1, "cell \(k) shows frame \(frame), red \(red)")
        }
        #expect(Self.pixel(sheet, 99, 26) == [255, 255, 255, 255])            // label band: white
    }

    @Test("a short take shows every frame; nothing to show gives nil")
    func shortTakes() throws {
        let png = try #require(BoneTimelineKit.contactSheet(count: 3, frame: { Self.frame($0) }, label: { "\($0)" }))
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let sheet = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(sheet.width == 300 && sheet.height == 228)
        #expect(BoneTimelineKit.contactSheet(count: 0, frame: { Self.frame($0) }, label: { "\($0)" }) == nil)
    }

    @Test("change detection ignores ±3 per channel")
    func sameThumbnails() {
        let a = BoneTimelineKit.thumbnail(Self.frame(100), divisor: 8)
        #expect(a.count == (300 / 8) * (600 / 8) * 4)
        #expect(BoneTimelineKit.same(a, BoneTimelineKit.thumbnail(Self.frame(103), divisor: 8)))
        #expect(!BoneTimelineKit.same(a, BoneTimelineKit.thumbnail(Self.frame(110), divisor: 8)))
        #expect(BoneTimelineKit.mean(a) > 100)
    }

    @Test func labels() {
        #expect(BoneTimelineKit.label(0.05) == "1⁄20")
        #expect(BoneTimelineKit.label(0.3) == "0.3×")
        #expect(BoneTimelineKit.seconds(0.7849) == "0.785 s")
    }
}

#endif
