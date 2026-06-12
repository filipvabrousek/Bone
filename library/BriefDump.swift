//
//  BriefDump.swift
//  Bone-vision
//
//  Parser for the classic Bone brief dump format (output.txt / briefoutput.txt):
//
//      _UIHostingView<List<Never, Text>>:
//       superclass: UIView
//       layer: <CALayer:0x...
//       sublayers: <CALayer:0x...
//
//      ->UIKitPlatformViewHost<...>:
//       superclass: ...
//
//      -->UpdateCoalescingCollectionView:
//       DataSource: SwiftUI.ShadowListDataSource<...>
//      -------------------------
//      OS: iOS:27
//
//  Depth is encoded by the number of leading '-' before '>'.
//

import Foundation

final class DumpNode: Identifiable {
    let id = UUID()
    let name: String
    let depth: Int
    var attributes: [(key: String, value: String)] = []
    var children: [DumpNode] = []
    weak var parent: DumpNode?

    init(name: String, depth: Int) {
        self.name = name
        self.depth = depth
    }

    /// Class name without generic parameters, for compact labels.
    var shortName: String {
        let base = name.prefix(while: { $0 != "<" })
        return base.isEmpty ? name : String(base)
    }

    var subtreeCount: Int {
        1 + children.reduce(0) { $0 + $1.subtreeCount }
    }
}

enum BriefDumpParser {

    static func parse(_ text: String) -> (roots: [DumpNode], os: String?) {
        var roots: [DumpNode] = []
        var stack: [DumpNode] = []
        var os: String?

        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Footer rule "-----------------"
            if trimmed.allSatisfy({ $0 == "-" }) { continue }

            // Trailing metadata
            if trimmed.hasPrefix("OS:") {
                os = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                continue
            }

            // Node line: optional --...-> prefix, class name, trailing ':'
            // with no value after it. Attribute lines always contain ": ".
            if trimmed.hasSuffix(":"), !trimmed.dropLast().contains(": ") {
                var depth = 0
                var rest = Substring(trimmed)
                while rest.first == "-" { depth += 1; rest = rest.dropFirst() }
                if rest.first == ">" { rest = rest.dropFirst() }
                let name = String(rest.dropLast()).trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { continue }

                // Root-level names are class names (uppercase or underscore
                // first char). Guards against stray "contents:" lines.
                if depth == 0, let f = name.first, f.isLowercase { continue }

                let node = DumpNode(name: name, depth: depth)
                while let last = stack.last, last.depth >= depth { stack.removeLast() }
                if let parentNode = stack.last {
                    node.parent = parentNode
                    parentNode.children.append(node)
                } else {
                    roots.append(node)
                }
                stack.append(node)
                continue
            }

            // Attribute line "key: value" attached to the current node
            if let colon = trimmed.firstIndex(of: ":"), let current = stack.last {
                let key = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
                let value = String(trimmed[trimmed.index(after: colon)...])
                    .trimmingCharacters(in: .whitespaces)
                if !key.isEmpty, !value.isEmpty {
                    current.attributes.append((key, value))
                }
            }
        }
        return (roots, os)
    }
}

// MARK: - Serialization (JSON structure + brief text)

/// Codable mirror of DumpNode — tuples aren't Codable, so attributes become
/// an ordered array of key/value pairs.
struct DumpNodeJSON: Codable {
    var name: String
    var depth: Int
    var attributes: [AttributePair]
    var children: [DumpNodeJSON]

    struct AttributePair: Codable {
        var key: String
        var value: String
    }

    init(_ node: DumpNode) {
        name = node.name
        depth = node.depth
        attributes = node.attributes.map { .init(key: $0.key, value: $0.value) }
        children = node.children.map(DumpNodeJSON.init)
    }

    func toNode(parent: DumpNode? = nil) -> DumpNode {
        let node = DumpNode(name: name, depth: depth)
        node.parent = parent
        node.attributes = attributes.map { ($0.key, $0.value) }
        node.children = children.map { $0.toNode(parent: node) }
        return node
    }
}

enum DumpSerializer {

    /// Pretty-printed JSON structure of the view tree.
    static func json(roots: [DumpNode]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(roots.map(DumpNodeJSON.init))
    }

    /// Inverse of `json(roots:)` — used by .bone3DFrom("*.json").
    static func rootsFromJSON(_ data: Data) throws -> [DumpNode] {
        try JSONDecoder().decode([DumpNodeJSON].self, from: data).map { $0.toNode() }
    }

