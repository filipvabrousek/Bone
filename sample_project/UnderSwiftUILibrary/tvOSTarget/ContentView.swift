//
//  ContentView.swift
//  tvOSTarget
//
//  Created by Filip Vabroušek on 19.01.2024.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
     //  Text("Hello")
        List {Text("Nice")}
            .bone(into: "tv.txt")
    }
}

#Preview {
    ContentView()
}
