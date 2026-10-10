//
//  BoneAnimationClock.swift
//  Bone-27
//
//  One clock for the app's animations, so the Liquid Glass morphs can be
//  paused, slowed down and stepped frame by frame (the timeline bar in
//  .boneInspector uses it).
//
//  Two kinds of animation run a morph such as a glass button opening into a
//  menu:
//
//  • AnimationKit (private, iOS 26+): LiquidMorphAnimation and the other
//    in-process animations are advanced inside the app by
//    InProcessAnimationManager (more than one instance) from a display link,
//    -displayLinkFire:. Each tick advances by `deltaTime = timestamp − time`
//    (ivar `time`). The hook rewrites `time` before each tick, so the tick
//    advances by what this clock says: nothing while paused, exactly the step
//    when stepping, and when slowed down whole 60 Hz frames every few ticks
//    (stop-motion – see `frame`). These are not CAAnimations – layer.speed
//    does nothing to them.
//  • Core Animation (plain CAAnimations): window layer time, scaled with
//    layer.speed / timeOffset – opt-in (BoneTimeline.scalesLayerTime). The
//    menu morph and its content fade are all AnimationKit; slowing the window
//    layer time down as well makes UIKit finish the morph at once.
//
//  Research / simulator use only — private API, never ship it.
//

#if canImport(UIKit) && !os(visionOS)

import UIKit
import QuartzCore

