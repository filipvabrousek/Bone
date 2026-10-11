//
//  BoneWatch.swift
//  Bone-27
//
//  .bone(into:) for watchOS – the UIKit view tree behind a SwiftUI view on
//  Apple Watch, in the same brief format as on iOS:
//
//      List { Text("Hello") }.bone(into: "watch.txt")
//
//  watchOS has no public UIKit: the SDK's headers mark UIView, UIWindow,
//  UIApplication and CALayer API_UNAVAILABLE(watchos). The watch runs the same
//  engine underneath, though – UIKit re-exports UIKitCore, which exports
//  UIView, UIWindow, UIApplication, UIScreen and UIGlassEffect; QuartzCore
//  exports CALayer, CABackdropLayer, CAFilter and the SDF layers; SwiftUI hosts
//  its views in _UIHostingView as on iOS. So everything here goes through the
//  Objective-C runtime: classes by name, -respondsToSelector: before every
//  key-value read (an unknown key would raise), ivar lists via class_copyIvarList.
//
//  Writes <name> (brief dump: class, superclass, layer, sublayers per view,
//  depth as leading "-") and <name minus extension>-layers.txt (the layer tree
//  with every filter's type and input keys – Liquid Glass shows up as
//  glassBackground) to Documents and, in the simulator, <project>/captures/.
//  The brief dump opens in .bone3DFrom(_:) on visionOS and diffs against iOS.
//
//  Liquid Glass on the watch has the iPhone's structure (SDFLayer → CABackdropLayer
//  with glassBackground, ~70 inputs), so .dumpGlass and .tune work here too, with
//  the same types (GlassInput, GlassTuning – BoneGlassTuning.swift):
//
//      Button("Glass") {}.buttonStyle(.glass).dumpGlass("watch-glass.txt")
//      Button("Glass") {}.buttonStyle(.glass).tune(.noShadow + [.blurRadius: 0])
//
//  They act on the glass inside the modified view's frame (a GeometryReader gives
//  it; each glass layer's frame comes from CALayer's own -convertRect:toLayer:).
//  .tune re-applies 8× a second – SwiftUI rebuilds the filter as on iOS.
//
//  Research / simulator use only — private API, never ship it.
//

#if os(watchOS)

import SwiftUI
import WatchKit
import ObjectiveC

extension View {

    /// Dumps the UIKit view tree behind this view (watchOS) to `into` and shows it as an overlay.
    func bone(into name: String, after delay: Double = 1.5) -> some View {
        modifier(BoneWatchModifier(name: name, delay: delay))
    }

    @available(*, deprecated, renamed: "bone(into:)")
    func wbone(name: String) -> some View { bone(into: name) }
}

struct BoneWatchModifier: ViewModifier {
    let name: String
    let delay: Double
    @State private var lines: [String] = []
    @State private var shown = true

    func body(content: Content) -> some View {
        content
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { lines = BoneWatch.dump(into: name) }
            }
            .overlay(alignment: .topTrailing) {
                if !lines.isEmpty {
                    VStack(alignment: .trailing, spacing: 2) {
                        Button { shown.toggle() } label: {
                            Image(systemName: shown ? "xmark.circle.fill" : "list.bullet.circle.fill")
                        }
                        .buttonStyle(.plain)
                        if shown {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 2) {
                                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                                        Text(line).font(.system(size: 9, design: .monospaced))
                                    }
                                }
                                .padding(4)
                            }
                            .background(.black.opacity(0.75))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
    }
}

enum BoneWatch {

    /// Brief dump + layer tree; returns the overlay lines (one per view).
    @discardableResult
    static func dump(into name: String) -> [String] {
        var notes: [String] = []
        let windows = findWindows(&notes)
        var brief = "", overlay: [String] = [], layerText = ""
        var count = 0
        func walkView(_ view: NSObject, _ depth: Int) {
            guard count < 3000, depth < 60 else { return }
            count += 1
            let type = className(view)
            brief += (depth > 0 ? String(repeating: "-", count: depth) + ">" : "") + type + ":"
            if let sup = class_getSuperclass(object_getClass(view)) { brief += "\n superclass: \(NSStringFromClass(sup)) \n" }
            if let layer = get(view, "layer") {
                brief += "\n layer: \(short(layer))"
                if let subs = get(layer, "sublayers") as? [NSObject], !subs.isEmpty {
                    brief += " \n sublayers: " + subs.map(short).joined(separator: " / ")
                }
            }
            brief += "\n\n"
            overlay.append(String(repeating: " ", count: min(depth, 12)) + type)
            for sub in (get(view, "subviews") as? [NSObject]) ?? [] { walkView(sub, depth + 1) }
        }
        for w in windows {
            walkView(w, 0)
            if let layer = get(w, "layer") { layerText += layerTree(layer, 0) }
        }

        let os = ProcessInfo().operatingSystemVersion
        brief += "-------------------------\nOS: watchOS:\(os.majorVersion)\n"
        let header = "BONE · watchOS \(os.majorVersion).\(os.minorVersion) · \(windows.count) window(s), \(count) views\n"
            + notes.map { "# " + $0 }.joined(separator: "\n") + "\n\n"
        write(brief, name)
        let base = (name as NSString).deletingPathExtension
        write(header + layerText, base + "-layers.txt")
        return overlay.isEmpty ? notes : overlay
    }

