//
//  watchOSSpecific.swift
//  watchOSTarget Watch App
//
//  Created by Filip Vabroušek on 28.01.2024.
//

import SwiftUI
import WatchKit


extension View {
    func getDataOverlay(perform action: @escaping () -> [String]) -> some View {
       // return self.modifier(GetDataOverlayModifier(action: action))
        
        return self.modifier(GetNavStack(action: action))
    }
}

struct GetDataOverlayModifier: ViewModifier {
    let action: () -> [String]
    @State private var data: [String] = []
    @State var isHidden =  false
    func body(content: Content) -> some View {
        content
            .overlay(
                VStack {
                    if !data.isEmpty {
                       /* Text("Data Overlay")
                            .font(.title)
                            .padding()
                            .background(Color.white)
                            .cornerRadius(10)
                            .shadow(radius: 5)*/
                        Button(isHidden ? "Show" : "Hide"){
                            isHidden.toggle()
                        }.font(.caption2)
                        
                        if (!isHidden){
                            
                            
                            ScrollView { // 120806 [[data]]
                                VStack(alignment: .leading) { // 12:11:27 !!!! DONE !!!
                                   
                                    
                                    ForEach(data, id: \.self) { item in
                                        Text(item)
                                        // 111847
                                            .padding()
                                        // .padding(.bottom, 20)
                                        //.frame(width: 300, height: 100)
                                        
                                    }
                                }.background(.green.opacity(0.4))
                                    .cornerRadius(10)
                                // 12:09 they blew dam
                                
                                // 115612
                                // I can't tank there
                                // I can't computer there
                                // I can't Houdini there
                                
                            }//.frame(height: 300)
                            
                        }
                       // .padding()
                       // .background(Color.white)
                     //   .cornerRadius(10)
                       // .shadow(radius: 5)
                       // .padding()
                    }
                }.frame(width: 200, height: 200)
                .onAppear {
                    data = action()
                }
            )
    }
}



struct GetNavStack: ViewModifier {
    let action: () -> [String]
    @State private var data: [String] = []
    @State var isHidden =  false
    func body(content: Content) -> some View {
      
        content.onAppear {
            data = action()
        }.overlay { // 153839
            
            
            
            NavigationStack { // 155950 Wow! 13/06
                ZStack {
                   /* content.onAppear {
                        data = action()
                    }*/
                    
                    VStack {
                        if !data.isEmpty {
                            /* Text("Data Overlay")
                             .font(.title)
                             .padding()
                             .background(Color.white)
                             .cornerRadius(10)
                             .shadow(radius: 5)*/
                            /*   Button(isHidden ? "Show" : "Hide"){
                             isHidden.toggle()
                             }.font(.caption2)
                             */
                            if (!isHidden){
                                
                                
                                ScrollView { // 120806 [[data]]
                                    VStack(alignment: .leading) { // 12:11:27 !!!! DONE !!!
                                        
                                        
                                        ForEach(data, id: \.self) { item in
                                            Text(item)
                                            // 111847
                                                .padding()
                                            // .padding(.bottom, 20)
                                            //.frame(width: 300, height: 100)
                                            
                                        }
                                    }.background(.green.opacity(0.4))
                                        .cornerRadius(10)
                                    
                                    // 12:09 they blew dam
                                    
                                    // 115612
                                    // I can't tank there
                                    // I can't computer there
                                    // I can't Houdini there
                                    
                                }//.frame(height: 300)
                                
                            }
                            // .padding()
                            // .background(Color.white)
                            //   .cornerRadius(10)
                            // .shadow(radius: 5)
                            // .padding()
                        }
                    }
                    
                }.toolbar {
                    ToolbarItem(placement: .topBarTrailing) { // 133235
                        /* Button("x"){ // 133430 saw
                         isHidden.toggle()
                         }*/
                        
                        Button {
                            isHidden.toggle()
                        } label: {
                            Image(systemName: "chevron.right.circle.fill")
                        }
                        
                    }
                } // 135025 !!!!
                
            }
            
        }
    }
}

extension View {
    
    
   /* func runOnApp() -> some View {
        return self.onAppearAndThen {
            self.drawData() // 223753
        }
        
        
    }*/
    
    func drawData(name: String) -> some View {
        
    
        
        ZStack {
            
      //  print("HIUGI")
            
           // Text("DATA: \(getUnderData().count)").foregroundStyle(.yellow)
           // self
          
           // ScrollView {
            ForEach(getUnderData(name: name), id: \.self){ l in
                    Text("\(l)").foregroundStyle(.yellow) // 221407
                }
         //   }
            
            
           
            
           
        }
    }
     
    
 
    
    func getUnderData(name: String) -> [String] {
        
        var str = ""
        // 203703
        let ro = WKExtension.shared().visibleInterfaceController//?.presentAlert(withTitle: "A", message: "A", preferredStyle: .actionSheet, actions: [.init(title: "A", style: .default, handler: (String)->())])
        dump(ro, to: &str)
        
        
        let r = Mirror(reflecting: ro)
        print(ro.customMirror)
        print(ro.customMirror.children)
        
       // print(str)
        
     //   print(ro?.value(forKey: "_recursiveDescription"))
        
        // print(str)
        let inputString = str
        let pattern = "\\b[A-Z][a-zA-Z]*View\\b"

        var filteredStrings: [String] = []
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let matches = regex.matches(in: inputString, range: NSRange(inputString.startIndex..., in: inputString))
            
            for match in matches {
                if let range = Range(match.range, in: inputString) {
                    let matchedSubstring = inputString[range]
                    
                    
                    let trw = String(matchedSubstring)
                    
                  //  let forbidden = ["AnyView", "UIView", "GenericView"]
                    let forbidden = [""]
                    if (forbidden.contains(trw) == false) {
                   // if (forbidden.contains(where: { !($0 == trw) }) ){
                        // 205624
                        filteredStrings.append(String(matchedSubstring))
                    }
                }
            }
            
            
            filteredStrings = Array(Set(filteredStrings)) // 21:00:27 OK !!!
        }
        
        
        print("BELOW:")
        print(filteredStrings)
        
        
        
        var lines = filteredStrings //Storagea.formatted.split(whereSeparator: \.isNewline)
        
        
        let os = ProcessInfo().operatingSystemVersion
        
        lines.append("-------------------------")
        lines.append("OS: watchOS\(os.majorVersion)")
        let result = lines.joined(separator: "\n")
      
        
        func getDocumentsDirectory() -> URL {
            let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            return paths[0]
        }
        
        let filename = getDocumentsDirectory().appendingPathComponent(name)

        do {
            try result.write(to: filename, atomically: true, encoding: String.Encoding.utf8)
            print("OUTPUT FILE: \(filename)")
            
        } catch {
            
        }
      //  return filteredStrings
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        return filteredStrings
    }
}



extension View {
    func wbone(name: String) -> some View { // 125433 14/06/23
        self.getDataOverlay {
            // Code to fetch data
            //fetchData()
            self.getUnderData(name: name) // 111530 WOW !!!
        }
    }
}
