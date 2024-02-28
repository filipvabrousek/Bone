//
//  ContentView.swift
//  watchOSTarget Watch App
//
//  Created by Filip Vabroušek on 28.01.2024.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        List {
            Text("Hello")
        }
        .dumpUI()
    }
}

#Preview {
    ContentView()
}
