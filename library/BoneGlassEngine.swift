//
//  BoneGlassEngine.swift
//  Bone-27
//
//  The glass engine behind .tune and .dumpGlass on iOS and macOS. Liquid Glass
//  is the same layer tree on both – SDFLayer → CABackdropLayer with a
//  glassBackground filter → CASDFElementLayer – so one engine walks it: find
//  the layers carrying filters, read every input, write overrides through
//  "filters.<name>.<input>". The platform hosts only decide which layers belong
//  to the modified view: on iOS everything under its hosting view, on macOS the
//  layers whose centre lies inside it (BoneMac.swift). watchOS reaches the same
//  tree through the Objective-C runtime (BoneGlassRuntime.swift); all three
//  write the same report (BoneGlassReport).
//
//  Research use only — private Core Animation keys, never ship it.
//

#if DEBUG   // Bone is private API: it compiles to nothing outside Debug builds

#if (canImport(UIKit) && !os(watchOS)) || os(macOS)

import Foundation
import QuartzCore

/// A layer carrying filters, with its path from the walk's root.
typealias BoneGlassFound = (layer: CALayer, path: String)

enum BoneGlassEngine {

    /// Every layer under `root` (itself included) that carries a filter and passes `keep`, in drawing
    /// order, with a path like "CALayer ▹ [0]SDFLayer ▹ [1]CALayer ▹ [0]CABackdropLayer".
    static func found(under root: CALayer, keep: (CALayer) -> Bool = { _ in true }) -> [BoneGlassFound] {
        var out: [BoneGlassFound] = []
        func walk(_ layer: CALayer, _ path: String) {
            if !BoneGlassLayers.filters(on: layer).isEmpty, keep(layer) { out.append((layer, path)) }
            for (i, sub) in (layer.sublayers ?? []).enumerated() {
                walk(sub, "\(path) ▹ [\(i)]\(type(of: sub))")
            }
        }
        walk(root, String(describing: type(of: root)))
        return out
    }

    /// The .dumpGlass report for these layers.
    static func dump(_ found: [BoneGlassFound], only: [GlassInput]?) -> String {
        var rows: [BoneGlassFilterRow] = []
        for (layer, path) in found {
            for slot in ["filters", "backgroundFilters"] {
                for filter in (layer.value(forKey: slot) as? [NSObject]) ?? [] {
                    rows.append(BoneGlassFilterRow(path: path, slot: slot, type: BoneGlassLayers.ident(filter).type,
                                                   inputs: BoneFilterInputs.keys(of: filter).map { ($0, filter.value(forKey: $0)) }))
                }
            }
        }
        return BoneGlassReport.dump(rows, only: only, os: BoneOS.line)
    }

    /// Writes `values` into every matching filter input – except those the inspector holds;
    /// returns what changed.
    static func apply(_ values: [String: Any], to found: [BoneGlassFound]) -> [String] {
        var changes: [String] = []
        for (layer, _) in found {
            for ref in BoneGlassLayers.filters(on: layer) {
                for (key, newValue) in values {
                    guard let input = BoneGlassReport.input(key, name: ref.name, type: ref.type) else { continue }
                    if BoneGlassPanelModel.shared.holds(layer, filter: ref.name, key: input) { continue }
                    let path = ref.path(input)
                    let current = layer.value(forKeyPath: path)
                    if let current, BoneGlassReport.same(current, newValue) { continue }
                    layer.setValue(newValue, forKeyPath: path)
                    changes.append(BoneGlassReport.change(layer: "\(type(of: layer))", path: path, from: current, to: newValue))
                }
            }
        }
        return changes
    }
}

/// Re-applies a tuning 8× a second (SwiftUI rebuilds the filter on hover, press and state
/// changes) and logs the first changes once. `.tune(file:)` re-reads its JSON when it changes.
final class BoneGlassTuner {

    var values: [String: Any]
    private let log: String?
    private let layers: () -> [BoneGlassFound]?
    private var fileURL: URL?
    private var fileStamp: Date?
    private var ticker: BoneTicker?
    private var ticks = 0
    private var logged = false

    /// `layers` returns nil once the view is gone, which stops the tuner.
    init(values: [String: Any], log: String?, file: String? = nil, layers: @escaping () -> [BoneGlassFound]?) {
        self.values = values
        self.log = log
        self.layers = layers
        if let file {
            fileURL = BoneCapture.readableURL(for: file)
            reloadIfChanged()
        }
    }

    func start() {
        guard ticker == nil, !values.isEmpty || fileURL != nil else { return }
        ticker = BoneTicker { [weak self] in self?.tick() }
    }

    func stop() {
        ticker?.stop()
        ticker = nil
    }

    private func reloadIfChanged() {
        guard let url = fileURL else { return }
        let stamp = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        guard stamp != fileStamp else { return }
        fileStamp = stamp
        guard let data = try? Data(contentsOf: url), let v = BoneGlassJSON.tunerValues(from: data) else { return }
        values = v
        logged = false
    }

    private func tick() {
        guard let found = layers() else { stop(); return }
        ticks += 1
        if fileURL != nil, ticks % 4 == 0 { reloadIfChanged() }
        let changes = BoneGlassEngine.apply(values, to: found)
        guard let log, !logged, !changes.isEmpty else { return }
        logged = true
        BoneCapture.writeData(Data(BoneGlassReport.tuneLog(values: values, changes: changes, os: BoneOS.line).utf8), fileName: log)
    }
}

#endif

#endif   // DEBUG
