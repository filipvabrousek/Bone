//
//  Bone3D.swift
//  Bone library (visionOS)
//
//  visionOS additions to the Bone library:
//
//    List { Text("Hello") }
//        .bone3D()                       // live 3D hierarchy of THIS view
//
//    List { Text("Hello") }
//        .bone3DFrom("briefoutput.txt")  // 3D graph parsed from a brief dump
//
//  Both render UNBOUNDED in a volumetric window: the hierarchy slabs float
//  freely in the volume, the wrapped content and the tapped-node detail
//  card hover as glass attachments (same look as the original viewer).
//
//  .bone3D() hosts the content in a UIHostingController (UIKit exists on
//  visionOS) and walks the resulting UIView hierarchy directly into
//  DumpNodes — no text round-trip.
//
//  .bone3DFrom(_:) resolves the file name against an absolute path, the
//  project captures/ folder (simulator), then the app's Documents folder.
//

#if os(visionOS)

import SwiftUI
import RealityKit
import UIKit
import Observation

// MARK: - Public API

public extension View {

    /// Shows this view as a floating card plus a live, tappable, unbounded
    /// 3D representation of its UIKit view hierarchy in the volume.
    /// Pass `into:` to also dump the captured tree to a file — the extension
    /// decides the format: ".json" writes the structured JSON tree, anything
    /// else writes the classic brief text dump.
    func bone3D(into file: String? = nil) -> some View {
        Bone3DLiveContainer(content: self, dumpFile: file)
    }

    /// Shows this view as a floating card plus an unbounded 3D graph built
    /// from a dump file: ".json" files are decoded as the structured tree,
    /// anything else is parsed as the classic brief text format.
    func bone3DFrom(_ file: String) -> some View {
        Bone3DFileContainer(content: self, file: file)
    }
}

// MARK: - Dump writing (extension decides format)

enum Bone3DDumpWriter {

    /// Brief text dump (classic format) of the captured tree.
    static func writeBrief(roots: [DumpNode], to name: String) {
        var text = DumpSerializer.briefText(roots: roots)
        text += "-------------------------\n"
        text += "OS: \(UIDevice.current.systemName):\(ProcessInfo().operatingSystemVersion.majorVersion)\n"
        writeData(Data(text.utf8), to: name)
    }

    /// Writes data to Documents and (simulator) the project's captures/.
    static func writeData(_ data: Data, to name: String) {
        var urls = [FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(name)]
        if let captures = Bone3DFileResolver.capturesDirectory {
            try? FileManager.default.createDirectory(
                at: captures, withIntermediateDirectories: true)
            urls.append(captures.appendingPathComponent(name))
        }
        for url in urls {
            do {
                try data.write(to: url)
                print("OUTPUT FILE: \(url.absoluteString)")
            } catch {
                print("BONE3D write failed (\(url.lastPathComponent)): \(error.localizedDescription)")
            }
        }
    }
}

/// Hosts the SwiftUI content in a UIHostingController so its real UIKit
/// hierarchy exists, then walks it after layout settles. If `dumpFile` is
/// set, also writes the dump: ".json" -> deep SwiftUI dump (BoneCapture
/// schema, like the output_capture_*.json files), else brief text.
private struct Bone3DCaptureHost<Content: View>: UIViewRepresentable {
    let content: Content
    var dumpFile: String?
    let onCapture: ([DumpNode]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var controller: UIViewController?
        var captured = false
    }

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        let host = UIHostingController(rootView: content)
        context.coordinator.controller = host

        host.view.frame = container.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.view.backgroundColor = .clear
        container.addSubview(host.view)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            guard !context.coordinator.captured else { return }
            context.coordinator.captured = true
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()

            let roots = [host.view.boneNodeTree()]
            onCapture(roots)

            if let dumpFile {
                if dumpFile.lowercased().hasSuffix(".json") {
                    if let data = try? BoneCapture.encodedDump(host: host, swiftUIRoot: content) {
                        Bone3DDumpWriter.writeData(data, to: dumpFile)
                    } else {
                        print("BONE3D JSON encode failed")
                    }
                } else {
                    Bone3DDumpWriter.writeBrief(roots: roots, to: dumpFile)
                }
            }
        }
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

// MARK: - File resolution

enum Bone3DFileResolver {

    /// Project-side captures folder (simulator only). `#filePath` bakes in
    /// this source file's Mac path at compile time; the simulator shares the
    /// host filesystem. On device this returns nil.
    static var capturesDirectory: URL? {
        #if targetEnvironment(simulator)
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // library/
            .deletingLastPathComponent()   // Bone-27/ (sources)
            .deletingLastPathComponent()   // Bone-27/ (project root)
            .appendingPathComponent("captures", isDirectory: true)
        #else
        return nil
        #endif
    }

    /// Absolute path -> project captures/ (simulator) -> app Documents.
    static func resolve(_ name: String) -> URL? {
        let fm = FileManager.default

        let direct = URL(fileURLWithPath: name)
        if fm.fileExists(atPath: direct.path) { return direct }

        if let captures = capturesDirectory {
            let url = captures.appendingPathComponent(name)
            if fm.fileExists(atPath: url.path) { return url }
        }

        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(name)
        if fm.fileExists(atPath: docs.path) { return docs }

        return nil
    }
}

