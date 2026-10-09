//
//  BoneShaderDump.swift
//  Bone-27
//
//  Dumps the shaders' own parameters – what the render server actually feeds
//  the Liquid Glass GPU code – straight from QuartzCore's Metal library:
//
//      Text("…").dumpShaders("shaders.txt")                    // every glass shader
//      Text("…").dumpShaders("blur.txt", matching: "blur")
//      Button("Liquid") {}.glassEffect().dumpGlass("glass-full.txt", full: true)
//
//  QuartzCore ships default.metallib next to its binary. Bone loads it with
//  Metal, lists the functions whose name matches, and reflects each fragment
//  function by building a render pipeline with QuartzCore's own vertex
//  function (the reflection-only API is not implemented in the simulator).
//  The reflection gives every buffer the shader reads – the uniform structs
//  with each field's offset and type – plus its textures. Each field is then
//  matched to the CAFilter input that feeds it where the names line up
//  (`inner_refraction_amount ← innerRefractionAmount`); fields without one are
//  derived by the render server or not reachable from a filter input.
//
//  Research / simulator use only — reads a private system library, never ship it.
//

#if canImport(UIKit)

import Metal
import QuartzCore
import SwiftUI
import UIKit

extension View {

    /// Writes the parameters of QuartzCore's own shaders whose name contains `matching`.
    /// - Parameter reflectAll: reflect every variant, not one per family (slow – a pipeline compile each).
    func dumpShaders(_ fileName: String = "shaders.txt", matching: String = "glass", reflectAll: Bool = false) -> some View {
        onAppear {
            BoneShaderDump.text(matching: matching, reflectAll: reflectAll) { text in
                BoneCapture.writeData(Data(text.utf8), fileName: fileName)
            }
        }
    }
}

enum BoneShaderDump {

    /// Builds the report off the main thread (pipeline compiles take seconds) and
    /// hands it back on the main thread.
    static func text(matching: String = "glass", reflectAll: Bool = false, completion: @escaping (String) -> Void) {
        let labels = inputLabels()
        DispatchQueue.global(qos: .userInitiated).async {
            let text = build(matching: matching, reflectAll: reflectAll, labels: labels)
            DispatchQueue.main.async { completion(text) }
        }
    }

    /// lowercased input name without "input" → how to show it (GlassInput case name, else the CA key).
    private static func inputLabels() -> [String: String] {
        var d: [String: String] = [:]
        for symbol in BoneFilterInputNames.symbols {
            let key = "input" + symbol.dropFirst("kCAFilterInput".count)
            d[String(key.dropFirst("input".count)).lowercased()] = GlassInput(rawValue: key)?.caseName ?? key
        }
        return d
    }