    // MARK: windows

    /// The app's windows, found through the runtime: UIApplication's windows, then its scenes'.
    static func findWindows(_ notes: inout [String]) -> [NSObject] {
        guard let appClass = NSClassFromString("UIApplication") as? NSObject.Type else {
            notes.append("no UIApplication class"); return []
        }
        let shared = NSSelectorFromString("sharedApplication")
        guard (appClass as AnyObject).responds(to: shared),
              let app = (appClass as AnyObject).perform(shared)?.takeUnretainedValue() as? NSObject else {
            notes.append("UIApplication.sharedApplication unavailable"); return []
        }
        notes.append("application: \(className(app))")
        var windows = (get(app, "windows") as? [NSObject]) ?? []
        if windows.isEmpty, let scenes = get(app, "connectedScenes") as? Set<NSObject> {
            for scene in scenes { windows += (get(scene, "windows") as? [NSObject]) ?? [] }
            notes.append("windows from \(scenes.count) scene(s)")
        }
        for w in windows {
            let root = get(w, "rootViewController").map(className) ?? "–"
            notes.append("window \(className(w)) · root \(root) · frame \(rect(get(w, "frame")))")
        }
        return windows
    }

    // MARK: layers

    /// Indented layer tree: class, frame, and every filter's type and input keys.
    static func layerTree(_ layer: NSObject, _ depth: Int) -> String {
        guard depth < 60 else { return "" }
        var out = String(repeating: "  ", count: depth) + className(layer) + " " + rect(get(layer, "frame"))
        if let delegate = get(layer, "delegate") { out += " delegate " + className(delegate) }
        out += "\n"
        for slot in ["filters", "backgroundFilters"] {
            for f in (get(layer, slot) as? [NSObject]) ?? [] {
                let type = (get(f, "type") as? String) ?? className(f)
                let keys = BoneFilterInputs.keys(of: f)
                out += String(repeating: "  ", count: depth + 1) + "\(slot): \(type) – \(keys.count) inputs: "
                    + keys.joined(separator: ", ") + "\n"
            }
        }
        for sub in (get(layer, "sublayers") as? [NSObject]) ?? [] { out += layerTree(sub, depth + 1) }
        return out
    }

    // MARK: runtime helpers

    /// -valueForKey: only when the object answers the getter (an unknown key raises).
    static func get(_ object: NSObject, _ key: String) -> NSObject? {
        guard object.responds(to: NSSelectorFromString(key)) else { return nil }
        return object.value(forKey: key) as? NSObject
    }

    static func className(_ object: NSObject) -> String {
        object_getClass(object).map { NSStringFromClass($0) } ?? "?"
    }

    /// "<CALayer: 0x…>" – the description up to the first ";", like the iOS dump.
    static func short(_ object: NSObject) -> String {
        let d = object.description
        if let semi = d.firstIndex(of: ";") { return String(d[..<semi]) + ">" }
        return d
    }

    /// An NSValue holding a CGRect, read without UIKit's NSValue additions.
    static func rect(_ value: NSObject?) -> String {
        guard let v = value as? NSValue, String(cString: v.objCType).hasPrefix("{CGRect") else { return "" }
        var r = CGRect.zero
        v.getValue(&r, size: MemoryLayout<CGRect>.size)
        return String(format: "(%.1f, %.1f, %.1f, %.1f)", r.minX, r.minY, r.width, r.height)
    }

    // MARK: files

    /// Documents and, in the simulator, <project>/captures/ (as BoneCapture does on iOS).
    static func write(_ text: String, _ fileName: String) {
        var urls = [FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(fileName)]
        #if targetEnvironment(simulator)
        let captures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("captures", isDirectory: true)
        try? FileManager.default.createDirectory(at: captures, withIntermediateDirectories: true)
        urls.append(captures.appendingPathComponent(fileName))
        #endif
        for url in urls {
            do { try text.write(to: url, atomically: true, encoding: .utf8); print("OUTPUT FILE: \(url.absoluteString)") }
            catch { print("BONE write failed (\(url.lastPathComponent)): \(error.localizedDescription)") }
        }
    }
}

// MARK: - Liquid Glass: .dumpGlass and .tune (engine: BoneGlassRuntime.swift)

extension View {

    /// Writes the glass filter inputs of the glass in this view (watchOS), like .dumpGlass on iOS.
    func dumpGlass(_ fileName: String, only: [GlassInput]? = nil, after delay: Double = 1.5) -> some View {
        modifier(BoneWatchAreaModifier { area in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                BoneWatch.write(BoneGlassRuntime.dumpGlass(BoneWatch.filterLayers(in: area.frame), only: only), fileName)
            }
        })
    }

    /// Overrides Liquid Glass filter inputs of the glass in this view (watchOS), like .tune on iOS.
    func tune(_ tuning: GlassTuning, log: String? = nil) -> some View {
        modifier(BoneWatchAreaModifier { area in
            let tuner = BoneGlassRuntimeTuner(values: tuning.caValues, log: log,
                                              collect: { [weak area] in BoneWatch.filterLayers(in: area?.frame ?? .null) },
                                              write: { BoneWatch.write($0, $1) })
            area.keepAlive = tuner
            tuner.start()
        })
    }
}

