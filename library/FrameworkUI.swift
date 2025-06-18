//
//  FrameworkUI.swift
//  UnderSwiftUI
//
//  Created by Filip Vabroušek on 15.06.2022.
//

import SwiftUI
#if canImport(UIKit)
import UIKit


class Storage {
    static var items = [String]()
    static var citems = [InnerItema]()
    static var formatted = ""
    static var idx = 0
    static var colors = ["#3498DB", "#FF4500", "#BDB76B", "#DDA0DD", "#FF00FF", "#7B68EE", "#ADFF2F", "#90EE90", "#00FA9A", "#228B22", "#66CDAA", "#20B2AA", "#008080", "#AFEEEE", "#7FFFD4", "#48D1CC"].map {UIColor(hex: $0)} // 14 items
}




struct Labela: View {
    var itm: InnerItema
    var body: some View {
        
       
        /*    Text(itm.name)
                .bold()
                .foregroundColor(Color(itm.color.cgColor))
        
        
        Text(itm.superclass)
    
    if (itm.layer != "empty"){
        Text(itm.layer)
    }*/
        
        
        #if os(tvOS)
        

            
            
                
                
                VStack(alignment: .leading){
                    
                    Text(itm.name)
                        .multilineTextAlignment(.leading)
                        .foregroundColor(Color(itm.color))
                    
                    
                    Text(itm.superclass)
                        .multilineTextAlignment(.leading)
                     //   .border(Color.green, width: 1.0)
                    
                    Text(itm.layer.debugDescription[..<itm.layer.debugDescription.firstIndex(of: ";")!].dropFirst(1)) //prefix here add
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.orange)
                        .bold()
                       // .border(Color.green, width: 1.0)
                    
                    if let subl = itm.sublayersa {
                        ForEach(subl, id: \.self){ a in
                            Text(a.description)
                                .multilineTextAlignment(.leading)
                                //.border(Color.green, width: 1.0)
                        } .foregroundColor(Color(.green))
                    }
                } //.border(Color.green, width: 1.0)
                    .padding(.leading, 21)
                    .padding(.bottom, 30)
                
             
            
            
        
        
        #else
        DisclosureGroup {
            
            HStack {
                
                
                VStack(alignment: .leading){
                    
                    
                    
                    
                    Text(itm.superclass)
                        .multilineTextAlignment(.leading)
                     //   .border(Color.green, width: 1.0)
                    
                    Text(itm.layer.debugDescription[..<itm.layer.debugDescription.firstIndex(of: ";")!].dropFirst(1)) //prefix here add
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.orange)
                        .bold()
                       // .border(Color.green, width: 1.0)
                    
                    if let subl = itm.sublayersa {
                        ForEach(subl, id: \.self){ a in
                            Text(a.description)
                                .multilineTextAlignment(.leading)
                                //.border(Color.green, width: 1.0)
                        } .foregroundColor(Color(.green))
                    }
                    
                    Text(itm.contents).foregroundStyle(.cyan)
                    
                } //.border(Color.green, width: 1.0)
                    .padding(.leading, 21)
                
                Spacer()
            }
            
        } label: {
            Text(itm.name)
                .multilineTextAlignment(.leading)
                .foregroundColor(Color(itm.color))
        }
        
      
        
        #endif

        
      /*  DisclosureGroup(itm.name) {
            VStack(alignment: .leading) {
               // Text(itm.name).multilineTextAlignment(.leading)
                //Text(itm.layer).multilineTextAlignment(.leading)
                Text(itm.superclass)
                    .multilineTextAlignment(.leading)
                
                Text(itm.layer.debugDescription.oerefix(50))
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.orange)
                    .bold()
                
               /* if (itm.layerArray != nil) {
                    ForEach(itm.layerArray!, id: \.self){ l in
                        Text(l).multilineTextAlignment(.leading)
                    }.foregroundColor(.blue)
                }*/
                
                if let subl = itm.sublayersa {
                    ForEach(subl, id: \.self){ a in
                        Text(a.description)
                    } .foregroundColor(Color(.green))
                }
                
                
                
            }
        }.multilineTextAlignment(.leading)
        .foregroundColor(Color(itm.color))*/
        // Sublayersa ADD tomorrow!
        
      
       
        
        
        
            
    }
    
}

struct BestView: View {
    var items: [InnerItema]
    var dataSources: [InnerItema]
    
    @State var showDataSources = false
    @State var showLegend = false
    
    var body: some View {
        
        ScrollView(.vertical) {
            
            
            if (dataSources.count > 0){
                
            
         
         
                
                Button {
                    self.showDataSources.toggle()
                } label: {
                    Text("Show data sources")
                        .frame(width: 160)
                    
                    //.frame(minWidth: 260, idealWidth: 260, maxWidth: 260)
                }   .padding(.bottom, 12)
                    .padding(.top, 12)
                
                
                
            }
            
           
            
            Button {
                self.showLegend.toggle()
            } label: {
                Text("Legend")
                    .frame(width: 160)
                //.frame(minWidth: 260, idealWidth: 260, maxWidth: 260)
            }

            
            VStack(alignment: .leading){
                
            
         //   ForEach(items, id:\.id){ itm, idx in
                
                ForEach(Array(items.enumerated()), id: \.offset) { idx, itm in
                  
                
                    Group {
                     
                    
              //  Text(Storage.spacesArray[idx])
                Labela(itm: itm)
                    }
                      
                   
                    
                
               
               
            }
            }
            .sheet(isPresented: $showDataSources) {
            // OnSheetView()
                
               
              /*  Button("Close"){
                    showDataSources.toggle()
                }
                
                Text("\(dataSources.map {"\($0.name):\($0.superclass)"}.joined(separator: ", "))")*/
                
                NewOnSheet(show: $showDataSources, dataSources: dataSources)
                    .padding()
            }
            .sheet(isPresented: $showLegend) {
                LegendView(show: $showLegend)
            }
        }//.border(Color.orange, width: 3)
        .padding()
        //.frame(width:400, height: 600, alignment: .leading)
        
    }
}

