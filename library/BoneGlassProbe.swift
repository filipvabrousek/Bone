//
//  BoneGlassProbe.swift
//  Bone-27
//
//  Finds out which Liquid Glass filter inputs actually change the rendered
//  glass – including the hidden ones SwiftUI never sets.
//
//      Button("Liquid") {}.glassEffect().probeGlass("glass-probe.txt")
//
//  For every input name the SDK exports (kCAFilterInput…, 136 on iOS 27) and
//  every key already on the filter, it sets a few test values, captures the
//  composited screen and counts the pixels that changed around the glass.
//  Inputs that changed nothing are tried again with the hidden inputs that
//  did (some only modulate another one, e.g. a height that needs an amount).
//
//  Writes glass-probe.txt (report), glass-probe.json and glass-probe.png
//  (contact sheet of every live input). Put the glass over a structured
//  backdrop – refraction, blur and aberration are invisible over a flat colour.
//  The glass panel (.glassPanel) runs the same probe on any glass you pick.
//
//  Research / simulator use only — private API, never ship it.
//

#if canImport(UIKit)

import SwiftUI
import UIKit

extension View {

    /// Probes the first Liquid Glass element in this view: which filter inputs change the rendering.
    /// - Parameter after: seconds to wait, so the glass has rendered.
    func probeGlass(_ fileName: String = "glass-probe.txt", after delay: Double = 2) -> some View {
        BoneGlassProbeHost(fileName: fileName, delay: delay) { self }
    }
}

// MARK: - Hosting wrapper

struct BoneGlassProbeHost<Content: View>: UIViewControllerRepresentable {
    let fileName: String
    let delay: Double
    let content: Content

    init(fileName: String, delay: Double, @ViewBuilder content: () -> Content) {
        self.fileName = fileName
        self.delay = delay
        self.content = content()
    }

    func makeUIViewController(context: Context) -> UIHostingController<Content> {
        let hosting = UIHostingController(rootView: content)
        hosting.view.backgroundColor = .clear
        hosting.sizingOptions = [.intrinsicContentSize]
        let fileName = fileName
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak view = hosting.view] in
            guard let view, let window = view.window,
                  let glass = BoneGlassLayers.glassLayers(in: view.layer).first else {
                let text = "BONE · probeGlass\n(no glass found – is .glassEffect() applied and rendered?)\n"
                BoneCapture.writeData(Data(text.utf8), fileName: fileName)
                return
            }
            let element = BoneGlassLayers.element(of: glass)
            BoneGlassProber(element: element, window: window,
                            filters: BoneGlassLayers.filterRefs(inElement: element))
                .run { $0.write(fileName: fileName) }   // the prober keeps itself alive until done
        }
        return hosting
    }

    func updateUIViewController(_ hosting: UIHostingController<Content>, context: Context) {
        hosting.rootView = content
    }

    /// Size of the content, not of the space offered (keeps stacks tight).
    func sizeThatFits(_ proposal: ProposedViewSize, uiViewController: UIHostingController<Content>, context: Context) -> CGSize? {
        uiViewController.sizeThatFits(in: CGSize(width: proposal.width ?? .infinity, height: proposal.height ?? .infinity))
    }
}

// MARK: - Report

struct BoneGlassProbeReport {
    var text: String
    var json: Data?
    var sheet: Data?
    var summary: String
    /// filter index → hidden input keys that changed the rendering
    var liveHidden: [Int: [String]]

    func write(fileName: String) {
        BoneCapture.writeData(Data(text.utf8), fileName: fileName)
        let base = (fileName as NSString).deletingPathExtension
        if let json { BoneCapture.writeData(json, fileName: base + ".json") }
        if let sheet { BoneCapture.writeData(sheet, fileName: base + ".png") }
    }
}

// MARK: - Prober

final class BoneGlassProber {

    /// An input counts as live when at least this many pixels change (channel difference > 8).
    static let liveThreshold = 50
    /// Points around the element that are compared too: shadows, outer refraction.
    static let margin: CGFloat = 24

    final class Result {
        let filterIndex: Int
        let ref: BoneFilterRef
        let key: String
        let exported: Bool
        let wasSet: Bool
        let kind: BoneValueKind
        var skipped: String?
        var trials: [(label: String, changed: Int)] = []
        var bestLabel = ""
        var bestValue: Any?
        var bestChanged = 0
        var tile: CGImage?
        var pass2 = false
        var restoreDrift = 0      // pixels still different after restoring

