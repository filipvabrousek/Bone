//
//  BoneTimeline.swift
//  Bone-27
//
//  Timeline bar in the inspector (.boneInspector → pick hint → Timeline):
//  pause, slow down and step the app's animations – the Liquid Glass morphs
//  included – and scrub through a recorded take.
//
//  Live: ⏸ freezes everything (the glass stays live: tap the drop to inspect
//  or tune it mid-morph, or open 3D), ⏭ advances one 60 Hz frame, and the
//  speed button slows the clock down to 1/20. A spring only runs forward, so
//  scrubbing is over a take: ⏺ steps the animation one frame at a time and
//  captures the screen after each step (the panel hidden) until it settles;
//  the slider then scrubs the take both ways (frames decoded at 2× off the
//  main thread, the whole take pre-decoded). Save writes a contact sheet.
//
//  The clock: BoneAnimationClock.swift. Research / simulator use only.
//

#if canImport(UIKit) && !os(visionOS)

import SwiftUI
import UIKit
import Combine

extension View {

    /// The inspector with its timeline bar already open: pause, slow down, step and
    /// record the app's animations – the Liquid Glass morphs included.
    ///
    ///     Menu { … } label: { … }
    ///         .buttonStyle(.glass)
    ///         .morphTimeline()              // or .morphTimeline(speed: 0.1)
    ///
    /// Pause, tap the menu, then step or record. The pink drop in the bar inspects
    /// the frozen glass; × closes the bar (back to the inspector's drop).
    func morphTimeline(speed: Double = 1) -> some View {
        background(BoneTimelineAnchor(speed: speed, scrubber: false, trigger: false))
    }

    /// No steps at all: shortly after launch the modified control's primary action runs
    /// (a Menu opens), its morph is caught on its first frame, recorded to its end, and a
    /// 0.0–1.0 scrubber appears. With `trigger: false` it waits for a tap instead. "Again"
    /// waits for the next morph (tap outside: the menu closing); × goes back to normal.
    ///
    ///     Menu { … } label: { … }
    ///         .buttonStyle(.glass)
    ///         .morphScrubber()
    func morphScrubber(trigger: Bool = true) -> some View {
        background(BoneTimelineAnchor(speed: 1, scrubber: true, trigger: trigger))
    }
}

struct BoneTimelineAnchor: UIViewRepresentable {
    let speed: Double
    let scrubber: Bool
    let trigger: Bool
    var csv: String? = nil
    func makeUIView(context: Context) -> BoneTimelineAnchorView {
        BoneTimelineAnchorView(speed: speed, scrubber: scrubber, trigger: trigger, csv: csv)
    }
    func updateUIView(_ view: BoneTimelineAnchorView, context: Context) {}
}

final class BoneTimelineAnchorView: UIView {
    private let speed: Double
    private let scrubber: Bool
    private let trigger: Bool
    private let csv: String?
    private var opened = false

    init(speed: Double, scrubber: Bool, trigger: Bool, csv: String?) {
        self.speed = speed
        self.scrubber = scrubber
        self.trigger = trigger
        self.csv = csv
        super.init(frame: .zero)
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard !opened, let scene = window?.windowScene else { return }
        opened = true
        let model = BoneGlassPanelModel.shared
        model.install(on: scene)
        if !model.timelineOpen { model.openTimeline() }
        if speed != 1 { model.timeline.speed = speed }
        if let csv { model.timeline.csvFile = csv }
        if scrubber { model.timeline.startScrubber(autoTrigger: trigger) }
        if scrubber && trigger {
            // after the app's own launch animations (a glass button appearing is a morph too)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                guard let self, let window = self.window else { return }
                model.timeline.trigger(in: window, at: self.convert(CGPoint(x: self.bounds.midX, y: self.bounds.midY), to: window))
            }
        }
    }
}

/// Notices a finger coming down on an app window (not the panel) and changes nothing:
/// UIWindow.sendEvent is swizzled once. (A gesture recognizer on the window, even one that
/// fails at once, stopped a glass Menu from opening.)
enum BoneTouchWatch {
    private static var installed = false

