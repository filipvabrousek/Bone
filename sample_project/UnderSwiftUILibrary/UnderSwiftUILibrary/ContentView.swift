//
//  ContentView.swift
//  UnderSwiftUILibrary
//
//  Created by Filip Vabroušek on 19.01.2024.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        List {
            Text("Bone")
        }.bone(into: "output.txt", fromRoot: true)
    }
}

#Preview {
    ContentView()
}
