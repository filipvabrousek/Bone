//
//  CommonViews.swift
//  UnderSwiftUILibrary
//
//  Created by Filip Vabroušek on 19.01.2024.
//

import SwiftUI


/*
class Wrapper: UIView {
   /* override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        print("Passing all touches to the next view (if any), in the view stack.")
        return false
    }*/
    
    override func point(inside point: CGPoint, with event: event) -> Bool {
       for subview in subviews {
           if subview.hitTest(convert(point, to: subview), with: event) != nil {
               return true
           }
       }
       return false
   }
} // 13:59:47

*/
struct OnSheetView: View {
    @Environment(\.presentationMode) var presentationMode
    
    
   /* var s: Storagea
    
    init(s: Storagea){ // DI???
        self.s = s
    }*/
    
    @State var idx = 0
    
    var body: some View {
        VStack {
            
        
        Button("Dismiss"){
            presentationMode.wrappedValue.dismiss()
        }.padding()
        
        Spacer()
        
        
        ScrollView {
            
        
            ForEach(/*Storagea.dataSources*/Storagea.dataSources, id: \.name){ item in
                
             /*  VStack {
                    
                    
                    Text(item.name)
                        .foregroundColor(.blue)
                        .bold()
                    
                    Text(item.superclass)
                    */
                
                  /*  DisclosureGroup("A") {
                        VStack(alignment: .leading) {
                            Text(Storagea.spacesArray[idx]).multilineTextAlignment(.leading)
                            Text(item.superclass).multilineTextAlignment(.leading)
                        }
                    }*/
               // }
        }
        }
            
        }.padding()
    }
}






/*
struct BestView: View {
    var items: [InnerItema]
    @State var showSublayerDumpSheet = false
    @State var showDataSources = false
    
    
    @State var aTitle = ""
    @State var global = ""
    @State var aString = String()
    
    
    var body: some View {
        
        ScrollView(.vertical) {
            
            
            if (Storagea.dataSources.count > 0){
                
            
            Button("Show data sources"){
                self.showDataSources.toggle()
            }
            }
            
            
            VStack(alignment: .leading){
                
               
         //   ForEach(items, id:\.id){ itm, idx in
                
                ForEach(Array(items.enumerated()), id: \.offset) { idx, itm in
                  
                
                    Group {
                        
                        
                            /*DisclosureGroup {
                                
                                VStack(alignment: .leading) {
                                    Text(Storagea.spacesArray[idx])
                                    Text(itm.superclass)
                                    
                                    if(itm.sublayersa != nil){
                                        ForEach(itm.sublayersa!, id:\.self){ a in
                                            Text(a.description).foregroundColor(.green)
                                        }
                                    }
                                }
                                
                            } label: {
                                Text(itm.name)
                                    .foregroundColor(itm.color)
                                    .bold()
                            }*/
                        
                        
                        DisclosureGroup {
                            VStack(alignment: .leading) {
                                Text(Storagea.spacesArray[idx]).multilineTextAlignment(.leading)
                                Text(itm.superclass).multilineTextAlignment(.leading)
                                   // .font(.title)
                                
                                
                                Divider()
                                if(itm.sublayersa != nil){
                                    ForEach(itm.sublayersa!, id:\.self){ a in
                                        Text(a.description) // dump(a)
                                            .multilineTextAlignment(.leading)
                                            .foregroundColor(.green)
                                            .onTapGesture {
                                                
                                                
                                                
                                                print("Oh very nice !!!")
                                                print(dump(a))
                                                
                                              //  var e = type(of: a), e is Metatype 23:08:29
                                                
                                                
                                                
                                                aTitle = a.description//"\(type(of: a))"
                                                
                                              dump(a, to: &aString)
                                                showSublayerDumpSheet.toggle()
                                            }.sheet(isPresented: $showSublayerDumpSheet){
                                                ScrollView {
                                                    Text(aTitle)
                                                        .font(.title)
                                                        .multilineTextAlignment(.leading)
                                                        .foregroundColor(.green)
                                                        .padding(.bottom, 20)
                                                        .padding(.top, 20)
                                                        .padding(.leading, 6)
                                                    
                                                    
                                                    Text(aString)
                                                }
                                            }
                                           
                                    }
                                }
                            }.padding()
                                .cornerRadius(6)
                            .border(Color.gray, width: 3)
                         
                            
                               
                            
                        } label: {
                            Text(itm.name)
                                .foregroundColor(Color(uiColor: itm.color))
                                .bold()
                        }
                            
                        
                        
                        // Text(itm.sublayersa.count)
                    }
                      
                   
               
            }
            }
            .sheet(isPresented: $showDataSources) {
             OnSheetView()
            }
        }//.border(Color.orange, width: 3)
        .padding()
        .frame(width: 824 - 10)
       // .frame(width: 824 - 10, height: 600, alignment: .leading)
        
    }
}
*/


struct AGenericView: View {
    var items: [InnerItema] = [InnerItema]()
    @State var idx = -1
    
    var body: some View {
        VStack(alignment: .leading){
            
            
            //   ForEach(items, id:\.id){ itm, idx in
            
         /*   ForEach(Array(items.enumerated()), id: \.offset) { idx, itm in
                Text(Storagea.spacesArray[idx])
                Text(itm.superclass)
                
                if(itm.sublayersa != nil){
                    ForEach(itm.sublayersa!, id:\.self){ a in
                        Text(a.description).foregroundColor(.green)
                    }
                }
                
                
            }*/
            
            
                ForEach(/*Storagea.dataSources*/items, id: \.name){ item in
                   
                 /*  VStack {
                        
                        
                        Text(item.name)
                            .foregroundColor(.blue)
                            .bold()
                        
                        Text(item.superclass)
                        */
                    
                      /*  DisclosureGroup("A") {
                            VStack(alignment: .leading) {
                                Text(Storagea.spacesArray[idx]).multilineTextAlignment(.leading)
                                Text(item.superclass).multilineTextAlignment(.leading)
                              
                                ForEach(item.sublayersa!, id:\.self){ a in
                                    Text(a.description).foregroundColor(.green)
                                }
                            }
                        }.onAppear {
                            idx += 1
                        }*/
                   // }
            }
            
            
        }
    }
}




extension String {
    func coutOut(range: String, indexString: String.SubSequence, addToIndex: Int) -> String {
        var superclass = ""
        if ((self.range(of: range)) != nil){ // "baseClass ="
           let arr = self.split(separator: " ")
           let idx = arr.firstIndex(of: indexString)! // "baseClass"
            superclass = String(arr[idx + addToIndex]) // 2
            
            let r = superclass.map({ String($0) })
            superclass = r.filter {$0 != ";"}.joined()
           // superclass = String(arr[idx + 2])
        }
        
        return superclass
    }
}
