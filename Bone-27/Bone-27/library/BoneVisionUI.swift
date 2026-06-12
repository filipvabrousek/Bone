//
//  BoneVisionUI.swift
//  Bone library (visionOS)
//
//  Reusable SwiftUI cards for the volumetric hierarchy viewer:
//  - ToolbarCard: loaded-dump info + file picker menu
//  - InfoCard:    detail panel for the tapped node
//
//  Both bind to VisionModel and are typically placed as RealityView
//  attachments (see Bone-vision/ContentView.swift).
//

#if os(visionOS)

import SwiftUI

// MARK: - Floating toolbar

struct ToolbarCard: View {
    var model: VisionModel

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "cube.transparent")
                .font(.title2)

            VStack(alignment: .leading) {
                Text(model.loadedName)
                    .font(.headline)
                    .lineLimit(1)
                if let os = model.osInfo {
                    Text(os)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Menu {
                ForEach(model.availableFiles, id: \.self) { url in
                    Button(url.lastPathComponent) { model.load(url: url) }
                }
                Divider()
                Button("Sample dump") { model.loadSample() }
                Button("Refresh file list") { model.refreshFiles() }
            } label: {
                Label("Dump", systemImage: "doc.text.magnifyingglass")
            }
        }
        .padding(20)
        .frame(minWidth: 380)
        .glassBackgroundEffect()
    }
}

// MARK: - Detail card

struct InfoCard: View {
    var model: VisionModel

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
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "hand.tap")
                        .font(.title)
                    Text("Tap a node for details")
                        .font(.headline)
                }
                .padding(24)
            }
        }
        .glassBackgroundEffect()
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

#endif
