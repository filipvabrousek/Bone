//
//  BoneCapture.swift
//  Bone-27
//
//  Structured capture of SwiftUI internals on top of the existing .bone() walk:
//   1. UIKit private introspection selectors:
//        -_ivarDescription      -> all ivars incl. private SwiftUI host state
//        -recursiveDescription  -> the exact tree LLDB's `po view` prints
//        -_autolayoutTrace      -> layout-engine state / ambiguity
//   2. Swift reflection (Mirror) of the SwiftUI root value AND of the
//      _UIHostingView instance — Mirror sees Swift stored properties,
//      so this exposes the ViewGraph, renderer, preference bridges, etc.
//   3. A Codable node tree written next to the classic dump as
//      <name>_capture.json and <name>_capture.txt
//
//  Research / simulator use only. The private selectors in here are
//  DEBUG-introspection API — do not ship them in an App Store build.
//

import SwiftUI

#if canImport(UIKit) || canImport(AppKit)

#if canImport(UIKit)
import UIKit
typealias BonePlatformView = UIView
typealias BonePlatformViewController = UIViewController
#else
import AppKit
typealias BonePlatformView = NSView
typealias BonePlatformViewController = NSViewController
#endif

// MARK: - Codable node tree

struct BoneNode: Codable {
    var className: String
    var superclassChain: [String]
    var frame: [Double]               // x, y, w, h
    var layerClass: String?
    var sublayers: [String]
    var layerContents: String?
    var animationKeys: [String]
    var ivarDescription: String?
    var children: [BoneNode]
}

struct BoneDump: Codable {
    var os: String
    var capturedAt: String
    var swiftUIRootMirror: String     // Mirror of the SwiftUI value tree (ModifiedContent<...> chain)
    var hostingViewMirror: String     // Mirror of _UIHostingView -> viewGraph, renderer, ...
    var recursiveDescription: String?
    var autolayoutTrace: String?
    var tree: BoneNode
}

// MARK: - Capture engine

enum BoneCapture {

    /// Max chars of _ivarDescription stored per node (it can get huge).
    static var maxIvarLength = 20_000
    /// Max recursion depth for Mirror dumps.
    static var maxMirrorDepth = 7

    /// Master switches for the private-selector dumps. These are private
    /// debug methods and DO crash (EXC_BAD_ACCESS) on some class/OS
    /// combinations. When that happens the console shows the last
    /// "BONE introspecting ..." line — that's the culprit. Either add the
    /// class name to `ivarDenylist` or flip the corresponding switch off.
    static var captureIvarDescriptions = true
    static var captureRecursiveDescription = true
    static var captureAutolayoutTrace = true

