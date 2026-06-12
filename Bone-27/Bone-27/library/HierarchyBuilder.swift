//
//  HierarchyBuilder.swift
//  Bone-vision
//
//  RealityKit entity factory for the 3D hierarchy: a colored slab per view
//  node (tappable, hover-highlighted) with a floating label, plus thin
//  connector struts between parent and child.
//

#if os(visionOS)

import SwiftUI
import RealityKit
import UIKit

enum HierarchyBuilder {

    /// Builds the full 3D tree for a set of dump roots: tidy-tree layout
    /// (leaves get sequential x slots, parents center over children, depth
    /// runs downward with a slight forward z-offset), connector struts,
    /// and a registry mapping entity names (node UUIDs) back to nodes.
    /// `fit` is the bounding box (in meters) the tree is scaled into.
    static func buildTree(
        roots: [DumpNode],
        fit: SIMD3<Float>
    ) -> (container: Entity, registry: [String: (node: DumpNode, entity: ModelEntity)]) {

        let container = Entity()
        var registry: [String: (node: DumpNode, entity: ModelEntity)] = [:]
        guard !roots.isEmpty else { return (container, registry) }

        var nextLeafX: Float = 0
        var positions: [UUID: SIMD3<Float>] = [:]

        func layout(_ node: DumpNode) -> Float {
            // Flat plane (z = 0): single-child chains form a perfectly
            // straight vertical line; siblings spread along x only.
            let y = -Float(node.depth) * 0.17
            let x: Float
            if node.children.isEmpty {
                x = nextLeafX
                nextLeafX += 0.34
            } else {
                let xs = node.children.map { layout($0) }
                x = (xs.min()! + xs.max()!) / 2
            }
            positions[node.id] = [x, y, 0]
            return x
        }
        roots.forEach { _ = layout($0) }

        func place(_ node: DumpNode) {
            let pos = positions[node.id]!
            let entity = nodeEntity(for: node)
            entity.position = pos
            container.addChild(entity)
            registry[node.id.uuidString] = (node, entity)

            for child in node.children {
                container.addChild(connection(from: pos, to: positions[child.id]!))
                place(child)
            }
        }
        roots.forEach(place)

        // Center and scale to fit.
        let bounds = container.visualBounds(relativeTo: nil)
        let scale = min(1,
                        fit.x / max(bounds.extents.x, 0.001),
                        fit.y / max(bounds.extents.y, 0.001))
        container.scale = .init(repeating: scale)
        container.position = -bounds.center * scale
        return (container, registry)
    }

    /// Depth-based color, matching Bone's colorful-borders spirit.
    static func color(forDepth depth: Int) -> UIColor {
        UIColor(hue: CGFloat(depth % 12) / 12.0,
                saturation: 0.68,
                brightness: 0.95,
                alpha: 1)
    }

    /// One tappable slab + label for a dump node.
    /// The entity name carries the node's UUID for hit-test lookup.
    static func nodeEntity(for node: DumpNode) -> ModelEntity {
        let mesh = MeshResource.generateBox(
            width: 0.155, height: 0.05, depth: 0.014, cornerRadius: 0.008)
        let material = SimpleMaterial(
            color: color(forDepth: node.depth), isMetallic: false)
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = node.id.uuidString

        // Interactivity — InputTarget + collision on the SAME entity is what
        // makes it tappable; HoverEffect adds the look-at highlight.
        entity.components.set(InputTargetComponent(allowedInputTypes: .all))
        entity.components.set(HoverEffectComponent())
        entity.components.set(CollisionComponent(
            shapes: [.generateBox(width: 0.165, height: 0.06, depth: 0.03)],
            mode: .trigger,
            filter: .default
        ))

        // Label above the slab
        let label = labelEntity(text: truncated(node.shortName, to: 22))
        label.position = [0, 0.038, 0.01]
        entity.addChild(label)

        return entity
    }

    /// Centered white text entity.
    static func labelEntity(text: String) -> Entity {
        let mesh = MeshResource.generateText(
            text,
            extrusionDepth: 0.001,
            font: .systemFont(ofSize: 0.02, weight: .semibold),
            containerFrame: .zero,
            alignment: .center,
            lineBreakMode: .byTruncatingTail)
        let model = ModelEntity(mesh: mesh,
                                materials: [UnlitMaterial(color: .white)])
        // generateText anchors at the baseline's left edge — recenter.
        let bounds = model.visualBounds(relativeTo: nil)
        let holder = Entity()
        model.position = [-bounds.center.x, 0, 0]
        holder.addChild(model)
        return holder
    }

    /// Thin strut connecting a parent slab to a child slab.
    static func connection(from a: SIMD3<Float>, to b: SIMD3<Float>) -> ModelEntity {
        let delta = b - a
        let length = simd_length(delta)
        guard length > 0.0001 else { return ModelEntity() }

        let mesh = MeshResource.generateBox(width: 0.003, height: 0.003, depth: length)
        let material = UnlitMaterial(color: UIColor.white.withAlphaComponent(0.35))
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.position = (a + b) / 2
        entity.orientation = simd_quatf(from: [0, 0, 1], to: simd_normalize(delta))
        return entity
    }

    private static func truncated(_ s: String, to max: Int) -> String {
        s.count <= max ? s : String(s.prefix(max - 1)) + "…"
    }
}

#endif
