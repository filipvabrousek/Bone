//
//  BoneMacTimeline.swift
//  Bone-27
//
//  The timeline bar on macOS (.boneInspector → pick hint → Timeline).
//
//  On the Mac, SwiftUI animates the glass morphs itself: no CAAnimations, and
//  AnimationKit's managers never tick. Every frame is computed in the app
//  window's hosting view, in -layout, at the current time. So:
//
//  ⏸       swallows that -layout: the window holds its frame (glass stays live –
//           inspect or tune it). SwiftUI's clock keeps running underneath, so ▶
//           jumps to where the animation is by then. There is no ⏭.
//  speed    animations started under .boneInspector() run at that speed
//           (Animation.speed on the root transaction – public API).
//  ⏺       waits for the window to change, then captures it once per 1/60 s
//           of animation (wall time × speed; at 1× as fast as ScreenCaptureKit
//           allows, ~50 fps) until it has settled. Slow down first for a smooth take. The slider
//           scrubs it both ways; Save writes a contact sheet.
//
//  The capture is the app window's rect; the panel is kept out of it with
//  sharingType = .none. Research use only – private behaviour, never ship it.
//

#if DEBUG   // Bone is private API: it compiles to nothing outside Debug builds

#if os(macOS)

import AppKit
import Combine
import ObjectiveC
import ScreenCaptureKit
import SwiftUI

/// Holds the app window's SwiftUI frames: its hosting view's -layout is skipped while paused.
enum BoneMacClock {
    nonisolated(unsafe) static var speed = 1.0
    nonisolated(unsafe) private(set) static var paused = false
    nonisolated(unsafe) private(set) static var skipped = 0
    nonisolated(unsafe) private static var held = NSHashTable<NSView>.weakObjects()
    nonisolated(unsafe) private static var hooked: Set<ObjectIdentifier> = []

    static func pause(_ windows: [NSWindow]) {
        for w in windows {
            guard let v = w.contentView else { continue }
            hook(type(of: v))
            held.add(v)
        }
        paused = true
    }

    static func resume() {
        paused = false
        for v in held.allObjects { v.needsLayout = true }    // a skipped layout is not asked for again
        held.removeAllObjects()
    }

    /// The hosting view class gets its own -layout, which calls the inherited one unless paused.
    private static func hook(_ cls: AnyClass) {
        let id = ObjectIdentifier(cls)
        let sel = #selector(NSView.layout)
        guard !hooked.contains(id), let m = class_getInstanceMethod(cls, sel) else { return }
        typealias Layout = @convention(c) (NSView, Selector) -> Void
        let original = unsafeBitCast(method_getImplementation(m), to: Layout.self)
        let block: @convention(block) (NSView) -> Void = { view in
            if paused, held.contains(view) { skipped += 1; return }
            original(view, sel)
        }
        let imp = imp_implementationWithBlock(block)
        if !class_addMethod(cls, sel, imp, method_getTypeEncoding(m)) { method_setImplementation(m, imp) }
        hooked.insert(id)
    }
}

struct BoneMacTake {
    var frames: [CGImage] = []
    var times: [Double] = []           // animation seconds from the first frame
    var count: Int { frames.count }
    var duration: Double { times.last ?? 0 }
}

final class BoneMacTimeline: ObservableObject {

    static let maxFrames = 240               // 4 s of animation

    @Published var speed = 1.0 { didSet { BoneMacClock.speed = speed } }
    @Published private(set) var paused = false
    @Published private(set) var take: BoneMacTake?
    @Published var frameIndex = 0
    @Published private(set) var armed = false
    @Published private(set) var recording = false
    @Published var status = ""

    weak var model: BoneGlassPanelModel?
    private var generation = 0
    private var windows: [NSWindow] { model?.appWindows ?? [] }

