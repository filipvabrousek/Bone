//
//  BoneTimelineKit.swift
//  Bone-27
//
//  What the iOS and macOS timeline bars share (BoneTimeline.swift,
//  BoneMacTimeline.swift): the speeds, the time label, change detection on
//  small thumbnails, the take's contact sheet and the take slider row.
//
//  Research use only — never ship it.
//

#if DEBUG   // Bone is private API: it compiles to nothing outside Debug builds

#if (canImport(UIKit) && !os(watchOS) && !os(visionOS)) || os(macOS)

import CoreText
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
private typealias BonePlatformFont = UIFont
#else
import AppKit
private typealias BonePlatformFont = NSFont
#endif

enum BoneTimelineKit {

    static let speeds: [(label: String, value: Double)] = [("1×", 1), ("½", 0.5), ("¼", 0.25), ("⅒", 0.1), ("1⁄20", 0.05)]

    static func label(_ speed: Double) -> String {
        speeds.first { $0.value == speed }?.label ?? String(format: "%g×", speed)
    }

    static func seconds(_ t: Double) -> String { String(format: "%.3f s", t) }

    // MARK: Change detection

    /// A 1/`divisor`-size RGBA copy.
    static func thumbnail(_ image: CGImage, divisor: Int) -> [UInt8] {
        let w = max(1, image.width / divisor), h = max(1, image.height / divisor)
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        buf.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            ctx.interpolationQuality = .low
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return buf
    }

    /// No channel of any pixel differs by more than 3.
    static func same(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        guard a.count == b.count else { return false }
        for i in stride(from: 0, to: a.count, by: 4) where abs(Int(a[i]) - Int(b[i])) > 3
            || abs(Int(a[i + 1]) - Int(b[i + 1])) > 3 || abs(Int(a[i + 2]) - Int(b[i + 2])) > 3 { return false }
        return true
    }

    /// Mean of R, G and B over a thumbnail (0–255): ~0 means the screen read back black.
    static func mean(_ a: [UInt8]) -> Double {
        guard !a.isEmpty else { return 0 }
        var sum = 0
        for i in stride(from: 0, to: a.count, by: 4) { sum += Int(a[i]) + Int(a[i + 1]) + Int(a[i + 2]) }
        return Double(sum) / Double(a.count / 4 * 3)
    }

    // MARK: Contact sheet

    /// Up to 12 evenly spaced frames of a take, six to a row at a third of their size, each
    /// labelled by `label(index)` above it – as PNG.
    static func contactSheet(count: Int, frame: (Int) -> CGImage?, label: (Int) -> String) -> Data? {
        let shown = min(12, count)
        guard shown > 0 else { return nil }
        let picks = (0..<shown).map { k in shown == 1 ? 0 : k * (count - 1) / (shown - 1) }
        let frames = picks.compactMap { i in frame(i).map { (index: i, image: $0) } }
        guard let first = frames.first?.image else { return nil }

        let cols = min(6, frames.count), rows = (frames.count + cols - 1) / cols
        let cell = CGSize(width: CGFloat(first.width) / 3, height: CGFloat(first.height) / 3)
        let band: CGFloat = 28                                                   // label above each frame
        let size = CGSize(width: cell.width * CGFloat(cols), height: (cell.height + band) * CGFloat(rows))
        guard let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))

        let font = BonePlatformFont.monospacedSystemFont(ofSize: 18, weight: .semibold)
        for (k, f) in frames.enumerated() {
            // laid out from the top; Core Graphics counts from the bottom
            let x = CGFloat(k % cols) * cell.width
            let top = CGFloat(k / cols) * (cell.height + band)
            ctx.draw(f.image, in: CGRect(x: x, y: size.height - top - band - cell.height, width: cell.width, height: cell.height))
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: label(f.index), attributes: [.font: font]))
            ctx.textPosition = CGPoint(x: x + 8, y: size.height - top - 4 - CTFontGetAscent(font as CTFont))
            CTLineDraw(line, ctx)
        }

        guard let sheet = ctx.makeImage() else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, sheet, nil)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }
}

/// The take slider: 0.0 … 1.0 over one recorded take, with Save and Live.
struct BoneTakeRow: View {
    let count: Int
    @Binding var frameIndex: Int
    let caption: String
    let save: () -> Void
    let live: () -> Void

    private var progress: Double { count > 1 ? Double(frameIndex) / Double(count - 1) : 0 }

    var body: some View {
        BoneSlider(value: Binding(get: { progress },
                                  set: { frameIndex = Int(($0 * Double(max(count - 1, 0))).rounded()) }),
                   in: 0...1)
        HStack {
            Text(caption)
                .font(.caption.monospacedDigit())
            Spacer()
            Button("Save", action: save)
            Button("Live", action: live)
        }
        .font(.caption.bold())
    }
}

#endif

#endif   // DEBUG