    static func install() {
        guard !installed,
              let original = class_getInstanceMethod(UIWindow.self, #selector(UIWindow.sendEvent(_:))),
              let watcher = class_getInstanceMethod(UIWindow.self, #selector(UIWindow.bone_sendEvent(_:))) else { return }
        method_exchangeImplementations(original, watcher)
        installed = true
    }
}

extension UIWindow {
    @objc func bone_sendEvent(_ event: UIEvent) {
        if event.type == .touches, !(self is BonePanelWindow),
           event.allTouches?.contains(where: { $0.phase == .began }) == true {
            BoneTimeline.onAppTouch?()
        }
        bone_sendEvent(event)                      // the original (exchanged)
    }
}

/// A recorded take: one screen capture per animation frame.
struct BoneTake {
    var frames: [Data] = []        // JPEG (simulator: the screen can be read)
    var views: [UIView] = []       // snapshot views (device: screen pixels read back black)
    var step = 1.0 / 60            // animation seconds between frames
    var count: Int { max(frames.count, views.count) }
    var duration: Double { Double(max(count - 1, 0)) * step }
}

final class BoneTimeline: ObservableObject {

    static let speeds: [(label: String, value: Double)] = [("1×", 1), ("½", 0.5), ("¼", 0.25), ("⅒", 0.1), ("1⁄20", 0.05)]
    static let frameStep = 1.0 / 60
    static let maxFrames = 180               // 3 s of animation
    static let maxSnapshotFrames = 90        // snapshot views hold full-screen surfaces

    @Published var speed = 1.0 {
        didSet {
            clock.set(speed: speed)
            if !clock.isPaused { origin = clock.now; elapsed = 0 }   // slider counts from here
            sync()
        }
    }
    @Published private(set) var paused = false
    @Published private(set) var elapsed = 0.0         // animation seconds since ⏸
    @Published private(set) var take: BoneTake?
    @Published var frameIndex = 0 { didSet { if frameIndex != oldValue { showFrame() } } }
    @Published private(set) var frameImage: UIImage?
    @Published private(set) var frameView: UIView?
    /// A recorded frame is on screen (it covers the app).
    var showsFrame: Bool { frameImage != nil || frameView != nil }
    @Published private(set) var recording = false
    /// The bar is not drawn while the screen is captured. (Hiding the panel window instead
    /// costs it key status, and SwiftUI then drops the next touch – the first scrub.)
    @Published private(set) var capturing = false
    /// .morphScrubber(): armed for the next morph, recorded by itself, scrubber only.
    @Published private(set) var scrubberMode = false
    /// .dumpMorph(_:): each take also writes the morph's values, frame by frame, to this CSV.
    var csvFile: String?
    @Published private(set) var armed = false
    private var armGeneration = 0
    /// Set while .morphScrubber() waits: a touch on an app window calls it.
    nonisolated(unsafe) static var onAppTouch: (() -> Void)?
    @Published var status = ""

    weak var model: BoneGlassPanelModel?
    let clock = BoneAnimationClock.shared
    private var origin = 0.0
    private var timer: Timer?
    // take frames are JPEGs: decoded at display size off the main thread, newest request wins,
    // cached (and the whole take pre-decoded right after recording) so scrubbing keeps up
    private let cache = NSCache<NSNumber, UIImage>()
    private var decoding = false
    private var takeID = 0

    // MARK: Open / close

    func open() {
        if !clock.install() { status = clock.problem ?? "AnimationKit hook failed" }
        paused = clock.isPaused
        origin = clock.now
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    // MARK: Scrubber (.morphScrubber)

    func startScrubber(autoTrigger: Bool = false) {
        scrubberMode = true
        // a finger on the app arms the clock; animations nobody touched (a glass button
        // appearing at launch is a morph too) are left alone
        BoneTouchWatch.install()
        Self.onAppTouch = { [weak self] in self?.touched() }
        arm(capturingBefore: !autoTrigger)                 // auto: trigger(in:at:) captures it, right before
    }

    /// Waits for the next touch on the app; the morph it starts is recorded.
    func arm(capturingBefore: Bool = true) {
        setTake(nil)
        status = ""
        if clock.isPaused { clock.resume() }
        paused = false
        armed = true
        if capturingBefore { Task { await captureBefore() } }
    }

    /// The screen before the morph – frame 0 of the take, 0.0 on the scrubber. (The first
    /// frame the clock catches is already a little way in: UIKit's first step, plus the
    /// frame a device needs to draw it.) The bar is hidden for it.
    private var before: (image: CGImage?, view: UIView?)?

    private func captureBefore() async {
        before = nil
        capturing = true
        try? await Task.sleep(nanoseconds: 60_000_000)          // the bar gone from the screen
        if let shot = BoneScreen.capture(), Self.mean(Self.thumbnail(shot)) > 0.5 {
            before = (shot, nil)
        } else if let screen = windows.first?.windowScene?.screen {
            before = (nil, screen.snapshotView(afterScreenUpdates: false))   // a device: pixels read back black
        }
        if !recording { capturing = false }
    }

    /// Runs the primary action of the control at `point` (a Menu: it opens), armed, so its
    /// morph is recorded without a touch.
    func trigger(in window: UIWindow, at point: CGPoint) {
        guard scrubberMode, armed, take == nil, !recording else { return }
        var view = window.hitTest(point, with: nil)
        while let v = view, !(v is UIControl) { view = v.superview }
        guard let control = view as? UIControl else { status = "no control under the modified view: tap it"; return }
        Task {
            await captureBefore()
            touched()
            control.performPrimaryAction()
        }
    }

    /// A finger came down on the app: the next animation that registers within ~2 s is taken.
    private func touched() {
        guard scrubberMode, armed, take == nil, !recording else { return }
        armGeneration &+= 1
        let generation = armGeneration
        clock.arm { [weak self] in
            MainActor.assumeIsolated { self?.triggered() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.armGeneration == generation, self.armed else { return }
            self.clock.disarm()                    // nothing started: wait for the next touch
        }
    }

    /// The clock paused on the first frame of something new. A morph → record it;
    /// anything else (a button's press bulge) → let it go and stay armed.
    private func triggered() {
        armed = false
        paused = true
        origin = clock.now
        elapsed = 0
        Task { @MainActor in
            // A tap's touch-down starts the press bulge; the morph only starts on touch-up.
            // Stay paused a little (the press frozen) so the morph is caught on its first frame.
            for _ in 0..<36 {
                if morphLayerCount() > 0 { record(); return }
                try? await Task.sleep(nanoseconds: 17_000_000)
            }
            clock.resume()
            paused = false
            if scrubberMode, take == nil, !recording { arm() }
        }
    }

    func close() {
        clock.disarm()
        armed = false
        scrubberMode = false
        Self.onAppTouch = nil
        timer?.invalidate()
        timer = nil
        setTake(nil)
        paused = false
        speed = 1
        clock.reset(windows: windows)
        status = ""
    }

    /// Also scale Core Animation time (plain CAAnimations: UIView.animate, fades).
    /// Off by default: the glass morphs and their content fades all run on AnimationKit's
    /// clock, and slowing the window layer time down makes UIKit finish a morph at once.
    var scalesLayerTime = false

    private var windows: [UIWindow] { model?.appWindows ?? [] }

    private func sync() { if scalesLayerTime { clock.syncLayerTime(of: windows) } }

    private func refresh() {
        guard !recording else { return }
        // the slider counts while paused or slowed down; at 1× it would just run off
        if take == nil, clock.isPaused || speed < 1 { elapsed = max(0, clock.now - origin) }
        sync()                                        // windows that appeared since (menus, sheets)
    }

    // MARK: Live

    func nextSpeed() {
        let i = Self.speeds.firstIndex { $0.value == speed } ?? 0
        speed = Self.speeds[(i + 1) % Self.speeds.count].value
    }

    func togglePause() {
        setTake(nil)
        if clock.isPaused {
            clock.resume()
            origin = clock.now - elapsed
        } else {
            clock.pause()
            origin = clock.now
            elapsed = 0
        }
        paused = clock.isPaused
        sync()
    }

    func stepFrame() {
        setTake(nil)
        if !clock.isPaused { clock.pause(); paused = true; origin = clock.now }
        clock.step(Self.frameStep)
        sync()
        refresh()
    }

    // MARK: Take

    /// Steps the animation frame by frame, capturing the screen after each step,
    /// until it has not changed for 12 frames (or `maxFrames`).
    func record() {
        guard !recording else { return }
        setTake(nil)
        if !clock.isPaused { clock.pause(); paused = true; origin = clock.now; elapsed = 0 }
        sync()
        recording = true
        status = "recording…"
        capturing = true
        let started = CACurrentMediaTime()
        Task { @MainActor in
            var shots: [CGImage] = []
            var views: [UIView] = []
            var values: [BoneMorphFrame] = []                      // .dumpMorph: one per frame, trimmed with them
            var layerNames: [ObjectIdentifier: String] = [:]
            var log = "record: \(UIDevice.current.model) iOS \(UIDevice.current.systemVersion)\nbefore:\n" + clock.diagnostics
            var still = 0
            var previous: [UInt8]?
            try? await Task.sleep(nanoseconds: 120_000_000)        // panel gone from the screen
            // On a device the screen reads back black: keep system snapshot views instead
            // (render-server copies – glass included, shown instantly, but no pixels to save).
            let readable = BoneScreen.capture().map { Self.mean(Self.thumbnail($0)) > 0.5 } ?? false
            // one take = one morph: it ends when UIKit removes the morph's own layers
            let morph = morphLayerCount() > 0
            clock.setAutoStep(false)
            log += "screen readable: \(readable) · morph running: \(morph) · frame before: \(before != nil)\n"
            if let b = before {                                   // frame 0: the screen before the morph
                if readable, let image = b.image { shots.append(image) }
                if !readable, let view = b.view { views.append(view) }
                let added = readable ? b.image != nil : b.view != nil
                if csvFile != nil && added { values.append(BoneMorphFrame()) }   // no morph layers yet: no values
                before = nil
            }
            for i in 0..<(readable ? Self.maxFrames : Self.maxSnapshotFrames) {
                let thumb: [UInt8]
                if readable {
                    guard let (shot, t) = await settledCapture() else { log += "frame \(i): capture failed\n"; break }
                    shots.append(shot)
                    thumb = t
                } else {
                    try? await Task.sleep(nanoseconds: 50_000_000)    // the tick, the commit, the render
                    guard let screen = windows.first?.windowScene?.screen else { break }
                    views.append(screen.snapshotView(afterScreenUpdates: false))
                    thumb = drawnThumbnail()                          // no glass, but enough to see it settle
                }
                if csvFile != nil { values.append(BoneMorphValues.sample(windows, names: &layerNames)) }
                let stillBefore = still
                if let p = previous, Self.same(p, thumb) { still += 1 } else { still = 0 }
                let morphLayers = morphLayerCount()
                log += String(format: "frame %d: mean %.1f still %d morph layers %d clock %.4f ticks %d\n", i, Self.mean(thumb), still,
                              morphLayers, clock.now, clock.tickCount)
                previous = thumb
                if morph && morphLayers == 0 {
                    // the morph finished. UIKit keeps its layers a while after the last movement, then
                    // swaps in the real menu (a slightly different last frame): drop the still run before it
                    let n = readable ? shots.count : views.count
                    let run = still > 0 ? still : stillBefore
                    let cut = (n - 1 - run)..<(n - 1)
                    if run > 0, cut.lowerBound > 0 {
                        if readable { shots.removeSubrange(cut) } else { views.removeSubrange(cut) }
                        if values.count == n { values.removeSubrange(cut) }
                    }
                    break
                }
                if !morph && still >= 12 && i > 12 {                  // anything else: settled, keep one still frame
                    if readable { shots.removeLast(still) } else { views.removeLast(still) }
                    if values.count > still { values.removeLast(still) }
                    break
                }
                clock.step(Self.frameStep)
                sync()
            }
            capturing = false
            clock.setAutoStep(true)
            var csvNote = ""
            if let file = csvFile, !values.isEmpty {
                BoneCapture.writeData(Data(BoneMorphValues.csv(values, step: Self.frameStep).utf8), fileName: file)
                let rows = values.reduce(0) { $0 + $1.values.count }
                csvNote = " · \(rows) values → \(file)"
            }
            log += "after:\n" + clock.diagnostics
            BoneCapture.writeData(Data(log.utf8), fileName: "timeline-diag.txt")
            status = "encoding \(shots.count) frames…"
            // JPEG off the main thread (raw frames would be ~12 MB each at 3×)
            let frames: [Data] = await Task.detached(priority: .userInitiated) {
                shots.compactMap { UIImage(cgImage: $0).jpegData(compressionQuality: 0.8) }
            }.value
            recording = false
            elapsed = clock.now - origin
            guard !frames.isEmpty || !views.isEmpty else { status = "nothing captured"; return }
            setTake(BoneTake(frames: frames, views: views, step: Self.frameStep))
            var wlog = "windows after the take:\n"
            for w in (model?.panel?.windowScene?.windows ?? []) {
                wlog += "  \(type(of: w)) level \(w.windowLevel.rawValue) hidden \(w.isHidden) key \(w.isKeyWindow) alpha \(w.alpha)\n"
            }
            wlog += "  bar rect \(model?.timelineRect ?? .zero) · frameView \(frameView.map { "\(type(of: $0))" } ?? "nil")\n"
            BoneCapture.writeData(Data((log + wlog).utf8), fileName: "timeline-diag.txt")
            status = "\(take!.count) frames · \(Self.seconds(take!.duration)) · recorded in \(String(format: "%.1f s", CACurrentMediaTime() - started))" + csvNote
        }
    }

    /// After a step: let the tick, the commit and the render server catch up, then take
    /// the first capture that a second one agrees with.
    private func settledCapture() async -> (CGImage, [UInt8])? {
        try? await Task.sleep(nanoseconds: 34_000_000)                 // two frames: the tick, then the render
        guard var last = BoneScreen.capture() else { return nil }
        var lastThumb = Self.thumbnail(last)
        for _ in 0..<6 {
            try? await Task.sleep(nanoseconds: 17_000_000)
            guard let next = BoneScreen.capture() else { return (last, lastThumb) }
            let t = Self.thumbnail(next)
            if Self.same(t, lastThumb) { return (next, t) }
            last = next
            lastThumb = t
        }
        return (last, lastThumb)
    }

    func leaveTake() {
        setTake(nil)
        status = ""
    }

    var frameTime: Double { Double(frameIndex) * (take?.step ?? Self.frameStep) }
    /// 0 = first frame of the take, 1 = its last (a morph: fully done).
    var progress: Double { guard let take, take.count > 1 else { return 0 }; return Double(frameIndex) / Double(take.count - 1) }

    private func setTake(_ t: BoneTake?) {
        takeID &+= 1
        cache.removeAllObjects()
        cache.totalCostLimit = 400 << 20
        take = t
        frameImage = nil
        frameView = nil
        frameIndex = 0
        guard let t else { showInTakeWindow(nil); return }
        showFrame()
        guard t.views.isEmpty else { return }
        // pre-decode the whole take in the background
        let id = takeID, size = displaySize, frames = t.frames
        DispatchQueue.global(qos: .utility).async { [weak self] in
            for (i, data) in frames.enumerated() {
                guard let img = Self.decode(data, size) else { continue }
                DispatchQueue.main.async {
                    guard let self, self.takeID == id else { return }
                    self.cache.setObject(img, forKey: i as NSNumber, cost: Self.cost(img))
                }
            }
        }
    }

    /// Shows `frameIndex`: from the cache, else decoded off the main thread – one decode
    /// at a time, and when it lands the newest index is shown (or decoded next).
    private func showFrame() {
        if let take, !take.views.isEmpty {
            frameView = take.views.indices.contains(frameIndex) ? take.views[frameIndex] : nil
            showInTakeWindow(frameView)
            return
        }
        showInTakeWindow(nil)
        guard let take, take.frames.indices.contains(frameIndex) else { frameImage = nil; return }
        if let img = cache.object(forKey: frameIndex as NSNumber) { frameImage = img; return }
        guard !decoding else { return }
        decoding = true
        let i = frameIndex, id = takeID, data = take.frames[i], size = displaySize
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            let img = Self.decode(data, size)
            DispatchQueue.main.async {
                guard let self else { return }
                self.decoding = false
                guard self.takeID == id else { return }
                if let img { self.cache.setObject(img, forKey: i as NSNumber, cost: Self.cost(img)) }
                if self.frameIndex == i { self.frameImage = img } else { self.showFrame() }
            }
        }
    }

    /// Snapshot views (device takes) are shown in a window of their own just below the
    /// panel: inside the panel's SwiftUI tree the render server drew them over the bar.
    private var takeWindow: UIWindow?

    private func showInTakeWindow(_ view: UIView?) {
        guard let view else { takeWindow?.isHidden = true; return }
        if takeWindow == nil, let scene = model?.panel?.windowScene {
            let w = UIWindow(windowScene: scene)
            w.windowLevel = UIWindow.Level(rawValue: (model?.panel?.windowLevel.rawValue ?? UIWindow.Level.alert.rawValue) - 1)
            w.isUserInteractionEnabled = false
            w.backgroundColor = .black
            takeWindow = w
        }
        guard let w = takeWindow else { return }
        if view.superview !== w {
            w.subviews.forEach { $0.removeFromSuperview() }
            view.frame = w.bounds
            w.addSubview(view)
        }
        w.isHidden = false
    }

    /// Screen size in pixels at 2× – sharp enough, a quarter of a 3× decode.
    private var displaySize: CGSize {
        let b = model?.appWindows.first?.bounds.size ?? CGSize(width: 402, height: 874)
        return CGSize(width: b.width * 2, height: b.height * 2)
    }

    nonisolated private static func decode(_ data: Data, _ size: CGSize) -> UIImage? {
        UIImage(data: data)?.preparingThumbnail(of: size)
    }

    nonisolated private static func cost(_ img: UIImage) -> Int {
        Int(img.size.width * img.scale * img.size.height * img.scale * 4)
    }

    /// Contact sheet of up to 12 frames, evenly spaced → timeline-take.png
    func saveTake() {
        guard let take else { return }
        guard !take.frames.isEmpty else { status = "Save needs the simulator: a device's screen pixels read back black"; return }
        let count = min(12, take.frames.count)
        let picks = (0..<count).map { k in count == 1 ? 0 : k * (take.count - 1) / (count - 1) }
        let images = picks.compactMap { UIImage(data: take.frames[$0]) }
        guard let first = images.first else { return }
        let cols = min(6, images.count), rows = (images.count + cols - 1) / cols
        let cell = CGSize(width: first.size.width / 3, height: first.size.height / 3)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let sheet = UIGraphicsImageRenderer(size: CGSize(width: cell.width * CGFloat(cols), height: (cell.height + 28) * CGFloat(rows)), format: format).image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: cell.width * CGFloat(cols), height: (cell.height + 28) * CGFloat(rows)))
            for (k, img) in images.enumerated() {
                let x = CGFloat(k % cols) * cell.width, y = CGFloat(k / cols) * (cell.height + 28)
                img.draw(in: CGRect(x: x, y: y + 28, width: cell.width, height: cell.height))
                let label = "\(picks[k]) · \(Self.seconds(Double(picks[k]) * take.step))" as NSString
                label.draw(at: CGPoint(x: x + 8, y: y + 4), withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: 18, weight: .semibold)])
            }
        }
        guard let png = sheet.pngData() else { return }
        BoneCapture.writeData(png, fileName: "timeline-take.png")
        status = "saved \(BoneCapture.readableURL(for: "timeline-take.png").lastPathComponent)"
    }

    // MARK: Helpers

    static func seconds(_ t: Double) -> String { String(format: "%.3f s", t) }

    static func label(_ speed: Double) -> String {
        speeds.first { $0.value == speed }?.label ?? String(format: "%g×", speed)
    }

    /// Layers of an AnimationKit morph in progress (they are removed when it completes).
    private func morphLayerCount() -> Int {
        var n = 0
        func walk(_ l: CALayer) {
            if String(describing: type(of: l)).contains("InProcessAnimatable") { n += 1 }
            l.sublayers?.forEach(walk)
        }
        windows.forEach { walk($0.layer) }
        return n
    }

    /// The app windows drawn small (drawHierarchy: no glass) – change detection on a device.
    private func drawnThumbnail() -> [UInt8] {
        guard let first = windows.first else { return [] }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0 / 6
        let image = UIGraphicsImageRenderer(bounds: first.bounds, format: format).image { _ in
            for w in windows where !w.isHidden { _ = w.drawHierarchy(in: w.frame, afterScreenUpdates: false) }
        }
        return image.cgImage.map(Self.thumbnail) ?? []
    }

    /// 1/6-size RGBA copy for change detection.
    private static func thumbnail(_ image: CGImage) -> [UInt8] {
        let w = max(1, image.width / 6), h = max(1, image.height / 6)
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

    private static func mean(_ a: [UInt8]) -> Double {
        guard !a.isEmpty else { return 0 }
        var sum = 0
        for i in stride(from: 0, to: a.count, by: 4) { sum += Int(a[i]) + Int(a[i + 1]) + Int(a[i + 2]) }
        return Double(sum) / Double(a.count / 4 * 3)
    }

    private static func same(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        guard a.count == b.count else { return false }
        for i in stride(from: 0, to: a.count, by: 4) where abs(Int(a[i]) - Int(b[i])) > 3
            || abs(Int(a[i + 1]) - Int(b[i + 1])) > 3 || abs(Int(a[i + 2]) - Int(b[i + 2])) > 3 { return false }
        return true
    }
}