    /// Classic brief dump text — same format BriefDumpParser reads.
    static func briefText(roots: [DumpNode]) -> String {
        var out = ""
        func walk(_ node: DumpNode) {
            out += " \n \n \n"
            if node.depth > 0 {
                out += String(repeating: "-", count: node.depth) + ">"
            }
            out += "\(node.name):\n"
            for attr in node.attributes {
                out += " \(attr.key): \(attr.value) \n"
            }
            node.children.forEach(walk)
        }
        roots.forEach(walk)
        return out
    }
}

// MARK: - Live walker: UIView -> DumpNode (iOS + visionOS)

#if canImport(UIKit)
import UIKit

extension UIView {

    func boneNodeTree(depth: Int = 0) -> DumpNode {
        let node = DumpNode(name: String(describing: type(of: self)), depth: depth)

        if let sup = superclass {
            node.attributes.append(("superclass", String(describing: sup)))
        }
        let layerPtr = Unmanaged.passUnretained(layer).toOpaque()
        node.attributes.append(("layer", "<\(type(of: layer)): \(layerPtr)>"))

        if let subs = layer.sublayers, !subs.isEmpty {
            node.attributes.append(("sublayers",
                subs.map { String(describing: type(of: $0)) }.joined(separator: " / ")))
        }
        if let contents = layer.contents {
            node.attributes.append(("contents",
                String(String(describing: contents).prefix(120))))
        }

        for sub in subviews {
            let child = sub.boneNodeTree(depth: depth + 1)
            child.parent = node
            node.children.append(child)
        }
        return node
    }
}
#endif

// MARK: - Built-in sample (a real dump of `List { Text("WOW") }` on iOS 27)

enum SampleDump {
    static let text = """
    _UIHostingView<List<Never, Text>>:
     superclass: UIView
     layer: <CALayer:0x10788fea0
     sublayers: <CALayer:0x1079f82a0

    ->UIKitPlatformViewHost<ListRepresentable<CollectionViewListDataSource<Never>, SelectionManagerBox<Never>>>:
     superclass: UICorePlatformViewHost<ListRepresentable<CollectionViewListDataSource<Never>,SelectionManagerBox<Never>>>
     layer: <CALayer:0x1079f82a0
     sublayers: <CALayer:0x10788ee20

    -->UpdateCoalescingCollectionView:
     superclass: UICollectionView
     layer: <CALayer:0x10788ee20
     sublayers: <CALayer:0x1079f9500 / <CALayer:0x1079f8f60 / <CALayer:0x1079f8390
     DataSource: SwiftUI.ShadowListDataSource<SwiftUI.CollectionViewListDataSource<Swift.Never>>
    Recorder: SwiftUI.ShadowListUpdateRecorder<SwiftUI.CollectionViewListDataSource<Swift.Never>>
    Base: SwiftUI.CollectionViewListDataSource<Swift.Never>
    Super: SwiftUI.UICollectionViewListCoordinatorBase<SwiftUI.CollectionViewListDataSource<Swift.Never>,

    --->_UICollectionViewListLayoutSectionBackgroundColorDecorationView:
     superclass: UICollectionReusableView
     layer: <CALayer:0x1079f9500

    --->ListCollectionViewCell:
     superclass: ListCollectionViewCellBase<_ViewList_View>
     layer: <CALayer:0x1079f8f60
     sublayers: <CALayer:0x1079f9140 / <CALayer:0x1079f8f90

    ---->_UISystemBackgroundView:
     superclass: UIView
     layer: <CALayer:0x1079f9140
     sublayers: <CALayer:0x1079f9170

    ----->UIView:
     superclass: UIResponder
     layer: <CALayer:0x1079f9170

    ---->_UICollectionViewListCellContentView:
     superclass: UIView
     layer: <CALayer:0x1079f8f90
     sublayers: <CALayer:0x1079f9350

    ----->CellHostingView<ModifiedContent<_ViewList_View, CollectionViewCellModifier>>:
     superclass: UIItemHostingView<ModifiedContent<_ViewList_View,CollectionViewCellModifier>>
     layer: <CALayer:0x1079f9350
     sublayers: <_TtC7SwiftUIP33_863CCF9D49B535DAEB1C7D61BEE53B5914CGDrawingLayer:0x1079f6e80

    --->_UIScrollViewScrollIndicator:
     superclass: UIView
     layer: <CALayer:0x1079f8390
     sublayers: <CALayer:0x1079f83f0

    ---->UIView:
     superclass: UIResponder
     layer: <CALayer:0x1079f83f0
    -------------------------
    OS: iOS:27
    """
}