struct NewOnSheet: View {
    var show: Binding<Bool>
    var dataSources: [InnerItema]
    
    var body: some View {
        ScrollView {
            
            VStack(alignment: .leading){
               /* Button("Close"){
                    show.wrappedValue.toggle()
                }*/
                
                Button {
                    show.wrappedValue.toggle()
                } label: {
                    Image(systemName: "xmark")
                        .fontWeight(.black)
                }.padding(.bottom)
                   
                
                ForEach(dataSources, id: \.id){ val in
                    Text(val.name).bold()
                    Text(val.superclass)//.padding(.bottom, 21)
                }
                
               
                
            }
            
            VStack {
                Text("Made with ❤️ by").bold()
                Text("Filip Vabrousek").bold().padding(.bottom, 12)
                
                Link("twitter.com/filipvabrousek", destination: URL(string: "https://twitter.com/filipvabrousek")!)
                    .bold()
                    .padding(.bottom, 12)
                
                Link("filipvabrousek.com", destination: URL(string: "http://filipvabrousek.com")!).bold()
            }.foregroundStyle(.gray)
            .padding()
            
           // Text("\(dataSources.map {"\($0.name):\($0.superclass)"}.joined(separator: ", "))")
        }
    }
}

struct ListInspectablea<Content: View>: View {
    let content: Content
    let name: String
 
    init(name: String, @ViewBuilder content: () -> Content) {
        self.name = name
        self.content = content()
    }
    
   
    struct All: UIViewRepresentable {
        var name: String
        var content: Content?
        
       func makeUIView(context: Context) -> UIView {
           let host = UIHostingController(rootView: self.content)
           host._render(seconds: 1)
           
           DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
               host.view.dumpSubviewsa()
               host.view.addDataSwiftUI(data: Storagea.citems, dataSources: Storagea.dataSources, color: .orange)
            //   host.view.addDataa(data: Storagea.citems, color: UIColor.orange)
               
               var lines = Storagea.formatted.split(whereSeparator: \.isNewline)
               
               
               let os = ProcessInfo().operatingSystemVersion
               
               lines.append("-------------------------")
               lines.append("OS: \(UIDevice.current.systemName):\(os.majorVersion)")
              // lines.append("OS: iOS\(os.majorVersion)")
               let result = lines.joined(separator: "\n")
               
               
               func getDocumentsDirectory() -> URL {
                   let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
                   return paths[0]
               }
               
               let filename = getDocumentsDirectory().appendingPathComponent(self.name)

               do {
                   try result.write(to: filename, atomically: true, encoding: String.Encoding.utf8)
                   print("OUTPUT FILE: \(filename)")
                   
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
    }
   
    
    var body: some View {
        All(name: name, content: content)
    }
}


extension View {
    func bone(into: String) -> some View {
        ListInspectablea(name: into) {
            self
        }
    }
}


extension String {
    func extractBrackets() -> String? {
        guard let leftRange = self.range(of: "("),
              let rightRange = self.range(of: ")", options: .backwards),
              leftRange.upperBound <= rightRange.lowerBound else {
            return nil
        }
        
        let contentRange = leftRange.upperBound..<rightRange.lowerBound
        return String(self[contentRange])
    }
}


extension String {
    func extractAllInfo() -> ([String], [String]) {
        let layerPattern = "<(SwiftUI\\.[^0-9]*)"
        let delegatePattern = "delegate = ([^0-9]*)"

        let layerRegex = try? NSRegularExpression(pattern: layerPattern)
        let delegateRegex = try? NSRegularExpression(pattern: delegatePattern)

        let layerMatches = layerRegex?.matches(in: self, range: NSRange(self.startIndex..., in: self))
        let delegateMatches = delegateRegex?.matches(in: self, range: NSRange(self.startIndex..., in: self))

        let layers = layerMatches?.map { String(self[Range($0.range(at: 1), in: self)!]) } ?? []
        let delegates = delegateMatches?.map { String(self[Range($0.range(at: 1), in: self)!]) } ?? []

        return (layers, delegates)
    }
    
    /*func extractMacOSLayer() -> ([String], [String]) {
        let layerPattern = "layer: <"
        
       // let layerPattern = "<(SwiftUI\\.[^0-9]*)"
       // let delegatePattern = "delegate = ([^0-9]*)"

        let layerRegex = try? NSRegularExpression(pattern: layerPattern)
       // let delegateRegex = try? NSRegularExpression(pattern: delegatePattern)

        let layerMatches = layerRegex?.matches(in: self, range: NSRange(self.startIndex..., in: self))
       // let delegateMatches = delegateRegex?.matches(in: self, range: NSRange(self.startIndex..., in: self))

        let layers = layerMatches?.map { String(self[Range($0.range(at: 1), in: self)!]) } ?? []
       // let delegates = delegateMatches?.map { String(self[Range($0.range(at: 1), in: self)!]) } ?? []

        return (layers, delegates)
    }*/
}




/*

#if canImport(UIKit)
typealias event = UIEvent?
#else
typealias event = NSEvent?
#endif




#if canImport(UIKit)
typealias color = UIColor
typealias view = UIView
typealias controller = UIHostingController
typealias button = UIButton
*/

class Wrapper: UIView {
   /* override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        print("Passing all touches to the next view (if any), in the view stack.")
        return false
    }*/
    
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
       for subview in subviews {
           if subview.hitTest(convert(point, to: subview), with: event) != nil {
               return true
           }
       }
       return false
   }
} // 13:59:47






extension UIView {
    
    // 22:12:00 UIScreen.main.bound not available in visionOS

