//
//  BoneIvars.swift
//  Bone-27
//
//  An ivar description that cannot crash, for the deep capture (BoneCapture).
//
//  UIKit's private -_ivarDescription describes Swift fields through
//  AttributeGraph's field visitor, which on iOS 27 dereferences a stale pointer
//  inside some SwiftUI objects (EXC_BAD_ACCESS in AGTypeApplyEnumData) – first
//  seen on SwiftUI.HostingScrollView, the UIScrollView behind every ScrollView,
//  then on more SwiftUI classes once a whole window is dumped. So objects whose
//  class chain includes a Swift class are described here instead:
//
//    Objective-C levels (UIScrollView, UIView, …) – every ivar from the runtime,
//      its value read by type encoding: numbers, CG geometry, insets, selectors,
//      and objects as <Class: address> (never their -description).
//    Swift levels (SwiftUI.HostingScrollView, …) – the stored properties from
//      Swift reflection, summarised by type: numbers, strings, geometry and
//      payload-free enums in full, everything else by type name, so no
//      arbitrary description runs.
//
//  Plain Objective-C classes keep UIKit's own -_ivarDescription.
//

#if DEBUG   // Bone is private API: it compiles to nothing outside Debug builds

#if (canImport(UIKit) && !os(watchOS)) || canImport(AppKit)

import CoreGraphics
import Foundation
import ObjectiveC

enum BoneIvars {

    /// A Swift class: mangled ("_TtC…") or module-qualified ("SwiftUI.HostingScrollView").
    static func isSwift(_ cls: AnyClass) -> Bool {
        let name = NSStringFromClass(cls)
        return name.hasPrefix("_Tt") || name.contains(".")
    }

    /// Whether any class in the chain up to NSObject is a Swift class.
    static func hasSwiftLevel(_ object: AnyObject) -> Bool {
        var c: AnyClass? = object_getClass(object)
        while let k = c, k != NSObject.self {
            if isSwift(k) { return true }
            c = class_getSuperclass(k)
        }
        return false
    }

    /// `-_ivarDescription`'s layout: "<Class: 0x…>:" then "in Level:" and one line per field.
    static func describe(_ object: NSObject, maxLength: Int) -> String {
        var out = "<\(NSStringFromClass(type(of: object))): \(address(object))>:\n"
        // Swift reflection, one level per class
        var mirrors: [ObjectIdentifier: Mirror] = [:]
        var m: Mirror? = Mirror(reflecting: object)
        while let mm = m {
            if let cls = mm.subjectType as? AnyClass { mirrors[ObjectIdentifier(cls)] = mm }
            m = mm.superclassMirror
        }
        var c: AnyClass? = object_getClass(object)
        while let k = c, k != NSObject.self, out.count < maxLength {
            out += "in \(NSStringFromClass(k)):\n"
            if isSwift(k), let level = mirrors[ObjectIdentifier(k)] {
                for child in level.children {
                    out += "\t\(child.label ?? "?") (\(typeName(of: child.value))): \(summary(child.value))\n"
                }
            } else {
                var count: UInt32 = 0
                if let list = class_copyIvarList(k, &count) {
                    for i in 0..<Int(count) {
                        let ivar = list[i]
                        let name = ivar_getName(ivar).map { String(cString: $0) } ?? "?"
                        let enc = ivar_getTypeEncoding(ivar).map { String(cString: $0) } ?? ""
                        out += "\t\(name) (\(enc)): \(value(of: ivar, encoding: enc, in: object))\n"
                    }
                    free(list)
                }
            }
            c = class_getSuperclass(k)
        }
        return String(out.prefix(maxLength))
    }

    // MARK: Objective-C ivars

