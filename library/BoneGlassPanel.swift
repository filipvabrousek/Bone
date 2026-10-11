//
//  BoneGlassPanel.swift
//  Bone-27
//
//  A live editor for Liquid Glass. Add it once, to the app's root view:
//
//      WindowGroup { ContentView().glassPanel() }
//
//  Tap the floating drop button, then tap any glass on screen – your own
//  .glassEffect() views and system bars alike. Every input of its filters gets
//  a control (slider, toggle, colour, size, 4×5 colour matrix), including the
//  hidden ones SwiftUI never sets (purple). Changes go straight to the real
//  glass and are re-applied when SwiftUI rebuilds it.
//
//  Layer mode  (switch in the pick hint): tap ANY element and edit its CALayer –
//              see BoneLayerPanel.swift / .tuneLayers.
//  Probe       runs .probeGlass on the picked glass; inputs it finds live are added.
//  Copy Swift  .tune([...]) code for the current changes, on the clipboard.
//  Save JSON   captures/glass-panel.json – load it with .tune(file: "glass-panel.json"),
//              which in the simulator re-reads the file whenever you edit it.
//
//  This file: the modifiers and the overlay window on each platform. The
//  model is BoneGlassPanelModel.swift, the views BoneGlassPanelViews.swift.
//
//  Research / simulator use only — private API, never ship it.
//

#if DEBUG   // Bone is private API: it compiles to nothing outside Debug builds

#if (canImport(UIKit) && !os(watchOS)) || os(macOS)

import Combine
import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

extension View {

    /// Adds the Liquid Glass panel: a floating button that edits any glass on screen.
    public func glassPanel() -> some View {
        #if os(macOS)
        // the timeline's speed: animations started in here run slower (BoneMacTimeline.swift)
        background(BoneGlassPanelAnchor())
            .transaction { t in
                if BoneMacClock.speed != 1, let a = t.animation { t.animation = a.speed(BoneMacClock.speed) }
            }
        #else
        background(BoneGlassPanelAnchor())
        #endif
    }

    /// The visual inspector: tap the drop, then tap text, glass or any element
    /// and adjust it with on-screen sliders. (Same as `.glassPanel()`.)
    public func boneInspector() -> some View {
        glassPanel()
    }
}

#if canImport(UIKit)
/// Finds the window scene and installs the panel's overlay window there.
struct BoneGlassPanelAnchor: UIViewRepresentable {
    func makeUIView(context: Context) -> BonePanelAnchorView { BonePanelAnchorView() }
    func updateUIView(_ view: BonePanelAnchorView, context: Context) {}
}

final class BonePanelAnchorView: UIView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        isUserInteractionEnabled = false
        if let scene = window?.windowScene { BoneGlassPanelModel.shared.install(on: scene) }
    }
}

/// Overlay window above the app. Lets every touch through except on the panel
/// itself (or everywhere while picking). SwiftUI ignores taps in a window that
/// is not key, so the panel becomes key when it is touched and gives key back
/// on Cancel / close.
final class BonePanelWindow: UIWindow {
    weak var model: BoneGlassPanelModel?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let m = model, m.takesPoint(point) else { return nil }
        if !isKeyWindow {
            m.rememberKeyWindow()
            makeKey()
        }
        return super.hitTest(point, with: event)
    }

    func hideForCapture(_ hidden: Bool) { isHidden = hidden }
}
#else
/// Finds the app window and attaches the panel's overlay window to it.
struct BoneGlassPanelAnchor: NSViewRepresentable {
    func makeNSView(context: Context) -> BonePanelAnchorView { BonePanelAnchorView() }
    func updateNSView(_ view: BonePanelAnchorView, context: Context) {}
}

final class BonePanelAnchorView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let w = window, !(w is BonePanelWindow) { BoneGlassPanelModel.shared.install(on: w) }
    }
}

/// A transparent child window exactly over the app window. AppKit has no per-point pass-through,
/// so a mouse monitor makes it ignore the mouse except over the drop button and the cards (and
/// everywhere while picking) – the same rule as the iOS window's hitTest.
final class BonePanelWindow: NSPanel {
    weak var model: BoneGlassPanelModel?
    private var monitor: Any?

    init(over app: NSWindow) {
        super.init(contentRect: app.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = app.level
        ignoresMouseEvents = true
        acceptsMouseMovedEvents = true
        app.acceptsMouseMovedEvents = true
        app.addChildWindow(self, ordered: .above)
        NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: app, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setFrame(app.frame, display: true) }
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .leftMouseDragged]) { [weak self] e in
            MainActor.assumeIsolated { self?.track(e) }
            return e
        }
    }

    override var canBecomeKey: Bool { true }

    /// The mouse in this window's points, top-left origin (SwiftUI's global space here).
    private func track(_ e: NSEvent) {
        guard let m = model else { return }
        let screen = e.window.map { $0.convertPoint(toScreen: e.locationInWindow) } ?? NSEvent.mouseLocation
        let p = convertPoint(fromScreen: screen)
        let takes = m.takesPoint(CGPoint(x: p.x, y: frame.height - p.y))
        if ignoresMouseEvents == takes { ignoresMouseEvents = !takes }
    }

    func hideForCapture(_ hidden: Bool) { alphaValue = hidden ? 0 : 1 }
}
#endif

#endif

#endif   // DEBUG