    /// Class-name PREFIXES whose -_ivarDescription crashes (varies per OS
    /// release). Prefix matching, because generic Swift classes carry their
    /// type parameters in the mangled name (_TtGC7SwiftUI14_UIHostingViewG...
    /// differs for every root view type).
    /// The Mirror dump (hostingViewMirror) still covers skipped objects.
    static var ivarDenylist: Set<String> = {
        var list: Set<String> = []
        #if os(visionOS)
        // visionOS: -_ivarDescription on SwiftUI's Swift-generic classes
        // (_UIHostingView, UIKitPlatformViewHost, CellHostingView, ...)
        // reads stale pointers and crashes (EXC_BAD_ACCESS) — same failure
        // iOS 26 had. "_TtGC7SwiftUI" is the mangled prefix of EVERY generic
        // Swift class in the SwiftUI module, so this skips the whole family.
        // Plain UIKit classes (UICollectionView, cells, ...) still dump fine.
        list.insert("_TtGC7SwiftUI")
        #elseif os(macOS)
        // macOS: untested territory — start permissive. If a capture
        // crashes, the last "BONE introspecting" console line names the
        // class; add its prefix here (the SwiftUI generic family would be
        // "_TtGC7SwiftUI", same mangling as the other platforms).
        #else
        if #unavailable(iOS 27.0) {
            // iOS 26: same crash on the hosting view. Fixed/changed in iOS 27.
            list.insert("_TtGC7SwiftUI14_UIHostingView")
        }
        #endif
        return list
    }()

    /// OS name + version, platform-appropriate.
    static var osDescription: String {
        #if canImport(UIKit)
        return "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
        #else
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        #endif
    }

    // MARK: Entry points

    /// Classic entry — builds the dump and writes the OS+timestamp-tagged
    /// .json/.txt pair (called from ListInspectablea after layout).
    static func run(named name: String, host: BonePlatformViewController, swiftUIRoot: Any) {
        write(makeDump(host: host, swiftUIRoot: swiftUIRoot), named: name)
    }

    /// Deep dump encoded as pretty-printed JSON — used by
    /// .bone(into: "*.json") and .bone3D(into: "*.json").
    static func encodedDump(host: BonePlatformViewController, swiftUIRoot: Any) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(makeDump(host: host, swiftUIRoot: swiftUIRoot))
    }

    /// Builds the full structured dump for a hosted view.
    static func makeDump(host: BonePlatformViewController, swiftUIRoot: Any) -> BoneDump {
        let rootView: BonePlatformView = host.view

        var visitedA = Set<ObjectIdentifier>()
        var visitedB = Set<ObjectIdentifier>()

        return BoneDump(
            os: osDescription,
            capturedAt: ISO8601DateFormatter().string(from: Date()),
            swiftUIRootMirror: "ROOT \(type(of: swiftUIRoot))\n"
                + mirrorDump(swiftUIRoot, visited: &visitedA),
            hostingViewMirror: "HOSTING \(type(of: rootView))\n"
                + mirrorDump(rootView, visited: &visitedB),
            recursiveDescription: {
                guard captureRecursiveDescription else { return nil }
                print("BONE introspecting recursiveDescription (root)")
                // UIKit: recursiveDescription; AppKit: _subtreeDescription.
                return privateString(rootView, "recursiveDescription")
                    ?? privateString(rootView, "_subtreeDescription")
            }(),
            autolayoutTrace: {
                guard captureAutolayoutTrace else { return nil }
                print("BONE introspecting _autolayoutTrace (root)")
                return privateString(rootView, "_autolayoutTrace")
            }(),
            tree: node(for: rootView)
        )
    }

    // MARK: Private-selector helpers (debug introspection)

    static func privateString(_ obj: NSObject, _ selectorName: String) -> String? {
        let sel = NSSelectorFromString(selectorName)
        guard obj.responds(to: sel) else { return nil }
        return obj.perform(sel)?.takeUnretainedValue() as? String
    }

    // MARK: View tree -> BoneNode (UIView / NSView)

    static func node(for view: BonePlatformView) -> BoneNode {
        var chain: [String] = []
        var cls: AnyClass? = type(of: view).superclass()
        while let c = cls, chain.count < 6 {
            chain.append(NSStringFromClass(c))
            cls = c.superclass()
        }

        // UIView.layer is non-optional, NSView.layer is optional — unify.
        let layer: CALayer? = view.layer
        let clsName = NSStringFromClass(type(of: view))

        var ivars: String?
        let denied = ivarDenylist.contains { clsName.hasPrefix($0) }
        if captureIvarDescriptions && !denied {
            // Last "BONE introspecting" line in the console before a crash
            // names the class (prefix) to add to `ivarDenylist`.
            print("BONE introspecting \(clsName)")
            ivars = privateString(view, "_ivarDescription").map { String($0.prefix(maxIvarLength)) }
        }

        return BoneNode(
            className: clsName,
            superclassChain: chain,
            frame: [view.frame.origin.x, view.frame.origin.y,
                    view.frame.size.width, view.frame.size.height].map(Double.init),
            layerClass: layer.map { NSStringFromClass(type(of: $0)) },
            sublayers: (layer?.sublayers ?? []).map { NSStringFromClass(type(of: $0)) },
            layerContents: layer?.contents.map { String(describing: $0).prefix(200).description },
            animationKeys: layer?.animationKeys() ?? [],
            ivarDescription: ivars,
            children: view.subviews.map { node(for: $0) }
        )
    }

    // MARK: Swift reflection — sees Swift stored properties incl. private ones.
    // Walks superclassMirror, so _UIHostingView's viewGraph & friends show up.

    static func mirrorDump(_ any: Any, depth: Int = 0,
                           visited: inout Set<ObjectIdentifier>) -> String {
        var out = ""
        func line(_ d: Int, _ s: String) {
            out += String(repeating: "  ", count: d) + s + "\n"
        }

        if depth > maxMirrorDepth { line(depth, "…max depth"); return out }

        let mirror = Mirror(reflecting: any)

        if mirror.displayStyle == .class {
            let id = ObjectIdentifier(any as AnyObject)
            if visited.contains(id) {
                line(depth, "cycle -> \(type(of: any))")
                return out
            }
            visited.insert(id)
        }

        // Include the whole superclass chain (Mirror.children excludes it).
        var mirrors: [Mirror] = [mirror]
        var sup = mirror.superclassMirror
        while let s = sup { mirrors.append(s); sup = s.superclassMirror }

        for m in mirrors {
            for (label, value) in m.children.prefix(48) {
                let typeName = String(describing: type(of: value))
                if let summary = leafSummary(value) {
                    line(depth, "\(label ?? "_"): \(typeName) = \(summary)")
                } else {
                    line(depth, "\(label ?? "_"): \(typeName)")
                    out += mirrorDump(value, depth: depth + 1, visited: &visited)
                }
            }
        }
        return out
    }

    private static func leafSummary(_ value: Any) -> String? {
        switch value {
        case let v as String:
            return "\"\(v.prefix(80))\""
        case is Bool, is Int, is Int64, is UInt, is Double, is Float, is CGFloat:
            return "\(value)"
        default:
            // Childless values (enums w/o payload, CGRect-like descriptions, etc.)
            let m = Mirror(reflecting: value)
            if m.children.isEmpty {
                return String(describing: value).prefix(120).description
            }
            return nil
        }
    }

    // MARK: Output

    /// Project-side mirror (simulator + native macOS): <project root>/captures/.
    /// `#filePath` bakes this source file's Mac path in at compile time,
    /// and the simulator shares the host filesystem, so the app can write
    /// there. On native macOS this works only without App Sandbox — with
    /// sandbox enabled the write fails gracefully and only Documents is used.
    /// On a real iOS/visionOS device this returns nil.
    private static var projectCaptureDirectory: URL? {
        #if targetEnvironment(simulator) || os(macOS)
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // library/
            .deletingLastPathComponent()   // Bone-27/ (sources)
            .deletingLastPathComponent()   // Bone-27/ (project root)
            .appendingPathComponent("captures", isDirectory: true)
        #else
        return nil
        #endif
    }

    private static func destinations(for fileName: String) -> [URL] {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var urls = [docs.appendingPathComponent(fileName)]
        if let proj = projectCaptureDirectory {
            try? FileManager.default.createDirectory(at: proj, withIntermediateDirectories: true)
            urls.append(proj.appendingPathComponent(fileName))
        }
        return urls
    }

    private static func writeData(_ data: Data, fileName: String) {
        for url in destinations(for: fileName) {
            do {
                try data.write(to: url)
                print("OUTPUT FILE: \(url.absoluteString)")
            } catch {
                print("BONE write failed (\(url.lastPathComponent)): \(error.localizedDescription)")
            }
        }
    }

    /// Mirrors the classic brief dump (the old output.txt content) to all
    /// destinations — Documents and, in the simulator, <project>/captures/.
    static func writeBrief(_ text: String, fileName: String = "briefoutput.txt") {
        writeData(Data(text.utf8), fileName: fileName)
    }

    private static func write(_ dump: BoneDump, named name: String) {
        let base = (name as NSString).deletingPathExtension

        // OS- and timestamp-tagged filenames
        // (e.g. output_capture_iOS27_0_2026-06-12_14-30-05.json) so dumps
        // from different runtimes and runs sit side by side, ready to diff.
        let osTag = osDescription
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: " ", with: "")

        let stampFormatter = DateFormatter()
        stampFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let stamp = stampFormatter.string(from: Date())
        let tag = "\(osTag)_\(stamp)"

        // JSON — structured, diffable across OS versions
        do {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            writeData(try enc.encode(dump), fileName: "\(base)_capture_\(tag).json")
        } catch {
            print("BONE JSON write failed: \(error.localizedDescription)")
        }

        // TXT — human-readable companion
        var txt = """
        ===== BoneCapture =====
        OS: \(dump.os)
        At: \(dump.capturedAt)

        ===== SwiftUI root value (Mirror) =====
        \(dump.swiftUIRootMirror)

        ===== Hosting view (Mirror -> ViewGraph etc.) =====
        \(dump.hostingViewMirror)

        """
        if let rd = dump.recursiveDescription {
            txt += "===== recursiveDescription =====\n\(rd)\n\n"
        }
        if let alt = dump.autolayoutTrace {
            txt += "===== _autolayoutTrace =====\n\(alt)\n\n"
        }
        txt += "===== UIKit tree (per-node _ivarDescription) =====\n"
        appendNode(dump.tree, depth: 0, into: &txt)

        writeData(Data(txt.utf8), fileName: "\(base)_capture_\(tag).txt")
    }

    private static func appendNode(_ n: BoneNode, depth: Int, into txt: inout String) {
        let pad = String(repeating: "  ", count: depth)
        txt += "\(pad)\(n.className)  frame=\(n.frame)\n"
        if !n.superclassChain.isEmpty {
            txt += "\(pad)  super: \(n.superclassChain.joined(separator: " < "))\n"
        }
        if let lc = n.layerClass {
            txt += "\(pad)  layer: \(lc)"
            if !n.sublayers.isEmpty { txt += "  sublayers: \(n.sublayers.joined(separator: ", "))" }
            txt += "\n"
        }
        if let c = n.layerContents { txt += "\(pad)  contents: \(c)\n" }
        if !n.animationKeys.isEmpty { txt += "\(pad)  animations: \(n.animationKeys.joined(separator: ", "))\n" }
        if let iv = n.ivarDescription {
            let indented = iv.split(separator: "\n").map { "\(pad)  | \($0)" }.joined(separator: "\n")
            txt += indented + "\n"
        }
        for child in n.children { appendNode(child, depth: depth + 1, into: &txt) }
    }
}