    var frameImage: NSImage? {
        guard let take, take.frames.indices.contains(frameIndex) else { return nil }
        let f = take.frames[frameIndex]
        return NSImage(cgImage: f, size: windows.first?.frame.size ?? CGSize(width: f.width, height: f.height))
    }
    var frameTime: Double { take.map { $0.times.indices.contains(frameIndex) ? $0.times[frameIndex] : 0 } ?? 0 }
    var progress: Double { guard let take, take.count > 1 else { return 0 }; return Double(frameIndex) / Double(take.count - 1) }

    func open() { status = "" }

    func close() {
        generation &+= 1
        armed = false
        recording = false
        take = nil
        if paused { togglePause() }
        speed = 1
        status = ""
    }

    func nextSpeed() {
        let i = BoneTimelineKit.speeds.firstIndex { $0.value == speed } ?? 0
        speed = BoneTimelineKit.speeds[(i + 1) % BoneTimelineKit.speeds.count].value
    }

    func togglePause() {
        take = nil
        if BoneMacClock.paused { BoneMacClock.resume() } else { BoneMacClock.pause(windows) }
        paused = BoneMacClock.paused
    }

    func leaveTake() { take = nil; status = "" }

    // MARK: Take

    /// Arms: the next change of the app window starts the take, which ends once it settles.
    func record() {
        guard !armed, !recording, let window = windows.first else { return }
        take = nil
        if paused { togglePause() }
        generation &+= 1
        let id = generation
        armed = true
        model?.panel?.sharingType = .none
        status = speed >= 0.5 ? "trigger the animation · slow down (⅒, 1⁄20) for more frames" : "trigger the animation"
        Task { @MainActor in
            guard let source = await WindowSource(window) else {
                armed = false
                status = "no window to capture"
                return
            }
            guard let base = await source.capture() else {
                armed = false; model?.panel?.sharingType = .readOnly; status = "capture failed – Screen Recording allowed?"; return
            }
            // waiting: up to 30 s for the window to differ from the baseline (not from the last
            // capture – slowed down, two captures in a row barely differ)
            let baseline = BoneTimelineKit.thumbnail(base, divisor: 8)
            var previous = baseline
            let before = base
            let deadline = CACurrentMediaTime() + 30
            var first: CGImage?
            while generation == id, CACurrentMediaTime() < deadline {
                guard let shot = await source.capture() else { break }
                let t = BoneTimelineKit.thumbnail(shot, divisor: 8)
                if !BoneTimelineKit.same(t, baseline) { first = shot; previous = t; break }
            }
            armed = false
            if first == nil { model?.panel?.sharingType = .readOnly }
            guard generation == id, let first else { if generation == id { status = "nothing changed" }; return }
            recording = true
            status = "recording…"
            let speed = BoneMacClock.speed
            let start = CACurrentMediaTime()
            let wall0 = start - 1.0 / 60                 // frame 0 (before) sits one frame ahead of the first change
            var frames = [before, first]
            var times: [Double] = [0, (start - wall0) * speed]
            var still = 0
            let interval = (1.0 / 60) / speed                // one frame per 1/60 s of animation
            while generation == id, frames.count < Self.maxFrames {
                let due = start + Double(frames.count - 1) * interval
                if due > CACurrentMediaTime() { try? await Task.sleep(nanoseconds: UInt64((due - CACurrentMediaTime()) * 1e9)) }
                guard let shot = await source.capture() else { break }
                let now = CACurrentMediaTime()
                let t = BoneTimelineKit.thumbnail(shot, divisor: 8)
                still = BoneTimelineKit.same(t, previous) ? still + 1 : 0
                previous = t
                frames.append(shot)
                times.append((now - wall0) * speed)
                if still >= 10 && (now - start) * speed > 0.25 { break }   // settled
            }
            recording = false
            model?.panel?.sharingType = .readOnly
            guard generation == id else { return }
            if still > 0, frames.count - still > 2 {                   // keep the first settled frame
                frames.removeLast(still - 1)
                times.removeLast(still - 1)
            }
            take = BoneMacTake(frames: frames, times: times)
            frameIndex = 0
            status = "\(frames.count) frames · \(BoneTimelineKit.seconds(times.last ?? 0)) of animation · \(BoneTimelineKit.seconds(CACurrentMediaTime() - start)) wall"
        }
    }

