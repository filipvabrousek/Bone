//
//  ContentView.swift
//  macOSTarget
//
//  Created by Filip Vabroušek on 19.01.2024.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
       /* Button("A"){
            print("A")
        }*/
        
       // List { Text("A")}//.frame(width: 200, height: 200)
    
        List { Text("A")}.frame(width: 200, height: 200)
      /*  Image("icon")
        .resizable()
            .aspectRatio(contentMode: .fit)
       .frame(width: 200)*/
        
       /* Image("icon")
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(width: 200)*/
        .bone(into: "hello.txt")
            //.dumpa(into: "hello.txt")
        
     
    }
}

#Preview {
    ContentView()
}
