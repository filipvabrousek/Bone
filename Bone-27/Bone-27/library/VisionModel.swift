//
//  VisionModel.swift
//  Bone-vision
//
//  Loads brief dumps (briefoutput.txt / output.txt) and turns them into a
//  tappable 3D hierarchy of RealityKit entities.
//
//  In the simulator the app reads the project's captures/ folder directly —
//  the visionOS simulator shares the Mac filesystem, and #filePath bakes in
//  this source file's location at compile time.
//

#if os(visionOS)

import SwiftUI
import RealityKit
import Observation

@Observable
final class VisionModel {

    // Parsed data
    var roots: [DumpNode] = []
    var osInfo: String?
    var loadedName = "—"
    var availableFiles: [URL] = []
    var selected: DumpNode?

    // RealityKit plumbing
    var treeRoot: Entity?
    private var registry: [String: (node: DumpNode, entity: ModelEntity)] = [:]
    private var selectedEntity: ModelEntity?

    // MARK: Where the dumps live (simulator only)
    // Shared with the library's .bone3DFrom(_:) file resolution.

    static var capturesDirectory: URL? {
        Bone3DFileResolver.capturesDirectory
    }

    // MARK: Loading

    func initialLoad() {
        refreshFiles()
        if let brief = availableFiles.first(where: { $0.lastPathComponent == "briefoutput.txt" })
            ?? availableFiles.first {
            load(url: brief)
        } else {
            loadSample()
        }
    }

    func refreshFiles() {
        guard let dir = Self.capturesDirectory else { availableFiles = []; return }
        let all = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil)) ?? []
        // Brief-format dumps only — the full *_capture_*.txt files use a
        // different layout this parser doesn't speak.
        availableFiles = all
            .filter { $0.pathExtension == "txt" && !$0.lastPathComponent.contains("_capture_") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func load(url: URL) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        apply(text: text, name: url.lastPathComponent)
    }

    func loadSample() {
        apply(text: SampleDump.text, name: "sample (List + Text, iOS 27)")
    }

    private func apply(text: String, name: String) {
        let parsed = BriefDumpParser.parse(text)
        roots = parsed.roots
        osInfo = parsed.os
        loadedName = name
        rebuild()
    }

    // MARK: Building the 3D tree

    func rebuild() {
        guard let treeRoot else { return }
        treeRoot.children.removeAll()
        registry.removeAll()
        selected = nil
        selectedEntity = nil
        guard !roots.isEmpty else { return }

        let built = HierarchyBuilder.buildTree(roots: roots, fit: [1.7, 1.0, 0.5])
        registry = built.registry
        treeRoot.addChild(built.container)
    }

    // MARK: Selection

    func select(entityNamed name: String) {
        guard let (node, entity) = registry[name] else {
            print("BONE select: no registry entry for '\(name)' (registry has \(registry.count) nodes)")
            return
        }
        print("BONE select: \(node.shortName)")

        // Restore previous highlight
        selectedEntity?.scale = .one

        if selected?.id == node.id {
            selected = nil
            selectedEntity = nil
            return
        }
        selected = node
        selectedEntity = entity
        entity.scale = .init(repeating: 1.2)
    }
}

#endif
