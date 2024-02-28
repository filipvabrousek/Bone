//
//  Extensions.swift
//  UnderSwiftUI
//
//  Created by Filip Vabroušek on 15.06.2022.
//

#if canImport(UIKit)
import UIKit
#endif


#if canImport(UIKit)
extension UIColor {
    
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


extension NSMutableAttributedString{
// If no text is send, then the style will be applied to full text
func setColorForTexta(_ textToFind: String?, with color: UIColor) {

    let range:NSRange?
    if let text = textToFind{
        range = self.mutableString.range(of: text, options: .caseInsensitive)
    }else{
        range = NSMakeRange(0, self.length)
    }
    if range!.location != NSNotFound {
        addAttribute(NSAttributedString.Key.foregroundColor, value: color, range: range!)
    }
}
}
#endif