    private nonisolated static func build(matching: String, reflectAll: Bool, labels: [String: String]) -> String {
        let started = Date()
        var t = "BONE · dumpShaders \"\(matching)\"\n"
        guard let url = Bundle(for: CALayer.self).url(forResource: "default", withExtension: "metallib") else {
            return t + "QuartzCore has no default.metallib on this OS.\n"
        }
        guard let device = MTLCreateSystemDefaultDevice() else { return t + "No Metal device.\n" }
        let library: MTLLibrary
        do { library = try device.makeLibrary(URL: url) } catch { return t + "Could not load \(url.path): \(error)\n" }

        let all = library.functionNames.sorted()
        let names = all.filter { $0.lowercased().contains(matching.lowercased()) }
        t += "library: \(url.path)\n"
        t += "device: \(device.name) · \(all.count) functions, \(names.count) match\n"

        let vertices = all.compactMap { n -> MTLFunction? in
            guard let f = library.makeFunction(name: n), f.functionType == .vertex else { return nil }
            return f.functionConstantsDictionary.isEmpty ? f : (try? library.makeFunction(name: n, constantValues: zeroConstants(f)))
        }

        // glass_background_ce_lph → family "glass_background", variant "ce", precision "lph";
        // one representative per family is reflected ("all" + "lpf" when there is one)
        let variants: Set<String> = ["all", "c", "ce", "cr", "e", "minimal", "r", "re"]
        func family(_ name: String) -> String {
            var parts = name.split(separator: "_").map(String.init)
            if let last = parts.last, last == "lpf" || last == "lph" { parts.removeLast() }
            if let last = parts.last, variants.contains(last) { parts.removeLast() }
            return parts.joined(separator: "_")
        }
        var representative: [String: String] = [:]
        for name in names {
            let f = family(name)
            let score = (name.contains("_all_") ? 2 : 0) + (name.hasSuffix("_lpf") ? 1 : 0)
            if let current = representative[f] {
                let currentScore = (current.contains("_all_") ? 2 : 0) + (current.hasSuffix("_lpf") ? 1 : 0)
                if score > currentScore { representative[f] = name }
            } else {
                representative[f] = name
            }
        }

        var structs: [(signature: String, fields: [String], size: Int, users: [String])] = []
        var rows: [String] = []
        var vertexUsed: [String: Int] = [:]
        var preferred: MTLFunction?

        for name in names {
            guard let raw = library.makeFunction(name: name) else { continue }
            let constants = raw.functionConstantsDictionary.values.sorted { $0.index < $1.index }
                .map { "\($0.name)\($0.required ? "" : "?")" }
            var line = "   \(name.padding(toLength: 34, withPad: " ", startingAt: 0)) \(kind(raw.functionType))"
            if !constants.isEmpty { line += "  constants: \(constants.joined(separator: " "))" }

            guard raw.functionType == .fragment else { rows.append(line); continue }
            let rep = representative[family(name)] ?? name
            if !reflectAll, rep != name {
                rows.append(line + "  (variant of \(rep))")
                continue
            }
            let function = raw.functionConstantsDictionary.isEmpty ? raw
                : ((try? library.makeFunction(name: name, constantValues: zeroConstants(raw))) ?? raw)
            guard let (bindings, vertex) = reflect(function, device: device, vertices: vertices, preferred: preferred) else {
                rows.append(line + "  (no vertex function pairs with it – not reflected)")
                continue
            }
            preferred = vertex
            vertexUsed[vertex.name, default: 0] += 1
            var parts: [String] = []
            for b in bindings.sorted(by: { $0.index < $1.index }) {
                if let bb = b as? MTLBufferBinding, let st = bb.bufferStructType {
                    let fields = describe(st, indent: "     ", labels: labels)
                    let signature = fields.joined(separator: "\n")
                    let id: Int
                    if let i = structs.firstIndex(where: { $0.signature == signature }) {
                        id = i
                        structs[i].users.append("\(name).\(b.name)")
                    } else {
                        structs.append((signature, fields, bb.bufferDataSize, ["\(name).\(b.name)"]))
                        id = structs.count - 1
                    }
                    parts.append("\(b.name) (buffer \(b.index) → S\(id + 1))")
                } else {
                    parts.append("\(b.name) (\(bindingKind(b.type)) \(b.index))")
                }
            }
            rows.append(line + "  REFLECTED\n      " + parts.joined(separator: " · "))
        }

        if !vertexUsed.isEmpty {
            t += "reflected via render pipelines with QuartzCore's own vertex function: "
            t += vertexUsed.map { "\($0.key) (\($0.value)×)" }.sorted().joined(separator: ", ") + "\n"
        }
        t += reflectAll ? "every fragment variant reflected\n"
            : "one variant per family reflected (\"all\", float precision); the others are marked – reflectAll: true for each\n"
        t += String(format: "took %.1f s\n", Date().timeIntervalSince(started))
        t += "\n-- functions\n" + rows.joined(separator: "\n") + "\n"
        for (i, s) in structs.enumerated() {
            let users = Set(s.users.map { String($0.split(separator: ".").last ?? "") }).sorted()
            t += "\n-- S\(i + 1): \(s.fields.count) fields, \(s.size) bytes · bound as \(users.joined(separator: ", ")) in \(s.users.joined(separator: ", "))\n"
            t += "     offset  field                                     type      fed by\n"
            t += s.fields.joined(separator: "\n") + "\n"
        }
        return t
    }

