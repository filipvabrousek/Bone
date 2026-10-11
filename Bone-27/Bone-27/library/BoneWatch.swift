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
                let keys = filterKeys(f)
                out += String(repeating: "  ", count: depth + 1) + "\(slot): \(type) – \(keys.count) inputs: "
                    + keys.joined(separator: ", ") + "\n"
            }
        }
        for sub in (get(layer, "sublayers") as? [NSObject]) ?? [] { out += layerTree(sub, depth + 1) }
        return out
    }

    /// A CAFilter's input keys: it has no API to list them, but archives them under "CAFilterInputs".
    static func filterKeys(_ filter: NSObject) -> [String] {
        guard filter.conforms(to: NSCoding.self),
              let data = try? NSKeyedArchiver.archivedData(withRootObject: filter, requiringSecureCoding: false),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let objects = plist["$objects"] as? [Any] else { return [] }
        func deref(_ v: Any?) -> Any? {
            guard let v else { return nil }
            let d = String(describing: v)
            guard d.contains("CFKeyedArchiverUID"), let r = d.range(of: "value = "),
                  let n = Int(d[r.upperBound...].prefix { $0.isNumber }), n < objects.count else { return v }
            return objects[n]
        }
        guard let root = objects.compactMap({ $0 as? [String: Any] }).first(where: { $0["CAFilterInputs"] != nil }),
              let box = deref(root["CAFilterInputs"]) as? [String: Any],
              let dict = (box["NS.keys"] != nil ? box : deref(box["dict"])) as? [String: Any],
              let keyRefs = dict["NS.keys"] as? [Any] else { return [] }
        return keyRefs.compactMap { deref($0) as? String }.sorted()
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

#endif
