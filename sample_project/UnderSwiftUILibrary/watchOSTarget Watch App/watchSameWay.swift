//
//  watchSameWay.swift
//  watchOSTarget Watch App
//
//  Created by Filip Vabroušek on 28.01.2024.
//

import SwiftUI
import WatchKit


/*

struct ListInspectablea<Content: View>: View {
    let content: Content
    let name: String
 
    init(name: String, @ViewBuilder content: () -> Content) {
        self.name = name
        self.content = content()
    }
    
    
    
    class MyHostingController: WKHostingController<ContentView> {
        override var body: ContentView {
            return ContentView()
        }
    }
   
    struct All: WKInterfaceObjectRepresentable {
        
        
        var name: String
        var content: Content?
        
        func makeWKInterfaceObject(context: Context) -> some WKInterfaceObject {
            let a = MyHostingController()
            return a.
            
        }
        
        func updateWKInterfaceObject(_ wkInterfaceObject: WKInterfaceObjectType, context: Context) {
            print("A")
        }
        
        /* func makeUIView(context: Context) -> UIView {
         let host = UIHostingController(rootView: self.content)
         host._render(seconds: 1)
         
         DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
         host.view.dumpSubviewsa()
         host.view.addDataSwiftUI(data: Storagea.citems, dataSources: Storagea.dataSources, color: .orange)
         //   host.view.addDataa(data: Storagea.citems, color: UIColor.orange)
         
         var lines = Storagea.formatted.split(whereSeparator: \.isNewline)
         
         
         let os = ProcessInfo().operatingSystemVersion
         
         lines.append("-------------------------")
         lines.append("OS: iOS\(os.majorVersion)")
         let result = lines.joined(separator: "\n")
         
         
         func getDocumentsDirectory() -> URL {
         let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
         return paths[0]
         }
         
         let filename = getDocumentsDirectory().appendingPathComponent(self.name)
         
         do {
         try result.write(to: filename, atomically: true, encoding: String.Encoding.utf8)
         print("WRITTEN TO \(filename)")
         
         //
         //   WRITTEN TO file:///Users/filipvabrousek/Library/Developer/CoreSimulator/Devices/29654C3C-9705-4967-B487-FFDCC979EDFE/data/Containers/Data/Application/BDD84391-A2E3-4D0B-993B-FB20950F9E84/Documents/hello.txt
         ///
         ///
         ///23:18:38
         ///23:18:59 01/11/2023
         
         } catch {
         print("Write failed")
         print(error.localizedDescription)
         }
         print("----------")
         }
         
         return host.view
         }
         
         func updateUIView(_ UIView: UIView, context: Context) {
         print("UPDATE Text!")
         }
         }*/
        
    }
    var body: some View {
        All(name: name, content: content)
    }
}


extension View {
    func dump(into: String) -> some View {
        ListInspectablea(name: into) {
            self
        }
    }
}
*/
