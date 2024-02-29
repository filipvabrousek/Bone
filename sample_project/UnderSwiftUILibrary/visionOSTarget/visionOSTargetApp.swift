//
//  visionOSTargetApp.swift
//  visionOSTarget
//
//  Created by Filip Vabroušek on 19.01.2024.
//

import SwiftUI

@main
struct visionOSTargetApp: App {
    var body: some Scene {
        WindowGroup {
            List {
                Text("Bone")
            }.bone(into: "hello.txt")
        }
    }
}