    // MARK: Reflection

    private nonisolated static func reflect(_ fragment: MTLFunction, device: MTLDevice, vertices: [MTLFunction],
                                preferred: MTLFunction?) -> ([MTLBinding], MTLFunction)? {
        let order = (preferred.map { [$0] } ?? []) + vertices.filter { $0 !== preferred }
        for v in order {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = v
            d.fragmentFunction = fragment
            d.colorAttachments[0].pixelFormat = .bgra8Unorm
            if let attributes = v.vertexAttributes, !attributes.isEmpty {
                let vd = MTLVertexDescriptor()
                for (i, a) in attributes.enumerated() where a.isActive {
                    vd.attributes[a.attributeIndex].format = vertexFormat(a.attributeType)
                    vd.attributes[a.attributeIndex].bufferIndex = 20 + i
                    vd.layouts[20 + i].stride = 16
                }
                d.vertexDescriptor = vd
            }
            var reflection: MTLRenderPipelineReflection?
            if (try? device.makeRenderPipelineState(descriptor: d, options: [.bindingInfo, .bufferTypeInfo],
                                                    reflection: &reflection)) != nil, let r = reflection {
                return (r.fragmentBindings, v)
            }
        }
        return nil
    }

    private nonisolated static func zeroConstants(_ f: MTLFunction) -> MTLFunctionConstantValues {
        let cv = MTLFunctionConstantValues()
        for c in f.functionConstantsDictionary.values {
            var zero = [UInt8](repeating: 0, count: 16)
            cv.setConstantValue(&zero, type: c.type, index: c.index)
        }
        return cv
    }

    private nonisolated static func vertexFormat(_ t: MTLDataType) -> MTLVertexFormat {
        switch t {
        case .float: return .float
        case .float2: return .float2
        case .float3: return .float3
        case .half: return .half
        case .half2: return .half2
        case .half3: return .half3
        case .half4: return .half4
        case .uchar4: return .uchar4
        case .char4: return .char4
        case .ushort2: return .ushort2
        case .short2: return .short2
        case .int: return .int
        case .uint: return .uint
        case .int2: return .int2
        case .uint2: return .uint2
        default: return .float4
        }
    }

    // MARK: Formatting

    private nonisolated static func describe(_ s: MTLStructType, indent: String, prefix: String = "", base: Int = 0,
                                             labels: [String: String]) -> [String] {
        var out: [String] = []
        for m in s.members {
            let name = prefix + m.name
            if m.dataType == .struct, let inner = m.structType() {
                out += describe(inner, indent: indent, prefix: name + ".", base: base + m.offset, labels: labels)
                continue
            }
            var type = typeName(m.dataType)
            if m.dataType == .array, let a = m.arrayType() { type = "\(typeName(a.elementType))[\(a.arrayLength)]" }
            let offset = String(base + m.offset).padding(toLength: 7, withPad: " ", startingAt: 0)
            out.append(indent + offset + " " + name.padding(toLength: 41, withPad: " ", startingAt: 0)
                       + " " + type.padding(toLength: 9, withPad: " ", startingAt: 0) + " " + feeder(m.name, labels: labels))
        }
        return out
    }