    func addDataSwiftUI(data: [InnerItema], dataSources: [InnerItema], color: UIColor){
        let view = BestView(items: data, dataSources: dataSources)
        let r = UIHostingController(rootView:view)
        
        #if os(visionOS)
        let mainw = 550
        let mainh = 600
        #else
        let mainw = UIScreen.main.bounds.size.width
        let mainh = UIScreen.main.bounds.height - 120
        #endif
        
        r.view.frame = CGRect(x: 0, y: 20, width: mainw, height: mainh)
        r.view.alpha = 0.7

        let wrapper = Wrapper()//UIView()
        wrapper.frame = CGRect(x: 0, y: 20, width: mainw, height: mainh)
       
        var isHidden = false
        
        
        let btn = Button {
            r.view.isHidden.toggle()
            isHidden.toggle()
        } label: {
            Text("Toggle overlay")
                .bold()
                .frame(width: 160)
            
            //.frame(minWidth: 260, idealWidth: 260, maxWidth: 260)
        }
        
        let button = UIHostingController(rootView: btn)
        
        /* UIButton(type: .system, primaryAction: UIAction(title: "Show subviews", handler: { _ in
                    print("Button tapped!")
                    r.view.isHidden.toggle()
                }))*/
        
        
        
     //   button.titleLabel?.font = UIFont.boldSystemFont(ofSize: 18)
      //  button.frame = CGRect(x: 0, y: 0, width: mainw, height: 20)
        button.view.frame = CGRect(x: 0, y: 0, width: mainw, height: 20)
        
        #if os(tvOS)
        button.view.frame = CGRect(x: mainw / 2 - 300, y: 0, width: 600, height: 20)
        #endif
                                  
        button.view.backgroundColor = .clear
        
        wrapper.addSubview(r.view)
        wrapper.addSubview(button.view)
        self.addSubview(wrapper)
    }
    
    
    /*   let string = data.map { d in
           idx += 1
           
          
           let sr = NSMutableAttributedString(string: "\(Storagea.spacesArray[idx]) \(d.name) \n [\(d.superclass)] = \(d.layer)")
           sr.setColorForTexta("[\(d.superclass)]", with: d.color)
           sr.setColorForTexta("\(d.layer)", with: UIColor.purple)
           
           print("\n")
           print("MMM")
           print("\(d.name) === [\(d.superclass)]  === \(d.layer)")
           return sr
       } as [NSMutableAttributedString]
       
       */
    func addDataa(data: [InnerItema], color: UIColor){
       
        
        
        
      
        
        let wrapper = Wrapper()//UIView()
        
        let s = UIScrollView()
        
        s.isUserInteractionEnabled = true
        s.contentSize = .init(width: 600, height: 600)
        s.alwaysBounceVertical = true
        
        
        let u = UIView(frame: .init(x: 0, y: 0, width: 824, height: 724))
        u.backgroundColor = .black
        u.alpha = 0.6
        
        
        let button = UIButton(type: .system, primaryAction: UIAction(title: "Show label", handler: { _ in
                    print("Button tapped!")
            s.isHidden.toggle()
            u.isHidden.toggle()
                }))
       
        button.frame = CGRect(x: 0, y: 0, width: 230, height: 20)
        
        
      
        
      
        let stack = UIStackView()
        stack.axis = .vertical
        
        var idx = -1
        
        let string = data.map { d in
            idx += 1
            
           
            let sr = NSMutableAttributedString(string: "\(Storagea.spacesArray[idx]) \(d.name) \n [\(d.superclass)] = \(d.layer)")
            sr.setColorForTexta("[\(d.superclass)]", with: d.color)
            sr.setColorForTexta("\(d.layer)", with: UIColor.purple)
            
            print("\n")
            print("MMM")
            print("\(d.name) === [\(d.superclass)]  === \(d.layer)")
            return sr
        } as [NSMutableAttributedString]
        
        
        for v in string {
            
            if (v.length > 0){
                
            
            let e = UILabel()
            e.numberOfLines = 3
            e.font = UIFont.systemFont(ofSize: 14)
            e.attributedText = v
            e.layer.borderWidth = 1.0
            e.layer.borderColor = UIColor.green.cgColor
            stack.addArrangedSubview(e)
            }
        }
        
        s.frame = .init(x: 20,
                        y: 0,
                        width: 824 - 20,
                        height: 724 - 20)
      
        stack.frame = .init(x: 20,
                            y: 0,
                            width: 824 - 20, // 22:13:25 01/11/23
                            height: 724 - 20)
        s.addSubview(stack)
        
      //  s.translatesAutoresizingMaskIntoConstraints = false
       
        
        
       
        self.addSubview(u)
        
        
        
        
        print("Dumper")
        
        dump(s)
        s.isUserInteractionEnabled = true
       
        
        
        
        wrapper.addSubview(s)
        
        wrapper.addSubview(button)
        wrapper.isUserInteractionEnabled = true
     //   wrapper.pass = true
        
        self.addSubview(wrapper)
        
      
        
      //  print("ER")
       
       
    }
    
    
    func dumpSimple(){
        DispatchQueue.main.async {
            var myClassDumped = String() // 22:14:35 Yes!!!! 01/11/23
          
           // dump(self, to: &myClassDumped)
            
            print("---AAA---")
            print(myClassDumped)
        }
      
    }
    