        var live: Bool { bestChanged >= BoneGlassProber.liveThreshold }
        var label: String { GlassInput(rawValue: key)?.caseName ?? key }

        init(filterIndex: Int, ref: BoneFilterRef, key: String, exported: Bool, wasSet: Bool, kind: BoneValueKind) {
            self.filterIndex = filterIndex
            self.ref = ref
            self.key = key
            self.exported = exported
            self.wasSet = wasSet
            self.kind = kind
        }
    }

    let element: CALayer
    let window: UIWindow
    let filters: [BoneFilterRef]
    /// (done, total, input) – called before each input.
    var progress: ((Int, Int, String) -> Void)?

    private var region = CGRect.zero        // points
    private var crop = CGRect.zero          // screen pixels
    private var baseline: BonePixels?
    private var baselineTile: CGImage?
    private var contextTile: CGImage?
    private var noise = 0
    private var results: [Result] = []
    private var snapshots: [(layer: CALayer, slot: String, filters: [NSObject])] = []
    private var context: [(ref: BoneFilterRef, key: String, value: Any)] = []
    private var contextUsed: [String] = []
    private var drift: [String] = []
    private var unsettled = 0               // captures that never agreed twice in a row
    private var startedAt = Date()

    init(element: CALayer, window: UIWindow, filters: [BoneFilterRef]) {
        self.element = element
        self.window = window
        self.filters = filters
    }

    /// Runs on the main actor without blocking it; `completion` gets the report.
    func run(completion: @escaping (BoneGlassProbeReport) -> Void) {
        Task {   // the task keeps the prober alive until it is done
            let report = await self.probeAll()
            completion(report)
        }
    }

    private func probeAll() async -> BoneGlassProbeReport {
        startedAt = Date()
        CATransaction.flush()
        guard let shot = BoneScreen.capture() else {
            return makeReport(error: "screen capture unavailable (_UICreateScreenUIImage)")
        }
        let width = BoneScreen.width(of: window)
        let scale = CGFloat(shot.width) / width
        let screen = CGRect(x: 0, y: 0, width: width, height: CGFloat(shot.height) / scale)
        region = BoneGlassLayers.screenFrame(of: element, in: window)
            .insetBy(dx: -Self.margin, dy: -Self.margin).intersection(screen)
        crop = CGRect(x: region.minX * scale, y: region.minY * scale,
                      width: region.width * scale, height: region.height * scale).integral

        // copies of every filter list of the element – the last-resort restore
        var seen = Set<String>()
        for ref in filters {
            guard let layer = ref.layer, let list = layer.value(forKey: ref.slot) as? [NSObject] else { continue }
            if seen.insert("\(ObjectIdentifier(layer).hashValue).\(ref.slot)").inserted {
                snapshots.append((layer, ref.slot, list.compactMap { $0.copy() as? NSObject }))
            }
        }

        guard let base = await settledGrab() else { return makeReport(error: "could not read the glass region \(region)") }
        baseline = base
        noise = await settledGrab()?.changed(from: base) ?? 0
        baselineTile = base.image()

        let names = BoneFilterInputNames.resolved
        let exported = Dictionary(names.map { ($0.key, $0.exported) }, uniquingKeysWith: { a, _ in a })
        for (i, ref) in filters.enumerated() {
            let present = Set(ref.keys)
            for key in Set(names.map(\.key)).union(present).sorted() where key != "inputSourceSublayerName" {
                let current = present.contains(key) ? ref.value(key) : nil
                let r = Result(filterIndex: i, ref: ref, key: key, exported: exported[key] ?? false,
                               wasSet: present.contains(key), kind: BoneValueKind.of(key: key, current: current))
                if trials(for: r.kind, current: current).isEmpty { r.skipped = "\(r.kind.rawValue) value – not tried" }
                results.append(r)
            }
        }

        // pass 1: every input on its own
        let pass1 = results.filter { $0.skipped == nil }
        for (n, r) in pass1.enumerated() { await probe(r, pass: 1, n: n + 1, of: pass1.count) }

        // pass 2: inputs that changed nothing, again – with every hidden input
        // that did change something switched on (some only modulate another one)
        let hiddenLive = results.filter { $0.live && !$0.wasSet }
        context = hiddenLive.compactMap { r in r.bestValue.map { (r.ref, r.key, $0) } }
        contextUsed = hiddenLive.map { "\($0.label) = \($0.bestLabel)" }
        let dead = results.filter { $0.skipped == nil && !$0.live }
        if !context.isEmpty, !dead.isEmpty {
            applyContext(except: nil)
            CATransaction.flush()
            baseline = await settledGrab()
            contextTile = baseline?.image()
            for (n, r) in dead.enumerated() {
                r.pass2 = true
                await probe(r, pass: 2, n: n + 1, of: dead.count)
            }
        }

        for c in context { c.ref.remove(c.key) }   // context inputs were all hidden
        context = []
        restoreSnapshots()
        CATransaction.flush()
        try? FileManager.default.removeItem(at: BoneCapture.readableURL(for: "glass-probe.progress.txt"))
        return makeReport(error: nil)
    }