    private static func value(of ivar: Ivar, encoding enc: String, in object: NSObject) -> String {
        let base = UnsafeRawPointer(Unmanaged.passUnretained(object).toOpaque()) + ivar_getOffset(ivar)
        switch enc.first {
        case "@":
            // object_getIvar reads weak ivars through the weak-reference machinery
            guard let o = object_getIvar(object, ivar) as AnyObject? else { return "nil" }
            return "<\(object_getClass(o).map(NSStringFromClass) ?? "?"): \(address(o))>"
        case "#":
            guard let cls = object_getIvar(object, ivar) as AnyObject? else { return "nil" }
            return (cls as? AnyClass).map(NSStringFromClass) ?? "?"
        case ":":
            return base.loadUnaligned(as: Selector?.self).map(NSStringFromSelector) ?? "nil"
        case "c": return "\(base.loadUnaligned(as: Int8.self))"
        case "C": return "\(base.loadUnaligned(as: UInt8.self))"
        case "s": return "\(base.loadUnaligned(as: Int16.self))"
        case "S": return "\(base.loadUnaligned(as: UInt16.self))"
        case "i": return "\(base.loadUnaligned(as: Int32.self))"
        case "I": return "\(base.loadUnaligned(as: UInt32.self))"
        case "l", "q": return "\(base.loadUnaligned(as: Int64.self))"
        case "L", "Q": return "\(base.loadUnaligned(as: UInt64.self))"
        case "f": return "\(base.loadUnaligned(as: Float.self))"
        case "d": return "\(base.loadUnaligned(as: Double.self))"
        case "B": return base.loadUnaligned(as: Bool.self) ? "YES" : "NO"
        case "^", "*":
            let p = base.loadUnaligned(as: UInt.self)
            return p == 0 ? "NULL" : String(format: "0x%lx", p)
        case "{":
            // structs of doubles or floats only (CGPoint, CGSize, CGRect, UIEdgeInsets, CGAffineTransform, …):
            // "{CGRect={CGPoint=dd}{CGSize=dd}}" without the struct names is "dddd"
            // field names may be quoted in the encoding: {CGSize="width"d"height"d}
            let fields = enc.replacingOccurrences(of: #""[^"]*""#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\{[^=}]*="#, with: "", options: .regularExpression)
                .replacingOccurrences(of: "}", with: "")
            if !fields.isEmpty, fields.allSatisfy({ $0 == "d" }) {
                return "{" + (0..<fields.count).map { format(base.loadUnaligned(fromByteOffset: $0 * 8, as: Double.self)) }
                    .joined(separator: ", ") + "}"
            }
            if !fields.isEmpty, fields.allSatisfy({ $0 == "f" }) {
                return "{" + (0..<fields.count).map { format(Double(base.loadUnaligned(fromByteOffset: $0 * 4, as: Float.self))) }
                    .joined(separator: ", ") + "}"
            }
            return "struct"
        default:
            return enc.isEmpty ? "?" : "(\(enc))"
        }
    }

    // MARK: Swift fields

    private static func summary(_ value: Any) -> String {
        let m = Mirror(reflecting: value)
        if m.displayStyle == .optional {
            guard let some = m.children.first?.value else { return "nil" }
            return summary(some)
        }
        switch value {
        case let v as String: return "\"\(v.prefix(80))\""
        case let v as Bool: return v ? "true" : "false"
        case is Int, is Int8, is Int16, is Int32, is Int64, is UInt, is UInt8, is UInt16, is UInt32, is UInt64:
            return "\(value)"
        case let v as Double: return format(v)
        case let v as Float: return format(Double(v))
        case let v as CGFloat: return format(Double(v))
        case let v as CGPoint: return "{\(format(v.x)), \(format(v.y))}"
        case let v as CGSize: return "{\(format(v.width)), \(format(v.height))}"
        case let v as CGRect: return "{{\(format(v.minX)), \(format(v.minY))}, {\(format(v.width)), \(format(v.height))}}"
        default: break
        }
        if m.displayStyle == .class, let o = value as AnyObject? {
            return "<\(NSStringFromClass(type(of: o) as AnyClass)): \(address(o))>"
        }
        if m.displayStyle == .enum {
            // a case without payload prints its name; with one, the case label only
            if m.children.isEmpty { return String(describing: value).prefix(80).description }
            return "." + (m.children.first?.label ?? "?") + "(…)"
        }
        if m.displayStyle == .collection || m.displayStyle == .dictionary || m.displayStyle == .set {
            return "\(m.children.count) elements"
        }
        // a small struct of numbers (EdgeInsets, CGVector, …): its fields
        if m.displayStyle == .struct, (1...6).contains(m.children.count),
           m.children.allSatisfy({ $0.value is Double || $0.value is Float || $0.value is CGFloat || $0.value is Int || $0.value is Bool }) {
            return "{" + m.children.map { "\($0.label ?? "?"): \(summary($0.value))" }.joined(separator: ", ") + "}"
        }
        return m.children.isEmpty ? typeName(of: value) : "{\(m.children.count) fields}"
    }

    private static func typeName(of value: Any) -> String {
        String(describing: type(of: value)).prefix(100).description
    }

    // MARK: Helpers

    private static func address(_ o: AnyObject) -> String {
        String(format: "%p", UInt(bitPattern: Unmanaged.passUnretained(o).toOpaque()))
    }

    private static func format(_ d: Double) -> String {
        guard d.isFinite else { return "\(d)" }
        if d == d.rounded() && abs(d) < 1e15 { return String(Int(d)) }
        var t = String(format: "%.3f", d)                       // 15850.333, 0.5, 1.5 – never 1.585e+04
        while t.hasSuffix("0") { t.removeLast() }
        return t
    }

    private static func format(_ d: CGFloat) -> String { format(Double(d)) }
}

#endif

#endif   // DEBUG