    func unwrap(any: Any) -> Any {
        let mirror = Mirror(reflecting: any)
        if mirror.displayStyle != .optional {
            return any
        }
        if mirror.children.count == 0 { return NSNull() }
        let (_, some) = mirror.children.first!
        return some
    }

   
    func dumpSubviewsa(_ depth: Int = 0) {
        Storagea.idx += 1
        
        Storagea.formatted += "\n \n \n"
        
        for _ in 0..<depth {
            print("-", terminator: "")
            Storagea.formatted += "-"
            Storagea.spacesToCitems += "-"
        }
        
        if depth > 0 {
            print(">", terminator: "")
            Storagea.formatted += ">"
            Storagea.spacesToCitems += ">"
        }
       
        
        Storagea.spacesArray.append(Storagea.spacesToCitems)
        Storagea.spacesToCitems = ""
         
        var myClassDumped = String() // 22:14:35 Yes!!!! 01/11/23
       // dump(self.subviews, to: &myClassDumped)
        
       // var myClassDumped = String() // 22:14:35 Yes!!!! 01/11/23
    //    dump(self, to: &myClassDumped)
       
        
    //   print("MCD \(dump(self))")
        
      //  print("SCU")
      //  print("\(self.superclass)")
        
        let inString = (self.superclass != nil) ? "\(self.superclass!)" : ""
        print("SCU")
        print(inString)
        
        var superclass = inString
        var layerDump = "empty"
        
        
     /*   if ((myClassDumped.range(of: "baseClass =")) != nil){ // baseClass =
            superclass = myClassDumped.coutOut(range: "baseClass =",
                                               indexString: "baseClass",
                                               addToIndex: 2)
            print("abaseClass = \(superclass)")
            
        } else if((myClassDumped.range(of: "super:")) != nil){
           superclass = myClassDumped.coutOut(range: "super:",
                                              indexString: "super:",
                                              addToIndex: 1)
            
            print("asuper: \(superclass)")
        }*/
        
        
     
        
      
        
        superclass = superclass.filter {!$0.isWhitespace}
        
        
        print("Really??? o")
        print("-\(superclass)-")
       
        
        if (superclass == "UIColorWellVisualStyle"){
            print("DMP")
            dump(superclass)
           // self.setValue(nil, forKey: "_gestureRecognizers")
        }
        
        
        
        
        // self.layer.debugDescription.firstIndex(of: ">")
        
       
        
        Storagea.formatted += "\(String(describing: type(of: self))):"
        
        if (superclass != "empty"){
            Storagea.formatted +=  "\n superclass: \(superclass) \n"
        }
        
        Storagea.formatted += "\n layer: \(self.layer.debugDescription[..<self.layer.debugDescription.firstIndex(of: ";")!])"
     
        if (self.layer.sublayers != nil){
            print("DD \(self.layer.sublayers.map {$0.debugDescription})")
            
        
            Storagea.formatted += " \n sublayers: \(self.layer.sublayers!.map {$0.debugDescription[..<$0.debugDescription.firstIndex(of: ";")!]}.joined(separator: " / "))"//.joined(separator: "/")
          //  Storagea.formatted += self.layer.sublayers!.map {$0.name!}.joined(separator: "/")
        }
        
        
        var contents = "empty"
        
        if (self.layer.sublayers != nil){
            if (self.layer.sublayers![0].contents != nil){
              //  Storagea.formatted += " \n contents: \(self.layer.sublayers!.map {$0.contents != nil ? $0.contents.debugDescription : ""}.joined(separator: " / "))"
                
                
                Storagea.formatted += " \n contents:"
                
                let r = ""
                for layer in self.layer.sublayers! {
                    let ct = layer.contents.debugDescription.extractBrackets()
                  
                    if (ct != nil){
                        
                        
                        print("E \(ct!)")
                        contents = ct!
                        
                        if self.layer.sublayers!.count > 1 {
                            Storagea.formatted +=  "\(ct!) / "
                        } else {
                            Storagea.formatted +=  "\(ct!) "
                        }
                    }
                    
                    
                }
                
               // contents = " \n \(self.layer.sublayers!.map {$0.contents != nil ? $0.contents.debugDescription.extractBrackets()! : ""}.joined(separator: " / "))"
            }
        }
      
      
        
        
        
           
           // SHOW ANY
         //  if (superclass == "UITableView" && self.value(forKey: "_dataSource") != nil){
           if (superclass == "UICollectionView" && self.value(forKey: "_dataSource") != nil){
           
               print("LOVOR")
               print(self)
               
              // dump(self)
               
               let ds = self.value(forKey: "_dataSource")
               
              
                  
               
               print("NOT GOT")
               
               var dsDumpedString = String()
               dump(ds, to: &dsDumpedString)
              
              // print(ds.unsafelyUnwrapped)
               dump(ds.unsafelyUnwrapped)
               
               var sro = ""
               
               if((dsDumpedString.range(of: "dataSource:")) != nil){
                  sro = dsDumpedString.coutOut(range: "dataSource:",
                                                     indexString: "dataSource:",
                                                     addToIndex: 1)
               } else if ((dsDumpedString.range(of: "baseClass =")) != nil){ // baseClass =
                   sro = dsDumpedString.coutOut(range: "baseClass =",
                                                      indexString: "baseClass",
                                                      addToIndex: 2)
                   
               }  else if((dsDumpedString.range(of: "super:")) != nil){
                    sro = dsDumpedString.coutOut(range: "super:",
                                                       indexString: "super:",
                                                       addToIndex: 1)
                 }
               
               
               print("SRO")
               print(sro)
               
               
               // Other items array
             //  Storagea.citems.append(.init(name: "DataSource: \n", color: .orange, superclass: sro, layer: "none"))
             //  Storagea.spacesArray.append("aaa")
               
               
               Storagea.dataSources.append(.init(name: "DataSource", color: .orange, superclass: sro, layer: "none", sublayersa: [], layerArray: [], contents: ""))
               
               Storagea.formatted += "\n DataSource: \(sro)"
               
               
               
               
               
               var recorder = ""
               
               if((dsDumpedString.range(of: "recorder:")) != nil){
                  recorder = dsDumpedString.coutOut(range: "recorder:",
                                                     indexString: "recorder:",
                                                     addToIndex: 1)
                   
                   Storagea.dataSources.append(.init(name: "Recorder", color: .systemPink, superclass: recorder, layer: "none", sublayersa: [],  layerArray: [], contents: ""))
                   
                   Storagea.formatted += "Recorder: \(recorder)"
               }
               
              
               
               
               
               var base = ""
               
               if((dsDumpedString.range(of: "base:")) != nil){
                  base = dsDumpedString.coutOut(range: "base:",
                                                     indexString: "base:",
                                                     addToIndex: 1)
                   Storagea.dataSources.append(.init(name: "Base", color: .systemPink, superclass: base, layer: "none", sublayersa: [],  layerArray: [], contents: ""))
                   Storagea.formatted += "Base: \(base)"
                  
               }
               
               
               
               
               print("***DS")
               print(dsDumpedString)
               
               var supera = ""
               // BaseViewList
               
               if((dsDumpedString.range(of: "super:")) != nil){
                  supera = dsDumpedString.coutOut(range: "super:",
                                                     indexString: "super:",
                                                     addToIndex: 1)
                   Storagea.dataSources.append(.init(name: "Super", color: .systemPink, superclass: supera, layer: "none", sublayersa: [],  layerArray: [], contents: ""))
                   Storagea.formatted += "Super: \(supera) \n"
                  
               }
               
               print("SUREA \(supera)")
           }
        
     
      
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        // superclass instead of self.l

        // Default colour
        
        
        if (Storagea.idx > Storagea.colors.count - 1){
            print("IDX IS \(Storagea.idx)")
        }
        
        if (Storagea.idx <= Storagea.colors.count - 1){
       
            
           /* print("MYSELF*************")
            print(self)
            print("*")
            print(self.layer)
            print("***")
            print(self.layer.sublayers)*/
            
            
            
           /* if ((dsDumpedString.range(of: "baseClass =")) != nil){ // baseClass =
                sro = dsDumpedString.coutOut(range: "baseClass =",
                                                   indexString: "baseClass",
                                                   addToIndex: 2)
                
            }
            */
            
            /*print("EXTRACTED***")
             print(self.layer.debugDescription.extractAllInfo())
            */
            
            print("NAMEDO \(String(describing: type(of: self)))")
            
            
            let subs = self.layer.sublayers.map { dump($0)}
           // print("Subs are \(subs)") // Another sheet will come from bottom
            
            
            let dumpoo = dump(self.layer)
            
        let r = InnerItema(name: String(describing: type(of: self)),
                          color: Storagea.colors[Storagea.idx],
                          superclass: superclass,
                           layer: self.layer.debugDescription,
                          
                           sublayersa: self.layer.sublayers,
                           
                           layerArray: self.layer.debugDescription.extractAllInfo().0, 
                           contents: contents
                          
                         //  sublayersDump: subs
                           )
        Storagea.citems.append(r)
        
        }
       
        
        print("FINITO??")
        print(Storagea.spacesArray)
       
        
        
        
        self.layer.borderWidth = 3.0
        
        if (Storagea.idx <= Storagea.colors.count - 1){
        self.layer.borderColor = Storagea.colors[Storagea.idx].cgColor
        }
        
        for subview in self.subviews {
            subview.dumpSubviewsa(depth + 1)
        }
        
        print("OPOE")
        print(Storagea.formatted)
        // dump fails at visionOS
        
        // _UIScrollViewWolfScrollIndicatorView
        // _UICollectionViewListLayoutSectionBackgroundColorDecorationView LOL 23:15:49
        // 23:15:26 What ???
}
}

#else






class Storage {
    static var items = [String]()
    static var citems = [InnerItema]()
    static var formatted = ""
    static var idx = 0
    static var colors = ["#3498DB", "#FF4500", "#BDB76B", "#DDA0DD", "#FF00FF", "#7B68EE", "#ADFF2F", "#90EE90", "#00FA9A", "#228B22", "#66CDAA", "#20B2AA", "#008080", "#AFEEEE", "#7FFFD4", "#48D1CC"].map {NSColor(hex: $0)} // 14 items
}




struct Labela: View {
    var itm: InnerItema
    var body: some View {
        
       
            Text(itm.name)
                .bold()
                .foregroundColor(Color(itm.color.cgColor))
        
        
        Text(itm.superclass)
    
    if (itm.layer != "empty"){
        Text(itm.layer)
    }
            
    }
    
}


struct BestView: View {
    var items: [InnerItema]
    