    private func probe(_ r: Result, pass: Int, n: Int, of total: Int) async {
        progress?(n, total, (pass == 2 ? "pass 2 · " : "") + r.label)
        // the last input touched, in case the render server falls over on one
        let note = "probing \(r.ref.name).\(r.key) (pass \(pass), \(n)/\(total))\n"
        try? Data(note.utf8).write(to: BoneCapture.readableURL(for: "glass-probe.progress.txt"))

        guard let base = baseline else { return }
        let original = r.wasSet ? r.ref.value(r.key) : nil
        for (label, value) in trials(for: r.kind, current: original) {
            applyContext(except: r)
            r.ref.set(r.key, value)
            CATransaction.flush()
            guard let px = await settledGrab() else { continue }
            let changed = px.changed(from: base)
            r.trials.append((pass == 2 ? label + " +ctx" : label, changed))
            if changed > r.bestChanged || r.bestLabel.isEmpty {
                r.bestChanged = changed
                r.bestLabel = label
                r.bestValue = value
                r.tile = changed >= Self.liveThreshold ? px.image() : nil
            }
        }
        // restore in place: the original value, or remove an input SwiftUI never set
        if let original { r.ref.set(r.key, original) } else { r.ref.remove(r.key) }
        applyContext(except: nil)
        CATransaction.flush()
        r.restoreDrift = await settledGrab()?.changed(from: base) ?? 0
        if r.restoreDrift >= Self.liveThreshold {
            // last resort: the original filter objects (a re-added filter needs ~1 frame)
            restoreSnapshots()
            applyContext(except: nil)
            CATransaction.flush()
            if let px = await settledGrab() {
                r.restoreDrift = px.changed(from: base)
                if r.restoreDrift >= Self.liveThreshold {   // still different – compare later inputs to this
                    drift.append("\(r.ref.name).\(r.key) (\(r.restoreDrift) px)")
                    baseline = px
                }
            }
        }
    }

    // MARK: Helpers

    private func grab() -> BonePixels? {
        autoreleasepool {
            guard let shot = BoneScreen.capture() else { return nil }
            return BonePixels(shot, crop: crop)
        }
    }

    /// A capture taken after the render server has caught up: wait two frames,
    /// then accept once two captures in a row agree. (Right after
    /// CATransaction.flush() the screen sometimes still shows the previous commit.)
    private func settledGrab() async -> BonePixels? {
        try? await Task.sleep(nanoseconds: 34_000_000)
        guard var last = grab() else { return nil }
        for _ in 0..<10 {
            guard let next = grab() else { return last }
            if next.changed(from: last) == 0 { return next }
            last = next
            try? await Task.sleep(nanoseconds: 17_000_000)
        }
        unsettled += 1
        return last
    }

    /// Copies of the original filter objects back in place.
    private func restoreSnapshots() {
        for s in snapshots { s.layer.setValue(s.filters.compactMap { $0.copy() as? NSObject }, forKey: s.slot) }
    }

    private func applyContext(except r: Result?) {
        for c in context where !(r != nil && c.ref.name == r!.ref.name && c.key == r!.key) { c.ref.set(c.key, c.value) }
    }

