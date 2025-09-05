//
//  iOSInspect.swift
//  UnderSwiftUI
//
//  Created by Filip Vabroušek on 03.04.2022.
//

import Foundation
import SwiftUI


#if canImport(UIKit)
import UIKit




class InnerItema {
    var id: UUID
    var name: String
    var color: UIColor
    var superclass: String
    var layer: String
    var sublayersa: [CALayer]?
    var layerArray: [String]?
    var contents: String
   // var sublayersDumps: [String]?
    
    init(name: String, color: UIColor, superclass: String, layer: String, sublayersa: [CALayer]?, layerArray: [String]?, contents: String){
        self.id = UUID()
        self.name = name
        self.color = color
        self.superclass = superclass
        self.layer = layer
        self.sublayersa = sublayersa
        self.layerArray = layerArray
        self.contents = contents
       // self.sublayersDumps = sublayersDumps
    }
}





class Storagea {
    static var items = [String]()
    static var citems = [InnerItema]()
    static var dataSources = [InnerItema]()
    static var formatted = ""
    static var spacesToCitems = ""
    static var spacesArray = [String]()
    static var idx = -1
    static var colors = ["#3498DB", "#FF4500", "#BDB76B", "#DDA0DD", "#FF00FF", "#7B68EE", "#ADFF2F", "#90EE90", "#00FA9A", "#228B22", "#66CDAA", "#20B2AA", "#008080", "#AFEEEE", "#7FFFD4", "#48D1CC"].map {UIColor(hex: $0)} // 14 items
}






#else




class InnerItema {
    var id: UUID
    var name: String
    var color: NSColor
    var superclass: String
    var layer: String
    var sublayersa: [CALayer]?
    var contents: String
   // var sublayersDumps: [String]?
    
    init(name: String, color: NSColor, superclass: String, layer: String, sublayersa: [CALayer]?, contents: String){
        self.id = UUID()
        self.name = name
        self.color = color
        self.superclass = superclass
        self.layer = layer
        self.sublayersa = sublayersa
        self.contents = contents
       // self.sublayersDumps = sublayersDumps
    }
}

extension NSColor {
    
 convenience init(hex: String) {
    let trimHex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    let dropHash = String(trimHex.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
    let hexString = trimHex.starts(with: "#") ? dropHash : trimHex
    let ui64 = UInt64(hexString, radix: 16)
    let value = ui64 != nil ? Int(ui64!) : 0
    // #RRGGBB
    var components = (
        R: CGFloat((value >> 16) & 0xff) / 255,
        G: CGFloat((value >> 08) & 0xff) / 255,
        B: CGFloat((value >> 00) & 0xff) / 255,
        a: CGFloat(1)
    )
    if String(hexString).count == 8 {
        // #RRGGBBAA
        components = (
            R: CGFloat((value >> 24) & 0xff) / 255,
            G: CGFloat((value >> 16) & 0xff) / 255,
            B: CGFloat((value >> 08) & 0xff) / 255,
            a: CGFloat((value >> 00) & 0xff) / 255
        )
    }
    self.init(red: components.R, green: components.G, blue: components.B, alpha: components.a)
}
}



class Storagea {
    static var items = [String]()
    static var citems = [InnerItema]()
    static var dataSources = [InnerItema]()
    static var formatted = ""
    static var spacesToCitems = ""
    static var spacesArray = [String]()
    static var idx = 0
    static var colors = ["#3498DB", "#FF4500", "#BDB76B", "#DDA0DD", "#FF00FF", "#7B68EE", "#ADFF2F", "#90EE90", "#00FA9A", "#228B22", "#66CDAA", "#20B2AA", "#008080", "#AFEEEE", "#7FFFD4", "#48D1CC"].map {NSColor(hex: $0)} // 14 items
}




#endif