    @State var showDataSources = false
    
    var body: some View {
        
        ScrollView(.vertical) {
            
            
           /* if (Storage.dataSources.count > 0){
                
            
            Button("Show data sources"){
                self.showDataSources.toggle()
            }
            }*/
            
            
            VStack(alignment: .leading){
                
            
         //   ForEach(items, id:\.id){ itm, idx in
                
                ForEach(Array(items.enumerated()), id: \.offset) { idx, itm in
                  
                
                    Group {
                     
                    
              //  Text(Storage.spacesArray[idx])
                Labela(itm: itm)
                    }
                      
                   
                    
                
               
               
            }
            }
            .sheet(isPresented: $showDataSources) {
            // OnSheetView()
            }
        }//.border(Color.orange, width: 3)
        .padding()
        //.frame(width:400, height: 600, alignment: .leading)
        
    }
}




struct OnlyButtonWithSheet: View {
    var items: [InnerItema]
    @State var show = false
    
    var body: some View {
        
        
        
            
        
        Button("Hello \(items.count)"){
            self.show.toggle()
        }.sheet(isPresented: $show) {
            Button("End"){
                self.show.toggle()
            }
            BestView(items: items)
        }
            
        
    }
}



extension NSView {

    func addDataSwiftUI(data: [InnerItema], color: NSColor){
        let view = OnlyButtonWithSheet(items: data)//.allowsHitTesting(true)
        
        
        
        let r = NSHostingController(rootView:view)
          r.view.frame = CGRect(x: 0, y: 20, width: 400, height: 400 - 60)
        self.addSubview(r.view)
        
        
        /*  @objc func continueButtonClicked() {
              print("continueButtonClicked")
          } */
          
      /*  let r = NSHostingController(rootView:view)
        r.view.frame = CGRect(x: 0, y: 20, width: 400, height: 400 - 60)
       // r.view.alpha = 0.7

        let wrapper = NSView()
        
        wrapper.frame = CGRect(x: 0, y: 20, width: 400, height: 400 - 60)
        // or use wrapper with touch passing
        /*let button = NSButton(type: .system, primaryAction: NSAction(title: "Show subviews", handler: { _ in
                    print("Button tapped!")
                    r.view.isHidden.toggle()
                }))*/
        
        let button = NSButton(title: "Continue", target: wrapper, action: #selector(self.continueButtonClicked))
      //  button.titleLabel?.font = NSFont.boldSystemFont(ofSize: 18)
        button.frame = CGRect(x: 100, y: 599, width: 110, height: 20)
           
    
        wrapper.addSubview(r.view)
        wrapper.addSubview(button)
        */
        
        
        
    
        
      
    }
}

extension String {
    func matches(for pattern: String) -> [String] {
        do {
            let regex = try NSRegularExpression(pattern: pattern)
            let results = regex.matches(in: self, range: NSRange(self.startIndex..., in: self))
           
            if pattern.starts(with: "layer:"){
                return results.map {
                    String(String(self[Range($0.range, in: self)!]).dropFirst(7))
                }
            } else {
                return results.map {
                    String(String(self[Range($0.range, in: self)!]).dropFirst(10))
                }
            }
           
        } catch let error {
            print("Invalid regex: \(error.localizedDescription)")
            return []
        }
    }
    
    
    func matchBetween(pattern: String) -> [String]{
       var matchedStrings = [String]()
        
        do {
            
            
            let regex = try NSRegularExpression(pattern: pattern)
            let results = regex.matches(in: self,
                                        range: NSRange(self.startIndex..., in: self))
             matchedStrings = results.map {
                String(self[Range($0.range, in: self)!])
            }
            print(matchedStrings)
        } catch {
            
        }
        return matchedStrings
    }
}

extension NSView {
    func addData(data: [InnerItema], color: NSColor){
        let stack = NSTextView()
        
        let string = data.map { d in
            let sr = NSMutableAttributedString(string: "\(d.name) \n [\(d.superclass)]  \n \(d.layer)")
           // sr.setColorForText("[\(d.superclass)]", with: d.color)
           // sr.setColorForText("\(d.layer)", with: NSColor.purple)
            return sr
        } as [NSMutableAttributedString]
        
        for v in string {
            stack.insertText(v)
        }
        
        stack.frame = .init(x: 90, y: 90, width: 600, height: 200)
        self.addSubview(stack)
    }
   