    private func trials(for kind: BoneValueKind, current: Any?) -> [(String, Any)] {
        switch kind {
        case .number:
            let c = (current as? NSNumber)?.doubleValue
            return [0, 1, 10, 50, -10].filter { c == nil || abs($0 - c!) > 1e-9 }
                .map { (Self.fmt($0), NSNumber(value: $0)) }
        case .toggle:
            let on = ((current as? NSNumber)?.doubleValue ?? 0) != 0
            return [(on ? "0" : "1", NSNumber(value: on ? 0 : 1))]
        case .color:
            return [("red", CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)),
                    ("green", CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1))]
        case .size:
            return [("size(0, 0)", NSValue(cgSize: .zero)), ("size(20, 20)", NSValue(cgSize: CGSize(width: 20, height: 20)))]
        case .matrix:
            return [("swapRedBlue", BoneColorMatrix.value(BoneColorMatrix.swapRedBlue)),
                    ("invert", BoneColorMatrix.value(BoneColorMatrix.invert))]
        default:
            return []
        }
    }

    static func fmt(_ d: Double) -> String {
        d == d.rounded() && abs(d) < 1e9 ? String(Int(d)) : String(format: "%.4g", d)
    }

    // MARK: Report

    private func makeReport(error: String?) -> BoneGlassProbeReport {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var t = "BONE · probeGlass\n"
        t += "OS: \(UIDevice.current.systemName) \(UIDevice.current.systemVersion) · captured: \(df.string(from: Date()))"
        t += String(format: " · %.1f s\n", Date().timeIntervalSince(startedAt))
        if let error {
            t += "ERROR: \(error)\n"
            return BoneGlassProbeReport(text: t, json: nil, sheet: nil, summary: "probe failed: \(error)", liveHidden: [:])
        }
        let pixels = max(1, Int(crop.width) * Int(crop.height))
        func pct(_ n: Int) -> String { String(format: "%.1f%%", Double(n) * 100 / Double(pixels)) }

        t += "element: \(type(of: element)) · region \(Int(region.minX)),\(Int(region.minY)) \(Int(region.width))×\(Int(region.height)) pt"
        t += " (element ±\(Int(Self.margin)) pt) = \(pixels) px\n"
        t += "capture: _UICreateScreenUIImage, settled (2 frames, then two identical captures in a row) · noise \(noise) px"
        t += unsettled > 0 ? " · \(unsettled) captures never settled" : ""
        t += " · restores in place (nil removes a key)"
        t += " · LIVE = ≥ \(Self.liveThreshold) px changed (channel difference > 8)\n"
        t += "candidates: \(BoneFilterInputNames.symbols.count) SDK input names (kCAFilterInput…) + keys already on the filter\n"
        t += "numbers tried: 0, 1, 10, 50, -10 · toggles flipped · colours red, green · matrices swapRedBlue, invert\n"
        t += "backdrop matters: refraction, blur and aberration only show over structure –\n"
        t += "an input with no visible effect here can still do something over another backdrop.\n"
        if !contextUsed.isEmpty { t += "pass 2 context (hidden inputs switched on): \(contextUsed.joined(separator: ", "))\n" }
        if !drift.isEmpty { t += "re-baselined after (did not restore cleanly): \(drift.joined(separator: ", "))\n" }

        func row(_ r: Result) -> String {
            var s = "   " + (r.label == r.key ? r.key : "\(r.label)  (\(r.key))")
            s = s.padding(toLength: max(s.count, 62), withPad: " ", startingAt: 0)
            s += r.kind.rawValue.padding(toLength: 8, withPad: " ", startingAt: 0)
            if let skip = r.skipped { s += skip } else {
                s += r.trials.map { "\($0.label): \(pct($0.changed))" }.joined(separator: " · ")
            }
            if !r.exported { s += "   [not an SDK constant]" }
            return s + "\n"
        }
        for (i, ref) in filters.enumerated() {
            let rs = results.filter { $0.filterIndex == i }
            t += "\n===== [\(i)] \(ref.type)  (\(ref.slot) on \(ref.layer.map { String(describing: type(of: $0)) } ?? "?")) =====\n"
            let sections: [(String, [Result])] = [
                ("LIVE – hidden: not set when the probe started (SwiftUI never sets it)", rs.filter { $0.live && !$0.wasSet && !$0.pass2 }),
                ("LIVE – only together with the hidden inputs (pass 2)", rs.filter { $0.live && $0.pass2 }),
                ("LIVE – already set (by SwiftUI, or by .tune / the panel)", rs.filter { $0.live && $0.wasSet && !$0.pass2 }),
                ("no visible effect", rs.filter { !$0.live && $0.skipped == nil }),
                ("skipped", rs.filter { $0.skipped != nil }),
            ]
            for (title, list) in sections where !list.isEmpty {
                t += "\n-- \(title) (\(list.count))\n"
                list.forEach { t += row($0) }
            }
        }

        let hidden = results.filter { $0.live && !$0.wasSet && !$0.pass2 }
        let combo = results.filter { $0.live && $0.pass2 }
        let known = results.filter { $0.live && $0.wasSet && !$0.pass2 }
        let dead = results.filter { !$0.live && $0.skipped == nil }
        let skipped = results.filter { $0.skipped != nil }
        let summary = "\(hidden.count) hidden live · \(combo.count) live in combination · \(known.count) already-set live"
            + " · \(dead.count) no effect · \(skipped.count) skipped"
        t += "\nsummary: \(summary)\n"

        var liveHidden: [Int: [String]] = [:]
        for r in hidden + combo where !r.wasSet { liveHidden[r.filterIndex, default: []].append(r.key) }

        let rows: [[String: Any]] = results.map { r in [
            "filter": r.ref.type, "key": r.key, "name": r.label, "kind": r.kind.rawValue,
            "sdkConstant": r.exported, "setBySwiftUI": r.wasSet, "live": r.live, "pass2": r.pass2,
            "skipped": r.skipped ?? NSNull(), "best": r.bestLabel, "bestChangedPixels": r.bestChanged,
            "restoreDriftPixels": r.restoreDrift,
            "trials": r.trials.map { ["value": $0.label, "changedPixels": $0.changed] },
        ] }
        let json = try? JSONSerialization.data(withJSONObject: [
            "os": "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
            "regionPixels": pixels, "liveThreshold": Self.liveThreshold, "noisePixels": noise,
            "pass2Context": contextUsed, "results": rows,
        ], options: [.prettyPrinted, .sortedKeys])

        var tiles: [(String, String, CGImage?)] = [("baseline", "before the probe", baselineTile)]
        if contextTile != nil { tiles.append(("pass 2 baseline", "hidden inputs on", contextTile)) }
        for r in hidden + combo + known {
            tiles.append(("\(r.label) = \(r.bestLabel)",
                          "\(filters[r.filterIndex].type) · \(pct(r.bestChanged))\(r.wasSet ? "" : " · hidden")", r.tile))
        }
        return BoneGlassProbeReport(text: t, json: json, sheet: Self.sheet(tiles), summary: summary, liveHidden: liveHidden)
    }

    private static func sheet(_ tiles: [(String, String, CGImage?)]) -> Data? {
        guard let first = tiles.compactMap({ $0.2 }).first else { return nil }
        let tileW: CGFloat = 300, gap: CGFloat = 14, cols = 5
        let imgH = tileW * CGFloat(first.height) / CGFloat(first.width)
        let tileH = imgH + 42
        let rows = (tiles.count + cols - 1) / cols
        let size = CGSize(width: CGFloat(cols) * (tileW + gap) + gap, height: CGFloat(rows) * (tileH + gap) + gap)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let bold: [NSAttributedString.Key: Any] = [.font: UIFont.monospacedSystemFont(ofSize: 13, weight: .bold)]
            let small: [NSAttributedString.Key: Any] = [.font: UIFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                                                         .foregroundColor: UIColor.darkGray]
            for (i, tile) in tiles.enumerated() {
                let x = gap + CGFloat(i % cols) * (tileW + gap), y = gap + CGFloat(i / cols) * (tileH + gap)
                (tile.0 as NSString).draw(in: CGRect(x: x, y: y, width: tileW, height: 18), withAttributes: bold)
                (tile.1 as NSString).draw(in: CGRect(x: x, y: y + 19, width: tileW, height: 16), withAttributes: small)
                if let cg = tile.2 { UIImage(cgImage: cg).draw(in: CGRect(x: x, y: y + 40, width: tileW, height: imgH)) }
            }
        }
        return image.pngData()
    }
}

#endif