// MARK: - BoneDump -> DumpNode (3D rendering of deep dumps via .bone3DFrom)

extension BoneDump {

    /// Converts the deep capture tree into DumpNodes for the 3D graph.
    /// The ivar dump is truncated for the detail card.
    func dumpRoots() -> [DumpNode] {
        func convert(_ b: BoneNode, depth: Int, parent: DumpNode?) -> DumpNode {
            let node = DumpNode(name: b.className, depth: depth)
            node.parent = parent

            if !b.superclassChain.isEmpty {
                node.attributes.append(("superclass", b.superclassChain.joined(separator: " < ")))
            }
            if b.frame.count == 4 {
                node.attributes.append(("frame",
                    "(\(b.frame[0]), \(b.frame[1]); \(b.frame[2]) × \(b.frame[3]))"))
            }
            if let layerClass = b.layerClass {
                node.attributes.append(("layer", layerClass))
            }
            if !b.sublayers.isEmpty {
                node.attributes.append(("sublayers", b.sublayers.joined(separator: " / ")))
            }
            if let contents = b.layerContents {
                node.attributes.append(("contents", contents))
            }
            if !b.animationKeys.isEmpty {
                node.attributes.append(("animations", b.animationKeys.joined(separator: ", ")))
            }
            if let ivars = b.ivarDescription {
                node.attributes.append(("ivars", String(ivars.prefix(1500))))
            }

            node.children = b.children.map { convert($0, depth: depth + 1, parent: node) }
            return node
        }
        return [convert(tree, depth: 0, parent: nil)]
    }
}

#endif