// MARK: - Views

/// A slider drawn and dragged by SwiftUI alone. The system Slider is a Liquid Glass
/// control on iOS 26+: its thumb follows the finger with an AnimationKit spring, so it
/// freezes with everything else while the timeline holds the clock – every panel uses
/// this one instead.
struct BoneSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double?

    init(value: Binding<Double>, in range: ClosedRange<Double>, step: Double? = nil) {
        _value = value
        self.range = range
        self.step = step
    }

    var body: some View {
        GeometryReader { g in
            let knob: CGFloat = 24
            let span = max(range.upperBound - range.lowerBound, .ulpOfOne)
            let f = CGFloat(min(max((value - range.lowerBound) / span, 0), 1))
            let x = f * (g.size.width - knob)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.25)).frame(height: 5)
                Capsule().fill(Color.accentColor).frame(width: x + knob / 2, height: 5)
                Circle()
                    .fill(.white)
                    .frame(width: knob, height: knob)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    .offset(x: x)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { d in
                let t = min(max((d.location.x - knob / 2) / max(g.size.width - knob, 1), 0), 1)
                var v = range.lowerBound + Double(t) * span
                if let step, step > 0 { v = range.lowerBound + ((v - range.lowerBound) / step).rounded() * step }
                if v != value { value = v }
            })
        }
        .frame(height: 30)
    }
}