    func addDataOld(data: [InnerItema], color: NSColor){
        var offset = 0
        let stack = NSView()
      
        for val in data {
            offset += 30
            
            let l = NSTextView()//NSText()
            l.font = NSFont.boldSystemFont(ofSize: 12)
            l.frame = CGRect(x: 3, y: offset, width: 300, height: 30)
            l.textColor = NSColor.gray

            let string = NSMutableAttributedString(string: "\(val.name) \n [\(val.superclass)]  \n \(val.layer)")
            
           // string.setColorForText("[\(val.superclass)]", with: val.color)
           // string.setColorForText("\(val.layer)", with: NSColor.purple)
            l.insertText(string)
            stack.addSubview(l)
         
        }
        
      
        stack.frame = CGRect(x: 120, y: 100, width: 1000, height: 1300)
        self.addSubview(stack)
    }
    
    
    
   
    func dumpSubviews(_ depth: Int = 0) {
        Storage.idx += 1
        Storage.formatted += "\n \n \n" // 12:48:04 27/02/24
        
        for _ in 0..<depth {
            print("-", terminator: "")
            Storage.formatted += "-"
        }
        
        if depth > 0 {
            print(">", terminator: "")
            Storage.formatted += ">"
        }
       
        var myClassDumped = String()
        dump(self, to: &myClassDumped)
        
        print(myClassDumped)
        var superclass = "empty"
        var layerDump = "empty"
        
        if ((myClassDumped.range(of: "baseClass =")) != nil){
           let arr = myClassDumped.split(separator: " ")
           let idx = arr.firstIndex(of: "baseClass")!
            superclass = String(arr[idx + 2])
        } else  if((myClassDumped.range(of: "super:")) != nil){
            
            let arr = myClassDumped.split(separator: " ")
            let idx = arr.firstIndex(of: "super:")!
             superclass = String(arr[idx + 1])
        }
        
    // "<(SwiftUI[^:]*)"
        // "layer: <(SwiftUI[^:]*):"
        let er = "\(myClassDumped)".matchBetween(pattern: "layer: <(SwiftUI[^:]*)")//.matches(for: "layer: <[a-zA-Z].*")
        if er.count > 0 {
            print("OE \(er)")
            layerDump = er[0]
        }
        
        var contentsDump = "empty"
        let era = "\(myClassDumped)".matches(for: "contents = <[a-zA-Z].*")
        if era.count > 0 {
            print("POE \(era[0])")
            contentsDump = era[0]
        }
        
        
        var contentsDumpa = "empty"
        let eraa = "\(myClassDumped)".matches(for: "sublayers = <[a-zA-Z].*")
        if eraa.count > 0 {
            print("Why not sub? \(eraa[0])")
            contentsDumpa = eraa[0]
        }
        
        if (contentsDumpa != "empty"){
            Storage.formatted += "\n Sublayers: \(contentsDumpa) \n" // FIX HERE BEFORE PROD
        }
        
        
        Storage.formatted += "\(String(describing: type(of: self))): \(superclass)\n"
        
        if (layerDump != "empty"){
            Storage.formatted += "\n \(layerDump) \n"
        }
        
        
        if (contentsDump != "empty"){
            Storage.formatted += "\n Contents: \(contentsDump) \n" // FIX HERE BEFORE PROD
        }
        
        
        var copy = layerDump
        if (copy.count > 8){
            copy.removeFirst(8)
        }
       
        
        // Default colour
        let r = InnerItema(name: String(describing: type(of: self)),
                          color: Storage.colors[Storage.idx],
                          superclass: superclass,
                           layer: copy,
                           sublayersa: self.layer?.sublayers,
                           contents: contentsDump)
                          // contents: contentsDump.prefix(20).base)
        

        Storage.citems.append(r)
        
        self.wantsLayer = true
        self.layer?.borderWidth = 0.5
        self.layer?.borderColor = Storage.colors[Storage.idx].cgColor
        
        
        if self.layer != nil {
            print("SUBSA")
            if(self.layer!.sublayers != nil){
                var rt = ""
                self.layer!.sublayers!.map {rt += $0.description ?? ""}
                Storage.formatted += "Sublayers: " + rt
            }
             
           
        }
      
        
        for subview in self.subviews {
            subview.dumpSubviews(depth + 1)
        }
}
}

extension NSView {