/// The modified view's frame in window coordinates, kept current by a GeometryReader.
final class BoneWatchArea {
    var frame: CGRect = .null
    var keepAlive: AnyObject?
}

struct BoneWatchAreaModifier: ViewModifier {
    let onStart: (BoneWatchArea) -> Void
    @State private var area = BoneWatchArea()
    @State private var started = false

    func body(content: Content) -> some View {
        content.background(GeometryReader { g in
            Color.clear
                .onAppear {
                    area.frame = g.frame(in: .global)
                    if !started { started = true; onStart(area) }
                }
                .onChange(of: g.frame(in: .global)) { _, f in area.frame = f }
        })
        .onDisappear { (area.keepAlive as? BoneGlassRuntimeTuner)?.stop() }
    }
}

extension BoneWatch {

    /// Layers carrying filters whose window frame centre lies in `area` (any, if `area` is null).
    static func filterLayers(in area: CGRect) -> [BoneGlassRuntime.Found] {
        var notes: [String] = []
        let roots = findWindows(&notes).compactMap { get($0, "layer") }
        return BoneGlassRuntime.filterLayers(roots: roots) { layer, root in
            guard !area.isNull else { return true }
            let r = BoneGlassRuntime.rect(of: layer, in: root)
            return area.insetBy(dx: -8, dy: -8).contains(CGPoint(x: r.midX, y: r.midY))
        }
    }
}

// MARK: - Layers: .dumpLayers

extension View {

    /// Writes the layers SwiftUI draws this view into (watchOS), in the iOS .dumpLayers format.
    /// (.tuneLayers is iOS and macOS only: CALayer and CATransform3D are unavailable on watchOS.)
    func dumpLayers(_ fileName: String, after delay: Double = 1.5) -> some View {
        modifier(BoneWatchAreaModifier { area in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                BoneWatch.write(BoneWatch.dumpLayers(in: area.frame), fileName)
            }
        })
    }
}

extension BoneWatch {

    /// The layers inside `area` (centre inside, not much larger), as subtrees under their top layers.
    static func dumpLayers(in area: CGRect) -> String {
        typealias R = BoneGlassRuntime
        var t = "BONE · dumpLayers\nOS: \(R.osLine)\n"
        t += "targets: .text = CGDrawingLayer · .shape = *ShapeLayer · .gradient = GradientLayer · .glass · leaf = no sublayers\n\n"
        var notes: [String] = []
        for w in findWindows(&notes) {
            guard let root = get(w, "layer") else { continue }
            func inside(_ l: NSObject) -> Bool {
                let r = R.rect(of: l, in: root)
                return r.width > 0 && r.height > 0 && area.insetBy(dx: -2, dy: -2).contains(CGPoint(x: r.midX, y: r.midY))
                    && r.width <= area.width * 1.25 + 4 && r.height <= area.height * 1.25 + 4
            }
            func line(_ l: NSObject, _ depth: Int) {
                let r = R.rect(of: l, in: root)
                let cls = className(l)
                let subs = (get(l, "sublayers") as? [NSObject]) ?? []
                var parts = [cls]
                if let d = get(l, "delegate") { parts.append("delegate=\(className(d))") }
                parts.append("\(Int(r.minX - area.minX)),\(Int(r.minY - area.minY)) \(Int(r.width))×\(Int(r.height))")
                if let o = get(l, "opacity") as? NSNumber, o.doubleValue < 1 { parts.append("opacity=\(o)") }
                if let h = get(l, "isHidden") as? NSNumber, h.boolValue { parts.append("hidden") }
                if let c = get(l, "cornerRadius") as? NSNumber, c.doubleValue > 0 { parts.append("cornerRadius=\(c)") }
                let fs = R.filters(on: l)
                if !fs.isEmpty { parts.append("filters=[\(fs.map(\.type).joined(separator: ", "))]") }
                var targets: [String] = []
                if cls.contains("CGDrawingLayer") { targets.append(".text") }
                if cls.contains("ShapeLayer") { targets.append(".shape") }
                if cls.contains("GradientLayer") { targets.append(".gradient") }
                if fs.contains(where: { $0.type.lowercased().contains("glass") }) { targets.append(".glass") }
                if subs.isEmpty, r.width > 0, r.height > 0 { targets.append(".leaves") }
                if !targets.isEmpty { parts.append("→ " + targets.joined(separator: " ")) }
                t += String(repeating: "  ", count: depth) + parts.joined(separator: "  ") + "\n"
                subs.forEach { line($0, depth + 1) }
            }
            func walk(_ l: NSObject, parentInside: Bool) {
                let me = inside(l)
                if me && !parentInside { line(l, 0); return }
                for sub in (get(l, "sublayers") as? [NSObject]) ?? [] { walk(sub, parentInside: me) }
            }
            walk(root, parentInside: false)
        }
        return t
    }
}

#endif