// MARK: - Selection model

@Observable
final class Bone3DModel {
    var selected: DumpNode?
    var treeRoot: Entity?
    private var registry: [String: (node: DumpNode, entity: ModelEntity)] = [:]
    private var selectedEntity: ModelEntity?
    private var roots: [DumpNode] = []

    func set(roots: [DumpNode]) {
        self.roots = roots
        rebuild()
    }

    private func rebuild() {
        guard let treeRoot else { return }
        treeRoot.children.removeAll()
        registry.removeAll()
        selected = nil
        selectedEntity = nil
        guard !roots.isEmpty else { return }

        // Unbounded volumetric fit (matches the volumetric demo windows).
        let built = HierarchyBuilder.buildTree(roots: roots, fit: [1.3, 0.8, 0.5])
        registry = built.registry
        treeRoot.addChild(built.container)
    }

    func select(entityNamed name: String) {
        guard let (node, entity) = registry[name] else { return }
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

// MARK: - Unbounded volumetric graph (tree floats free, cards as attachments)

private struct Bone3DVolumeView<Header: View>: View {
    var roots: [DumpNode]
    @ViewBuilder var header: () -> Header
    @State private var model = Bone3DModel()

    var body: some View {
        RealityView { content, attachments in
            let root = Entity()
            content.add(root)
            model.treeRoot = root
            model.set(roots: roots)

            if let headerEntity = attachments.entity(for: "header") {
                headerEntity.position = [0, 0.48, 0.25]
                content.add(headerEntity)
            }
            if let info = attachments.entity(for: "info") {
                info.position = [0.62, 0.05, 0.3]
                content.add(info)
            }
        } update: { _, _ in
        } attachments: {
            Attachment(id: "header") { header() }
            Attachment(id: "info") { Bone3DInfoCard(model: model) }
        }
        .gesture(
            TapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    model.select(entityNamed: value.entity.name)
                }
        )
        .onChange(of: roots.map(\.id)) {
            model.set(roots: roots)
        }
    }
}

// MARK: - Floating detail card

private struct Bone3DInfoCard: View {
    var model: Bone3DModel

    var body: some View {
        Group {
            if let node = model.selected {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(node.shortName)
                            .font(.title3.bold())

                        Text(node.name)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)

                        Divider()

                        row("depth", "\(node.depth)")
                        if let parent = node.parent {
                            row("parent", parent.shortName)
                        }
                        row("children", "\(node.children.count)")
                        row("subtree", "\(node.subtreeCount) views")

                        if !node.attributes.isEmpty {
                            Divider()
                            ForEach(Array(node.attributes.enumerated()), id: \.offset) { _, attr in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(attr.key)
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                    Text(attr.value)
                                        .font(.caption.monospaced())
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                    .padding(20)
                }
                .frame(width: 400, height: 440)
                .glassBackgroundEffect()
            } else {
                EmptyView()
            }
        }
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(key)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.caption.monospaced())
        }
    }
}

// MARK: - Containers behind the modifiers

private struct Bone3DLiveContainer<Content: View>: View {
    let content: Content
    var dumpFile: String?
    @State private var roots: [DumpNode] = []

    var body: some View {
        Bone3DVolumeView(roots: roots) {
            VStack(spacing: 8) {
                Bone3DCaptureHost(content: content, dumpFile: dumpFile) { captured in
                    roots = captured
                }
                .frame(width: 460, height: 300)

                if roots.isEmpty {
                    ProgressView("Capturing hierarchy…")
                        .padding(.bottom, 8)
                }
            }
            .padding(12)
            .glassBackgroundEffect()
        }
    }
}

private struct Bone3DFileContainer<Content: View>: View {
    let content: Content
    let file: String
    @State private var roots: [DumpNode] = []
    @State private var loadError: String?

    var body: some View {
        Bone3DVolumeView(roots: roots) {
            VStack(spacing: 8) {
                content
                    .frame(width: 460, height: 300)

                if let loadError {
                    Label(loadError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .padding(.bottom, 8)
                }
            }
            .padding(12)
            .glassBackgroundEffect()
        }
        .task {
            guard let url = Bone3DFileResolver.resolve(file) else {
                loadError = "Dump file not found: \(file)"
                return
            }
            if url.pathExtension.lowercased() == "json" {
                guard let data = try? Data(contentsOf: url) else {
                    loadError = "Could not read: \(url.lastPathComponent)"
                    return
                }
                // Deep SwiftUI dump (BoneCapture schema) first — the format
                // of output_capture_*.json and .bone(into: "*.json").
                if let deep = try? JSONDecoder().decode(BoneDump.self, from: data) {
                    roots = deep.dumpRoots()
                } else if let legacy = try? DumpSerializer.rootsFromJSON(data) {
                    roots = legacy
                } else {
                    loadError = "Not a Bone JSON dump: \(url.lastPathComponent)"
                }
            } else {
                guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                    loadError = "Could not read: \(url.lastPathComponent)"
                    return
                }
                roots = BriefDumpParser.parse(text).roots
            }
        }
    }
}

#endif