    func addSwiftUI(data: [InnerItema], color: NSColor){
        let view = OnlyButtonWithSheet(items: data)//.allowsHitTesting(true)
        let r = NSHostingController(rootView:view)
          r.view.frame = CGRect(x: 0, y: 20, width: 400, height: 400 - 60)
        self.addSubview(r.view)
    }
}




struct Tap: View {
    var body: some View {
        Button("Hello"){
            print("Wow")
        }
    }
}


struct ListInspectable<Content: View>: View {
    let content: Content
    let name: String
 
    init(name: String, @ViewBuilder content: () -> Content) {
        self.name = name
        self.content = content()
    }
    
    
    @State var show = false
    @State var showLegend = false
    struct All: NSViewRepresentable {
        var name: String
        var content: Content?
        
        
       func makeNSView(context: Context) -> NSView {
           let host = NSHostingController(rootView: self.content)
           host._render(seconds: 1)
           
           DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
               host.view.dumpSubviews()
               
               
               
               
             
              // let h = NSHostingView(rootView: Tap())//NSHostingView(rootView: OnlyButtonWithSheet(items: Storage.citems))
            //   host.view.addSubview(h)
               
               
             //  h.frame = CGRect(x: 200, y: 200, width: 200, height: 200)
               
               
              // host.view.addDataSwiftUI(data: Storage.citems, color: NSColor.green)
             
               
               // host.view.addData(data: Storage.citems, color: NSColor.green)
               //host.view.addData(data: Storage.citems, color: NSColor.green)//.addData(data: Storage.citems, color: NSColor.orange)
               
               var lines = Storage.formatted.split(whereSeparator: \.isNewline)
               
               
               let os = ProcessInfo().operatingSystemVersion
              
               lines.append("-------------------------")
               lines.append("OS: iOS\(os.majorVersion)")
               let result = lines.joined(separator: "\n")
             
               
               func getDocumentsDirectory() -> URL {
                   let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
                   return paths[0]
               }
               
               let filename = getDocumentsDirectory().appendingPathComponent(self.name)
               print("macOS written to \(filename)")

               do {
                   try result.write(to: filename, atomically: true, encoding: String.Encoding.utf8)
               } catch {
                   print("Write failed")
                   print(error.localizedDescription)
               }
               print("----------")
           }
           
           return host.view
       }
        
        func updateNSView(_ NSView: NSView, context: Context) {
            print("UPDATE Text!")
        }
    }
    
    var body: some View {
        ZStack {
            
           /* Button("ShowMeTest"){
                self.show.toggle()
            }.offset(y: -300)
                .zIndex(-1)
            */
            
            HStack {
             
                
                if self.show {
                    
                    
                  //  Text("A")
                     //   .zIndex(1)
                     //   .overlay {
                            
                            ScrollView {
                                
                                Button("Legend"){ // macOS UI
                                    self.showLegend.toggle()
                                }.sheet(isPresented: $showLegend) {
                                   LegendView(show: $showLegend)
                                }
                                
                                VStack {
                                    
                                  
                                    
                                    ForEach(Storage.citems, id:\.name){ itm in // macOS UI
                                        DisclosureGroup {
                                            
                                            VStack(alignment: .leading){
                                                
                                                
                                                
                                 
                                                Text(itm.superclass.trimmingCharacters(in: .whitespacesAndNewlines))
                                                    .title()
                                                
                                                Text(itm.layer)
                                                    .title()
                                                    .foregroundStyle(.orange)
                                                
                                                
                                                if itm.sublayersa != nil {
                                                    
                                                    
                                                    
                                                    ForEach(itm.sublayersa!, id: \.name){ a in
                                                        Text(a.description)
                                                            .title()
                                                            .foregroundStyle(.green)
                                                    }
                                                }
                                                
                                                Text(itm.contents)
                                                    .title()
                                                    .foregroundStyle(.cyan)
                                                
                                            }
                                            
                                        } label: {
                                            Text(itm.name)
                                                .foregroundStyle(Color(cgColor: itm.color.cgColor))
                                                .title()
                                        }
                                        .padding()
                                        
                                        
                                    }
                                }
                            }//.offset(y: 300)
                            
                           // .offset(x: 300)
                            .frame(width: 400, height: 800)
                      //  }
                } else {
                    Text("Loading")
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0){
                            self.show = true
                        }
                    } .frame(width: 300, height: 600)
                }
                   
                
                All(name: name, content: content)
            }
            
