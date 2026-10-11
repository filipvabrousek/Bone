//
//  BoneDumpModel.swift
//  Bone-27
//
//  What .bone(into:) collects while it walks the views (BoneDump.swift),
//  and the text helpers it reads class names out of `dump` output with.
//
//  Created by Filip Vabroušek on 03.04.2022.
//

#if DEBUG   // Bone is private API: it compiles to nothing outside Debug builds

#if (canImport(UIKit) && !os(watchOS)) || canImport(AppKit)

import Foundation
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// One view of the dump, as the overlay shows it.
final class BoneDumpItem {
    let id = UUID()
    var name: String
    var color: BonePlatformColor
    var superclass: String
    var layer: String
    var sublayers: [CALayer]?
    var layerArray: [String]?
    var contents: String

    init(name: String, color: BonePlatformColor, superclass: String, layer: String, sublayers: [CALayer]?,
         layerArray: [String]? = nil, contents: String) {
        self.name = name
        self.color = color
        self.superclass = superclass
        self.layer = layer
        self.sublayers = sublayers
        self.layerArray = layerArray
        self.contents = contents
    }
}

/// The walk's state: the text written to the file and the items the overlay lists.
enum BoneDumpStore {
    static var items = [BoneDumpItem]()
    static var dataSources = [BoneDumpItem]()
    static var formatted = ""
    #if canImport(UIKit)
    static var idx = -1
    #else
    static var idx = 0
    #endif
    /// One colour per view, in walk order (views past the 16th get no item and no border on iOS).
    static let colors = ["#3498DB", "#FF4500", "#BDB76B", "#DDA0DD", "#FF00FF", "#7B68EE", "#ADFF2F", "#90EE90",
                         "#00FA9A", "#228B22", "#66CDAA", "#20B2AA", "#008080", "#AFEEEE", "#7FFFD4", "#48D1CC"]
        .map(BoneDumpStore.color(hex:))

    /// `#RRGGBB` or `#RRGGBBAA`.
    static func color(hex: String) -> BonePlatformColor {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines) : trimmed
        let value = Int(UInt64(digits, radix: 16) ?? 0)
        if digits.count == 8 {
            return BonePlatformColor(red: CGFloat((value >> 24) & 0xff) / 255, green: CGFloat((value >> 16) & 0xff) / 255,
                                     blue: CGFloat((value >> 8) & 0xff) / 255, alpha: CGFloat(value & 0xff) / 255)
        }
        return BonePlatformColor(red: CGFloat((value >> 16) & 0xff) / 255, green: CGFloat((value >> 8) & 0xff) / 255,
                                 blue: CGFloat(value & 0xff) / 255, alpha: 1)
    }
}

/// Reads names out of `debugDescription` and `dump` text.
enum BoneDumpText {

    /// The text between the first "(" and the last ")".
    static func brackets(in text: String) -> String? {
        guard let left = text.range(of: "("), let right = text.range(of: ")", options: .backwards),
              left.upperBound <= right.lowerBound else { return nil }
        return String(text[left.upperBound..<right.lowerBound])
    }

    /// SwiftUI layer classes and delegates named in a layer's description.
    static func layerInfo(in text: String) -> (layers: [String], delegates: [String]) {
        func captures(_ pattern: String) -> [String] {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
            return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
                .map { String(text[Range($0.range(at: 1), in: text)!]) }
        }
        return (captures("<(SwiftUI\\.[^0-9]*)"), captures("delegate = ([^0-9]*)"))
    }

    /// In `dump` text containing `marker`: the word `offset` words after `word`, without ";".
    static func word(after word: Substring, offset: Int, in text: String, ifContains marker: String) -> String {
        guard text.range(of: marker) != nil else { return "" }
        let words = text.split(separator: " ")
        let found = String(words[words.firstIndex(of: word)! + offset])
        return found.filter { $0 != ";" }
    }

    /// Every match of `pattern`, minus its first 7 characters ("layer: ") or 10 (anything else).
    static func matches(for pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let drop = pattern.starts(with: "layer:") ? 7 : 10
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .map { String(String(text[Range($0.range, in: text)!]).dropFirst(drop)) }
    }

    /// Every match of `pattern`, whole.
    static func matchBetween(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .map { String(text[Range($0.range, in: text)!]) }
    }
}

#endif

#endif   // DEBUG
