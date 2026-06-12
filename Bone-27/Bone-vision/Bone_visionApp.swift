//
//  Bone_visionApp.swift
//  Bone-vision
//
//  Created by Filip Vabroušek on 12/6/26.
//
//  All Bone machinery lives in the shared library folder — the app is just
//  two volumetric windows demonstrating the modifiers:
//
//    .bone3D()          live 3D hierarchy of the wrapped view
//    .bone3DFrom(_:)    3D graph parsed from a brief dump file
//
//  visionOS launches the first scene; open the second one with
//  openWindow(id: "bone3DFromFile") or swap the order to change the default.
//

import SwiftUI

@main
struct Bone_visionApp: App {
    var body: some Scene {
        WindowGroup {
            List {
                Text("Hello")
            }.bone3D(into: "ssu.json")
           
            /*
             static func privateString(_ obj: NSObject, _ selectorName: String) -> String? {
                 let sel = NSSelectorFromString(selectorName)
                 guard obj.responds(to: sel) else { return nil }
                 return obj.perform(sel)?.takeUnretainedValue() as? String
             }
             */
           // .bone3DFrom("briefoutput.txt")
          
           
            /*
            Button("Wow"){
                
            }
            .bone3D() // 3D representation of this view's internals
             */
            
            
          /*  Button("Wow"){
                print("Wow")
            }.bone3DFrom("briefoutput.txt")*/
            
           // Text("A").bone3DFrom("briefoutput.txt")//.bone3D()
            
        }
        .windowStyle(.volumetric)
        .defaultSize(width: 1.6, height: 1.2, depth: 0.7, in: .meters)

      /* WindowGroup(id: "bone3DFromFile") {
            List {
                Text("Hello")
            }
            .bone3DFrom("briefoutput.txt") // 3D graph from a dump file
        }
        .windowStyle(.volumetric)
        .defaultSize(width: 1.6, height: 1.2, depth: 0.7, in: .meters)*/
    }
}