struct BoneTimelineScreen: View {
    @ObservedObject var model: BoneGlassPanelModel
    @ObservedObject var timeline: BoneTimeline

    var body: some View {
        ZStack {
            if timeline.capturing {
                Color.clear                                      // nothing of the panel in the captures
            } else {
            if timeline.frameView != nil {
                Color.black.opacity(0.001)                       // the take window shows it; this takes the touches
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
            } else if let image = timeline.frameImage {
                Image(uiImage: image)
                    .resizable()
                    .ignoresSafeArea()
                    .contentShape(Rectangle())          // a take covers the app
            }
            Group {
                if timeline.scrubberMode {
                    BoneScrubberBar(model: model, timeline: timeline)
                } else {
                    BoneTimelineBar(model: model, timeline: timeline)
                }
            }
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
            }
        }
    }
}

/// The bar of .morphScrubber(): waiting → (recording, nothing drawn) → 0.0–1.0 scrubber.
struct BoneScrubberBar: View {
    @ObservedObject var model: BoneGlassPanelModel
    @ObservedObject var timeline: BoneTimeline

    var body: some View {
        VStack(spacing: 6) {
            if let take = timeline.take {
                BoneSlider(value: Binding(get: { timeline.progress },
                                          set: { timeline.frameIndex = Int(($0 * Double(max(take.count - 1, 0))).rounded()) }),
                           in: 0...1)
                HStack {
                    Text(String(format: "%.2f", timeline.progress) + " · \(BoneTimeline.seconds(timeline.frameTime)) of \(BoneTimeline.seconds(take.duration))")
                        .font(.caption.monospacedDigit())
                    Spacer()
                    Button("Again") { timeline.arm() }
                        .font(.caption.bold())
                    Button { model.closeTimeline() } label: { Image(systemName: "xmark.circle.fill") }
                }
                if !timeline.status.isEmpty {
                    Text(timeline.status)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                HStack(spacing: 8) {
                    Circle().fill(timeline.armed ? Color.red : Color.orange).frame(width: 8, height: 8)
                    Text(timeline.recording ? "recording…" : timeline.armed ? "trigger the animation – it is recorded by itself" : "…")
                        .font(.caption)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer()
                    Button { model.closeTimeline() } label: { Image(systemName: "xmark.circle.fill") }
                }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { model.timelineRect = $0 }
        .onDisappear { model.timelineRect = .zero }
    }
}

struct BoneTimelineBar: View {
    @ObservedObject var model: BoneGlassPanelModel
    @ObservedObject var timeline: BoneTimeline

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                Button { timeline.togglePause() } label: {
                    Image(systemName: timeline.paused ? "play.fill" : "pause.fill")
                }
                Button { timeline.stepFrame() } label: { Image(systemName: "forward.frame.fill") }
                // a button, not a menu Picker: a UIKit menu is itself a glass morph, and one
                // still closing (slowed down) makes UIKit finish the next menu at once
                Button { timeline.nextSpeed() } label: {
                    Text(BoneTimeline.label(timeline.speed))
                        .font(.headline.monospacedDigit())
                        .frame(minWidth: 44)
                }
                .buttonStyle(.bordered)
                Button { timeline.record() } label: {
                    Image(systemName: "record.circle").foregroundStyle(.red)
                }
                .disabled(timeline.recording)
                Spacer(minLength: 0)
                Button { model.startPicking() } label: { Image(systemName: "drop.halffull") }
                    .tint(.pink)
                Button { model.closeTimeline() } label: { Image(systemName: "xmark.circle.fill") }
            }
            .font(.title3)

            VStack(spacing: 4) {                                        // (a Group would give each row the height)
            if let take = timeline.take {
                // 0.0 … 1.0 over the take: one morph, start to end
                BoneSlider(value: Binding(get: { timeline.progress },
                                          set: { timeline.frameIndex = Int(($0 * Double(max(take.count - 1, 0))).rounded()) }),
                           in: 0...1)
                HStack {
                    Text(String(format: "%.2f", timeline.progress) + " · frame \(timeline.frameIndex)/\(take.count - 1) · \(BoneTimeline.seconds(timeline.frameTime))")
                        .font(.caption.monospacedDigit())
                    Spacer()
                    Button("Save") { timeline.saveTake() }
                    Button("Live") { timeline.leaveTake() }
                }
                .font(.caption.bold())
            } else {
                // a spring only runs forward: scrubbing (both ways) is over a recorded take
                HStack {
                    Text("\(timeline.recording ? "recording" : timeline.paused ? "paused" : "live") · \(BoneTimeline.seconds(timeline.elapsed)) · \(BoneTimeline.label(timeline.speed))")
                        .font(.caption.monospacedDigit())
                    Spacer()
                    Text(timeline.paused ? "trigger the animation · step, or record it to scrub"
                                         : "pause first, then trigger the animation")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            }
            .frame(height: 64)                                          // same height live or with a take: the buttons don't jump
            Text(timeline.status.isEmpty ? " " : timeline.status)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { model.timelineRect = $0 }
        .onDisappear { model.timelineRect = .zero }
    }
}

#endif