nonisolated final class BoneAnimationClock: @unchecked Sendable {

    static let shared = BoneAnimationClock()

    /// Longest step one tick may take; a bigger step (fast-forward) is spread over
    /// several ticks so the springs integrate it in small pieces.
    static let maxTickStep = 1.0 / 30
    /// Slow motion is stop-motion: whole 60 Hz frames, every few ticks. Parts of a morph
    /// are smoothed per tick, not per second – fed a tiny step every tick they still run
    /// at close to full speed (1/20 came out about 5× slower), fed whole frames they are exact.
    static let frame = 1.0 / 60

    private let lock = NSLock()
    private var hooked = false
    private var hookError: String?
    private var timeOffset: Int?                         // byte offset of InProcessAnimationManager.time
    private var speed = 1.0
    private var paused = false
    private var frozen = 0.0                             // clock time when last paused / re-based
    private var since = CACurrentMediaTime()             // wall time `frozen` was taken at
    private var seen: [ObjectIdentifier: Double] = [:]   // clock time each manager has reached
    private var lastStamp: [ObjectIdentifier: CFTimeInterval] = [:]
    /// A longer pause between a manager's ticks means its display link was stopped (idle).
    static let idleGap = 0.1
    private var ticks = 0
    private var deltaOffset: Int?
    private var entryOffsets: [Int] = []                 // `entries`, `newlyAddedEntries` (Swift arrays)
    private var entryCounts: [ObjectIdentifier: Int] = [:]
    /// Frames the clock stepped by itself (a new animation while paused).
    private(set) var autoSteps = 0
    private var autoStepEnabled = true
    /// One automatic step per pause: a morph registers dozens of animations over its first
    /// frames, and stepping for each would run it forward by itself.
    private var autoStepAvailable = true
    private var armed = false
    private var onTrigger: (@Sendable () -> Void)?

    /// Armed: the clock runs normally until an animation registers, then pauses on that
    /// tick – before the animation has advanced – and calls `trigger` on the main thread.
    func arm(_ trigger: @escaping @Sendable () -> Void) {
        lock.lock(); armed = true; onTrigger = trigger; lock.unlock()
    }

    func disarm() { lock.lock(); armed = false; onTrigger = nil; lock.unlock() }

    var isArmed: Bool { lock.lock(); defer { lock.unlock() }; return armed }

    /// Off while a take is recorded: the take steps every frame itself, and animations the
    /// stepping starts must not add frames of their own.
    func setAutoStep(_ on: Bool) { lock.lock(); autoStepEnabled = on; lock.unlock() }
    private var lastDelta: [ObjectIdentifier: (asked: Double, applied: Double, main: Bool)] = [:]

    private init() {}

    // MARK: State

    /// Animation seconds since the clock was created (slowed, paused and stepped).
    var now: Double {
        lock.lock(); defer { lock.unlock() }
        return nowLocked()
    }

    var isPaused: Bool { lock.lock(); defer { lock.unlock() }; return paused }
    var currentSpeed: Double { lock.lock(); defer { lock.unlock() }; return speed }
    /// Ticks seen so far (0 = the hook has not run: nothing animated in-process yet).
    var tickCount: Int { lock.lock(); defer { lock.unlock() }; return ticks }
    /// Why the AnimationKit hook could not be installed (nil = installed or not tried).
    var problem: String? { lock.lock(); defer { lock.unlock() }; return hookError }
    /// True when the clock runs like the real one (nothing is altered).
    var isNeutral: Bool { lock.lock(); defer { lock.unlock() }; return !paused && speed == 1 }

    private func nowLocked() -> Double {
        paused ? frozen : frozen + (CACurrentMediaTime() - since) * speed
    }

    func set(speed s: Double) {
        lock.lock()
        frozen = nowLocked(); since = CACurrentMediaTime(); speed = max(0, s)
        lock.unlock()
    }

    func pause() {
        lock.lock()
        if !paused { frozen = nowLocked(); paused = true; autoStepAvailable = true }
        lock.unlock()
    }

    func resume() {
        lock.lock()
        if paused { since = CACurrentMediaTime(); paused = false }
        lock.unlock()
    }

    /// While paused: advance by `seconds` of animation time (spent over the next ticks).
    func step(_ seconds: Double) {
        lock.lock()
        if paused { frozen += max(0, seconds) }
        lock.unlock()
    }

    // MARK: AnimationKit hook

    /// Swizzles -[AnimationKit.InProcessAnimationManager displayLinkFire:] once.
    @discardableResult
    func install() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if hooked { return true }
        guard let cls = NSClassFromString("AnimationKit.InProcessAnimationManager") else {
            hookError = "AnimationKit.InProcessAnimationManager not found (needs iOS 26+)"; return false
        }
        guard let ivar = class_getInstanceVariable(cls, "time") else { hookError = "no `time` ivar"; return false }
        let sel = NSSelectorFromString("displayLinkFire:")
        guard let method = class_getInstanceMethod(cls, sel) else { hookError = "no -displayLinkFire:"; return false }
        timeOffset = ivar_getOffset(ivar)
        deltaOffset = class_getInstanceVariable(cls, "deltaTime").map { ivar_getOffset($0) }
        entryOffsets = ["entries", "newlyAddedEntries"].compactMap { (name: String) -> Int? in
            class_getInstanceVariable(cls, name).map { ivar_getOffset($0) }
        }
        typealias Fire = @convention(c) (AnyObject, Selector, AnyObject) -> Void
        let original = unsafeBitCast(method_getImplementation(method), to: Fire.self)
        let block: @convention(block) (AnyObject, AnyObject) -> Void = { [unowned self] manager, link in
            let asked = self.prepare(manager, link)
            original(manager, sel, link)
            self.note(manager, asked)
        }
        method_setImplementation(method, imp_implementationWithBlock(block))
        hooked = true
        hookError = nil
        return true
    }

    /// Runs on the animation thread before each tick: sets the manager's `time` so the
    /// tick advances by what this clock has moved since the manager's last tick.
    @discardableResult
    private func prepare(_ manager: AnyObject, _ link: AnyObject) -> Double {
        guard let link = link as? CADisplayLink, let offset = timeOffset else { return -1 }
        lock.lock(); defer { lock.unlock() }
        ticks &+= 1
        let id = ObjectIdentifier(manager)
        // A manager's display link stops while it has nothing to animate. When it ticks
        // again (or for the first time) there is nothing to catch up: catching up would run
        // the new animation fast. Waking up also means something new started.
        let woke = link.timestamp - (lastStamp[id] ?? -.infinity) > Self.idleGap
        lastStamp[id] = link.timestamp
        if woke { seen[id] = nowLocked() }
        let entries = entryCount(manager)
        let grew = entries > (entryCounts[id] ?? entries)
        entryCounts[id] = entries
        if armed, !paused, woke || grew {
            // armed: stop on this tick, before the new animation advanced – plus one frame,
            // because a device draws an animated value only from a tick that advances
            frozen = nowLocked() + Self.frame
            paused = true
            armed = false
            autoStepAvailable = true               // the morph may start a moment later (touch-up)
            if let trigger = onTrigger { DispatchQueue.main.async(execute: trigger) }
        } else if paused, autoStepEnabled, autoStepAvailable, woke || grew {
            // paused: the same one frame, once – a morph registers dozens of animations
            // over its first frames, and stepping for each would run it by itself
            frozen += Self.frame
            autoSteps += 1
            autoStepAvailable = false
        }
        let clock = nowLocked()
        let reached = seen[id] ?? clock
        if !paused && speed == 1 && abs(clock - reached) < 0.0005 {
            seen[id] = clock                                   // neutral: leave the tick alone
            return -1
        }
        let base = UnsafeMutableRawPointer(Unmanaged.passUnretained(manager).toOpaque())
        let previous = base.load(fromByteOffset: offset, as: Double.self)
        guard previous > 0 else { seen[id] = clock; return -1 }   // manager never ticked yet
        let target = !paused && speed < 1 ? (clock / Self.frame).rounded(.down) * Self.frame : clock
        let advance = min(max(0, target - reached), Self.maxTickStep)
        seen[id] = reached + advance
        base.storeBytes(of: link.timestamp - advance, toByteOffset: offset, as: Double.self)
        return advance
    }

    /// Animations registered with the manager: the counts of its two TickEntry arrays
    /// (a Swift array is one pointer to storage whose header holds the count at +16).
    private func entryCount(_ manager: AnyObject) -> Int {
        let base = UnsafeRawPointer(Unmanaged.passUnretained(manager).toOpaque())
        return entryOffsets.reduce(0) { sum, offset in
            guard let storage = base.load(fromByteOffset: offset, as: UnsafeRawPointer?.self) else { return sum }
            return sum + storage.load(fromByteOffset: 16, as: Int.self)
        }
    }

    /// After a tick: what the manager actually advanced by (diagnostics).
    private func note(_ manager: AnyObject, _ asked: Double) {
        guard let o = deltaOffset else { return }
        let applied = UnsafeRawPointer(Unmanaged.passUnretained(manager).toOpaque()).load(fromByteOffset: o, as: Double.self)
        lock.lock()
        lastDelta[ObjectIdentifier(manager)] = (asked, applied, Thread.isMainThread)
        lock.unlock()
    }

    /// State of the hook, for the timeline's diagnostics file.
    var diagnostics: String {
        lock.lock(); defer { lock.unlock() }
        var out = "hook: \(hooked ? "installed" : "NOT installed") \(hookError ?? "")\n"
        out += "ticks: \(ticks) · managers: \(seen.count) · paused: \(paused) · speed: \(speed) · clock: \(String(format: "%.4f", nowLocked())) · auto steps: \(autoSteps) · entries: \(entryCounts.values.map(String.init).joined(separator: "/"))\n"
        for (id, d) in lastDelta {
            out += String(format: "  manager %@ main=%d last asked=%.5f applied=%.5f\n",
                          String(UInt(bitPattern: id.hashValue) % 10000), d.main ? 1 : 0, d.asked, d.applied)
        }
        return out
    }

    // MARK: Core Animation time

    /// Scales the layer time of `windows` to match the clock (speed, pause, steps).
    /// Call it after every change; it is cheap when nothing changed.
    @MainActor
    func syncLayerTime(of windows: [UIWindow]) {
        let (s, p, t) = { lock.lock(); defer { lock.unlock() }; return (speed, paused, nowLocked()) }()
        for w in windows {
            let l = w.layer
            let mediaNow = CACurrentMediaTime()
            if !p && s == 1 {
                if l.speed != 1 || l.timeOffset != 0 || l.beginTime != 0 {
                    l.speed = 1; l.timeOffset = 0; l.beginTime = 0     // back to real time (running animations jump)
                }
                anchors[ObjectIdentifier(l)] = nil
                continue
            }
            // local time = clock time, re-anchored when the window is first seen
            let key = ObjectIdentifier(l)
            if anchors[key] == nil { anchors[key] = l.convertTime(mediaNow, from: nil) - t }
            let local = t + anchors[key]!
            l.beginTime = mediaNow
            l.timeOffset = local
            l.speed = p ? 0 : Float(s)
        }
    }

    @MainActor private var anchors: [ObjectIdentifier: CFTimeInterval] = [:]

    /// Back to real time everywhere.
    @MainActor
    func reset(windows: [UIWindow]) {
        set(speed: 1)
        resume()
        syncLayerTime(of: windows)
    }
}

#endif
