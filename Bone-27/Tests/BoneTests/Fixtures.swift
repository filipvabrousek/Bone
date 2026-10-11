//
//  Fixtures.swift
//  BoneTests
//
//  Real captures – never hand-written: a fixture that
//  states what we assume the system does would pass while Bone breaks.
//
//    ios-glass.txt     .dumpGlass of the demo's glass button, iOS 27 simulator
//    mac-glass.txt     .dumpGlass of a stock glass button, macOS 27
//    watch-glass.txt   .dumpGlass of a glass button, watchOS 27 simulator
//    watch-tune.txt    .tune's log on watchOS 27 (flat + blurRadius 0, faceOpacity 0.6)
//    ios-brief.txt     .bone(into:) of a List (Text, Button, Toggle, Image), iOS 27 simulator
//    glass-panel.json  what the inspector's Save JSON wrote
//

import Foundation
import Testing

enum Fixture {
    static func text(_ name: String) throws -> String {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    static func data(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    /// `caseName  (inputKey)  = value` lines of a .dumpGlass file, per filter section.
    static func glassLines(_ name: String) throws -> [(filter: String, caseName: String, key: String, value: String)] {
        var filter = ""
        var out: [(String, String, String, String)] = []
        let line = try NSRegularExpression(pattern: #"^\s+(\w+)\s+\((input\w+)\)\s*=\s*(.*)$"#)
        for raw in try text(name).split(separator: "\n").map(String.init) {
            if raw.hasPrefix("===== ["), let name = raw.split(separator: " ").dropFirst(2).first {
                filter = String(name)
            } else if let m = line.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)) {
                func group(_ i: Int) -> String { String(raw[Range(m.range(at: i), in: raw)!]) }
                out.append((filter, group(1), group(2), group(3)))
            }
        }
        return out
    }
}