         /*   .sheet(isPresented: .constant(false)) {
                Button("Hide"){
                    self.show.toggle()
                }
               
               
                
                ScrollView {
                    
                    
                    ForEach(Storage.citems, id:\.name){ itm in
                        VStack(alignment: .leading){
                            
                            
                            Text("\(itm.name)").padding()
                            
                            Text(itm.superclass)
                                .multilineTextAlignment(.leading)
                            //   .border(Color.green, width: 1.0)
                            
                            //  Text(itm.layer.debugDescription[..<itm.layer.debugDescription.firstIndex(of: ";")!].dropFirst(1)) //prefix here add
                            Text(itm.layer)
                                .multilineTextAlignment(.leading)
                                .foregroundStyle(.orange)
                                .bold()
                            // .border(Color.green, width: 1.0)
                            
                            if let subl = itm.sublayersa {
                                ForEach(subl, id: \.self){ a in
                                    Text(a.description)
                                        .multilineTextAlignment(.leading)
                                    //.border(Color.green, width: 1.0)
                                } .foregroundColor(Color(.green))
                            }
                        }
                    }
                }
                
                
                
                
               // Text("\(Storage.citems.count)").padding()
            }.offset(y: 300)*/
            
        
        }
    }
}



extension View {
    func title() -> some View {
        
        self
        .font(.title3)
        .bold()
        .fontDesign(.rounded)
        .multilineTextAlignment(.leading)
    }
}



/*
struct BestView: View {
    var items: [InnerItema]
    var body: some View {
        
        ScrollView(.vertical) {
            VStack(alignment: .leading){
                
            
         //   ForEach(items, id:\.id){ itm, idx in
                
                ForEach(Array(items.enumerated()), id: \.offset) { idx, itm in
                  
                
                Text(Storagea.spacesArray[idx])
                Text(itm.name)
                    .bold()
                    .foregroundColor(Color(itm.color.cgColor))
                
                Text(itm.superclass)
                Text(itm.layer)
               
            }
            }
        }.border(Color.orange, width: 3)
        .padding()
        .frame(width: NSScreen.main!.frame.width - 10, height: 600, alignment: .leading)
        
    }
}
*/

/*
extension NSView {
    func addDataSwiftUI(data: [InnerItema], color: NSColor){
        let view = BestView(items: data)
        let r = NSHostingController(rootView:view)
        r.view.frame = CGRect(x: 0, y: 20, width: NSScreen.main!.frame.width, height:  NSScreen.main?.frame.height - 60)
        r.view.alpha = 0.7

        let wrapper = Wrapper()//UIView()
        let button = NSButton(type: .system, primaryAction: NSAction(title: "Show subviews", handler: { _ in
                    print("Button tapped!")
            r.view.isHidden.toggle()
                }))
        button.frame = CGRect(x: 0, y: 0, width: NSScreen.main?.bounds.width, height: 20)
        wrapper.addSubview(r.view)
        wrapper.addSubview(button)
        self.addSubview(wrapper)
    }
}

*/


extension View {
    func bone(into: String) -> some View {
        ListInspectable(name: into) {
            self
        }
    }
}

#endif



struct LegendView: View {
    @Environment(\.colorScheme) var scheme
    var show: Binding<Bool>
    var body: some View {
        
        
        VStack {
        
            HStack {
                
                
                Button {
                    show.wrappedValue.toggle()
                } label: {
                    Image(systemName: "xmark").fontWeight(.black)
                }.padding(.top, 21)
                    .padding(.bottom)
                Spacer()
            }.padding()
            
        Spacer()
            
        VStack {
            
            
            
          
            
            // List {
            HStack{
                Text("Superclass")
                    .multilineTextAlignment(.leading)
                    .frame(width: 110, alignment: .leading)
                
                Spacer()
                Circle()
                    .fill(scheme == .dark ? Color.white : Color.black)
                    .stroke(.gray, style: .init())
                    .frame(width: 30, height: 30)
                    .padding(.trailing, 21)
                
            }//.frame(width: 160)
            
            HStack{
                Text("Layer")
                    .multilineTextAlignment(.leading)
                    .frame(width: 110, alignment: .leading)
                
                Spacer()
                Circle()
                    .fill(Color.orange)
                    .stroke(.gray, style: .init())
                    .frame(width: 30, height: 30)
                    .padding(.trailing, 21)
            }//.frame(width: 160)
            
            
            
            HStack{
                Text("Sublayers")
                    .multilineTextAlignment(.leading)
                    .frame(width: 110, alignment: .leading)
                // .multilineTextAlignment(.leading)
                // .frame(width: 110)
                
                Spacer()
                Circle()
                    .fill(Color.green)
                    .stroke(.gray, style: .init())
                    .frame(width: 30, height: 30)
                    .padding(.trailing, 21)
                
            }
            
            
            HStack{
                Text("Contents")
                    .multilineTextAlignment(.leading)
                    .frame(width: 110, alignment: .leading)
                // .multilineTextAlignment(.leading)
                // .frame(width: 110)
                
                Spacer()
                Circle()
                    .fill(Color.cyan)
                    .stroke(.gray, style: .init())
                    .frame(width: 30, height: 30)
                    .padding(.trailing, 21)
                
            }
            
            Spacer()
            
          
            
            
            // }.allowsHitTesting(false)
        }.padding()
        .frame(width: 230, height: 400)
        
            VStack {
                Text("Made with ❤️ by").bold()
                Text("Filip Vabrousek").bold().padding(.bottom, 12)
                
                Link("twitter.com/filipvabrousek", destination: URL(string: "https://twitter.com/filipvabrousek")!).bold()
                    .padding(.bottom, 12)
                
                Link("filipvabrousek.com", destination: URL(string: "http://filipvabrousek.com")!).bold()
            }.foregroundStyle(.gray)
                .padding()
            
            Spacer()
        
    }
    }
}