    /// Contact sheet of up to 12 frames, evenly spaced → timeline-take.png
    func saveTake() {
        guard let take, !take.frames.isEmpty,
              let png = BoneTimelineKit.contactSheet(count: take.count, frame: { take.frames[$0] },
                                                     label: { "\($0) · \(BoneTimelineKit.seconds(take.times[$0]))" }) else { return }
        BoneCapture.writeData(png, fileName: "timeline-take.png")
        status = "saved \(BoneCapture.readableURL(for: "timeline-take.png").lastPathComponent)"
    }

    /// The app window's rect through ScreenCaptureKit's captureImage(in:) (it works where
    /// SCShareableContent's window list needs Screen Recording). The panel above the window is
    /// left out with sharingType = .none while the take runs.
    private struct WindowSource {
        let rect: CGRect
        init?(_ window: NSWindow) async {
            let f = window.frame                                            // bottom-left, global
            let mainHeight = NSScreen.screens.first?.frame.height ?? f.maxY
            rect = CGRect(x: f.minX, y: mainHeight - f.maxY, width: f.width, height: f.height)
        }
        func capture() async -> CGImage? { await BoneScreen.capture(in: rect) }
    }

}

// MARK: - Views

struct BoneMacTimelineScreen: View {
    @ObservedObject var model: BoneGlassPanelModel
    @ObservedObject var timeline: BoneMacTimeline

    var body: some View {
        ZStack {
            if let image = timeline.frameImage {
                Image(nsImage: image)
                    .resizable()
                    .ignoresSafeArea()
                    .contentShape(Rectangle())                   // a take covers the app
            }
            BoneMacTimelineBar(model: model, timeline: timeline)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
        }
    }
}

struct BoneMacTimelineBar: View {
    @ObservedObject var model: BoneGlassPanelModel
    @ObservedObject var timeline: BoneMacTimeline

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                Button { timeline.togglePause() } label: {
                    Image(systemName: timeline.paused ? "play.fill" : "pause.fill")
                }
                Button { timeline.nextSpeed() } label: {
                    Text(BoneTimelineKit.label(timeline.speed))
                        .font(.headline.monospacedDigit())
                        .frame(minWidth: 44)
                }
                .buttonStyle(.bordered)
                Button { timeline.record() } label: {
                    Image(systemName: "record.circle").foregroundStyle(.red)
                }
                .disabled(timeline.armed || timeline.recording)
                Spacer(minLength: 0)
                Button { model.startPicking() } label: { Image(systemName: "drop.halffull") }
                    .tint(.pink)
                Button { model.closeTimeline() } label: { Image(systemName: "xmark.circle.fill") }
            }
            .font(.title3)

            VStack(spacing: 4) {
                if let take = timeline.take {
                    BoneTakeRow(count: take.count, frameIndex: $timeline.frameIndex,
                                caption: String(format: "%.2f", timeline.progress) + " · frame \(timeline.frameIndex)/\(take.count - 1) · \(BoneTimelineKit.seconds(timeline.frameTime))",
                                save: timeline.saveTake, live: timeline.leaveTake)
                } else {
                    HStack {
                        Text("\(timeline.recording ? "recording" : timeline.armed ? "armed" : timeline.paused ? "paused" : "live") · \(BoneTimelineKit.label(timeline.speed))")
                            .font(.caption.monospacedDigit())
                        Spacer()
                        Text(timeline.paused ? "the window holds its frame · ▶ jumps ahead"
                                             : "set the speed, then trigger the animation · ⏺ to scrub it")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
            }
            .frame(height: 52)
            Text(timeline.status.isEmpty ? " " : timeline.status)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .frame(maxWidth: 560)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { model.timelineRect = $0 }
        .onDisappear { model.timelineRect = .zero }
    }
}

#endif

#endif   // DEBUG
