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

// MARK: - Liquid Glass: .dumpGlass and .tune

extension View {

    /// Writes the glass filter inputs of the glass in this view (watchOS), like .dumpGlass on iOS.
    func dumpGlass(_ fileName: String, only: [GlassInput]? = nil, after delay: Double = 1.5) -> some View {
        modifier(BoneWatchAreaModifier { area in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                BoneWatch.write(BoneWatch.dumpGlass(in: area.frame, only: only), fileName)
            }
        })
    }

    /// Overrides Liquid Glass filter inputs of the glass in this view (watchOS), like .tune on iOS.
    func tune(_ tuning: GlassTuning, log: String? = nil) -> some View {
        modifier(BoneWatchAreaModifier { area in
            let tuner = BoneWatchTuner(values: tuning.caValues, log: log, area: area)
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
        .onDisappear { (area.keepAlive as? BoneWatchTuner)?.stop() }
    }
}

final class BoneWatchTuner {
    let values: [String: Any]
    let log: String?
    let area: BoneWatchArea
    private var timer: Timer?
    private var logged = false

    init(values: [String: Any], log: String?, area: BoneWatchArea) {
        self.values = values
        self.log = log
        self.area = area
    }

    func start() {
        guard !values.isEmpty else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.125, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func tick() {
        var changes: [String] = []
        for found in BoneWatch.filterLayers(in: area.frame) {
            for (slot, _, name, type) in BoneWatch.filters(on: found.layer) {
                for (key, newValue) in values {
                    guard let input = Self.input(key, name: name, type: type) else { continue }
                    let path = "\(slot).\(name).\(input)"
                    let current = found.layer.value(forKeyPath: path)
                    if let current, BoneWatch.same(current, newValue) { continue }
                    found.layer.setValue(newValue, forKeyPath: path)
                    changes.append("\(BoneWatch.className(found.layer)) \(path): \(current.map { BoneGlassFormat.value($0) } ?? "nil") → \(BoneGlassFormat.value(newValue))")
                }
            }
        }
        if let log, !logged, !changes.isEmpty {
            logged = true
            let os = ProcessInfo().operatingSystemVersion
            let text = "BONE · tune\nOS: watchOS \(os.majorVersion).\(os.minorVersion)\n"
                + "requested: \(values.keys.sorted().map { "\($0)=\(BoneGlassFormat.value(values[$0]))" }.joined(separator: ", "))\n\n"
                + changes.joined(separator: "\n") + "\n"
            BoneWatch.write(text, log)
        }
    }

    /// "inputBlurRadius" → every glass filter; "vibrantColorMatrix.inputColorMatrix" → that filter only.
    static func input(_ key: String, name: String, type: String) -> String? {
        if let dot = key.firstIndex(of: ".") {
            let target = key[..<dot]
            return target == name || target == type ? String(key[key.index(after: dot)...]) : nil
        }
        return type.lowercased().contains("glass") ? key : nil
    }
}

extension BoneWatch {

    /// Layers carrying filters whose window frame centre lies in `area` (any, if `area` is null),
    /// with a path like the iOS dump ("UIWindowLayer ▹ [0]CALayer ▹ …").
    static func filterLayers(in area: CGRect) -> [(layer: NSObject, path: String)] {
        var notes: [String] = []
        var out: [(NSObject, String)] = []
        for w in findWindows(&notes) {
            guard let root = get(w, "layer") else { continue }
            func walk(_ layer: NSObject, _ path: String, _ depth: Int) {
                guard depth < 60 else { return }
                if !filters(on: layer).isEmpty {
                    let r = windowRect(layer, root: root)
                    if area.isNull || area.insetBy(dx: -8, dy: -8).contains(CGPoint(x: r.midX, y: r.midY)) {
                        out.append((layer, path))
                    }
                }
                for (i, sub) in ((get(layer, "sublayers") as? [NSObject]) ?? []).enumerated() {
                    walk(sub, "\(path) ▹ [\(i)]\(className(sub))", depth + 1)
                }
            }
            walk(root, className(root), 0)
        }
        return out
    }

    /// (slot, filter, name, type) for every filter on a layer.
    static func filters(on layer: NSObject) -> [(String, NSObject, String, String)] {
        var out: [(String, NSObject, String, String)] = []
        for slot in ["filters", "backgroundFilters"] {
            for f in (get(layer, slot) as? [NSObject]) ?? [] {
                let type = (get(f, "type") as? String) ?? className(f)
                out.append((slot, f, (get(f, "name") as? String) ?? type, type))
            }
        }
        return out
    }

    /// The layer's bounds in its window, through CALayer's own -convertRect:toLayer:.
    static func windowRect(_ layer: NSObject, root: NSObject) -> CGRect {
        typealias Convert = @convention(c) (NSObject, Selector, CGRect, NSObject?) -> CGRect
        let sel = NSSelectorFromString("convertRect:toLayer:")
        guard let cls = object_getClass(layer), let m = class_getInstanceMethod(cls, sel),
              let v = get(layer, "bounds") as? NSValue, String(cString: v.objCType).hasPrefix("{CGRect") else { return .null }
        var bounds = CGRect.zero
        v.getValue(&bounds, size: MemoryLayout<CGRect>.size)
        return unsafeBitCast(method_getImplementation(m), to: Convert.self)(layer, sel, bounds, root)
    }

    /// The .dumpGlass report, in the iOS format.
    static func dumpGlass(in area: CGRect, only: [GlassInput]?) -> String {
        struct Found { var path: String; var slot: String; var type: String; var isGlass: Bool; var inputs: [(String, Any?)] }
        var found: [Found] = []
        for (layer, path) in filterLayers(in: area) {
            for (slot, f, _, type) in filters(on: layer) {
                found.append(Found(path: path, slot: slot, type: type, isGlass: type.lowercased().contains("glass"),
                                   inputs: BoneFilterInputs.keys(of: f).map { ($0, f.value(forKey: $0)) }))
            }
        }
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let os = ProcessInfo().operatingSystemVersion
        var t = "BONE · dumpGlass\nOS: watchOS \(os.majorVersion).\(os.minorVersion) · captured: \(df.string(from: Date()))\n"
        t += "inputs: " + (only.map { $0.map(\.caseName).joined(separator: ", ") } ?? "all") + "\n"
        let glass = found.filter(\.isGlass)
        t += "glass filters: \(glass.count)\n"
        if glass.isEmpty { t += "\n(no glass filter found – is a glass style applied, and has it rendered?)\n" }
        let wanted = only.map { Set($0.map(\.rawValue)) }
        func label(_ key: String) -> String { GlassInput(rawValue: key).map { "\($0.caseName)  (\(key))" } ?? key }
        for (i, f) in found.enumerated() where f.isGlass || wanted == nil {
            t += "\n===== [\(i)] \(f.type)  (\(f.slot) on \(f.path)) =====\n"
            let rows = f.inputs.filter { wanted == nil || wanted!.contains($0.0) }
            if rows.isEmpty { t += "   (none of the requested inputs)\n"; continue }
            let width = rows.map { label($0.0).count }.max() ?? 0
            for (key, value) in rows {
                let l = label(key)
                t += "   " + l + String(repeating: " ", count: width - l.count) + " = " + BoneGlassFormat.value(value) + "\n"
            }
        }
        return t
    }

    /// Whether a filter input already holds a value (numbers by value, colours with CFEqual).
    static func same(_ a: Any, _ b: Any) -> Bool {
        if let x = a as? NSNumber, let y = b as? NSNumber { return abs(x.doubleValue - y.doubleValue) < 1e-9 }
        if CFGetTypeID(a as CFTypeRef) == CGColor.typeID, CFGetTypeID(b as CFTypeRef) == CGColor.typeID {
            return CFEqual(a as CFTypeRef, b as CFTypeRef)
        }
        if let x = a as? NSObject, let y = b as? NSObject { return x.isEqual(y) }
        return false
    }
}

#endif
