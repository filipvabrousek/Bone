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
           /* Text("Inspect")
                .dump(into: "hello.txt")*/
            
         /*   Slider(value: .constant(0.3), in: 0...1) {
                  Text("A")
              } .dump(into: "slider.txt")*/
            
         /*   Image("icon")
                
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 100)
                .dump(into: "test.txt")*/
            
           /* Button("A"){
                
            }*/ 
            
            /*Slider(value: .constant(0.3), in: 0...1) {
                Text("A")
            }*/
            
            /*Picker("A",selection: .constant("A")){
               Text("A")
            }.dump(into: "test.txt")*/
            
          /*  Image("icon")
                .resizable()
                .frame(width: 100, height: 100)*/
            
           /* List {
               // ForEach(0...100, id: \.self){ _ in
                  
                Text("Hello") // WolfView shown only with single Text
                
                    
               // Button("A"){}
               
               // }
            }*/
            
          /*  Image("icon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 300)
             */
            
          /*  Label(title: {
                Text("Hello")
            }, icon: {
                Image(systemName: "sun.min.fill")
            })*/
            
            List {Text("A")}
          /*  Image("icon")
                 .resizable()
                 .aspectRatio(contentMode: .fit)
                 .frame(width: 300)*/
                .bone(into: "test.txt")
        }
    }
}