    /// The CAFilter input that sets a uniform field, where the names line up.
    /// Exact: `inner_refraction_amount ← innerRefractionAmount`; inverse: `*_inv_height ← 1 / *Height`;
    /// derived: `face_cm0 ← faceColorMatrix{Black, FillColor, …}` (computed from several inputs).
    /// Fields whose input has a different name – each confirmed with a targeted probe on iOS 27
    /// (conditions set first, then the input varied; pixels changed around a glass button).
    private nonisolated static let probedPairs: [String: (input: String, evidence: String)] = [
        "clamp_limit": ("clamp", "probed: face over-bright → clamp 0.3 changes 74 k px, ≈1.07 (default) ~0"),
        "preserve_hue": ("clamppreservehue", "probed: over-bright + clamp 0.6 → 73 k px"),
        "shadow_contribution": ("shadowvibrancycontribution", "probed: strong shadow → 10 changes 39 k px"),
        "sdr_white_value": ("sdrholdingtonewhite", "probed: only with sdrHoldingToneEnabled = 1 → 73 k px"),
        "holding_tone_opacity": ("sdrholdingtoneenabled", "likely: no effect alone, switches sdrHoldingToneWhite on"),
    ]

    private nonisolated static func feeder(_ field: String, labels: [String: String]) -> String {
        if let pair = probedPairs[field], let label = labels[pair.input] { return "← \(label)  (\(pair.evidence))" }
        let aliases = ["alpha": "opacity", "dist": "distance", "cm": "colormatrix", "dir": "angle"]
        var inverse = false
        var tokens: [String] = []
        for raw in field.split(separator: "_").map(String.init) {
            if raw == "inv" { inverse = true; continue }
            let letters = String(raw.prefix { !$0.isNumber }), digits = String(raw.drop { !$0.isNumber })
            tokens.append((aliases[letters] ?? letters) + digits)        // blur_alpha0 → opacity0
        }
        var candidates = [tokens.joined()]
        if tokens.first == "edge" { candidates.append(tokens.dropFirst().joined()) }     // edge_bleed_* → bleed*
        let direction = field.hasSuffix("_dir") ? " (as a direction)" : ""
        for c in candidates.map({ $0.lowercased() }) {
            if let label = labels[c] { return (inverse ? "← 1 / " : "← ") + label + direction }
        }
        guard !inverse else { return "–" }
        // derived from several inputs that share the name (face_cm0 → faceColorMatrix…)
        for c in candidates.map({ $0.lowercased().trimmingCharacters(in: .decimalDigits) }) where c.count > 6 {
            let matches = labels.keys.filter { $0.hasPrefix(c) }.sorted()
            if matches.count == 1 { return "← " + labels[matches[0]]! + direction }
            if matches.count > 1 {
                let names = matches.map { labels[$0]! }
                let stem = names.reduce(names[0]) { String($0.commonPrefix(with: $1)) }
                let rest = names.map { String($0.dropFirst(stem.count)) }.joined(separator: ", ")
                return "← \(stem){\(rest)} (derived)"
            }
        }
        return "–"
    }

    private nonisolated static func kind(_ t: MTLFunctionType) -> String {
        switch t {
        case .vertex: return "vertex"
        case .fragment: return "fragment"
        case .kernel: return "kernel"
        default: return "type \(t.rawValue)"
        }
    }

    private nonisolated static func bindingKind(_ t: MTLBindingType) -> String {
        switch t {
        case .buffer: return "buffer"
        case .texture: return "texture"
        case .sampler: return "sampler"
        case .threadgroupMemory: return "threadgroup"
        default: return "binding \(t.rawValue)"
        }
    }

    private nonisolated static func typeName(_ t: MTLDataType) -> String {
        switch t {
        case .float: return "float"
        case .float2: return "float2"
        case .float3: return "float3"
        case .float4: return "float4"
        case .float2x2: return "float2x2"
        case .float3x3: return "float3x3"
        case .float4x4: return "float4x4"
        case .half: return "half"
        case .half2: return "half2"
        case .half3: return "half3"
        case .half4: return "half4"
        case .int: return "int"
        case .int2: return "int2"
        case .int4: return "int4"
        case .uint: return "uint"
        case .uint2: return "uint2"
        case .uint4: return "uint4"
        case .short: return "short"
        case .ushort: return "ushort"
        case .char: return "char"
        case .uchar: return "uchar"
        case .bool: return "bool"
        case .struct: return "struct"
        case .array: return "array"
        default: return "type \(t.rawValue)"
        }
    }
}

#endif
