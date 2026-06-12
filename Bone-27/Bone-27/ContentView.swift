import SwiftUI
import Playgrounds

@main struct MyApp: App {
    var body: some Scene {
        WindowGroup {
           /* Button("Bone"){ // 235715 , 235739 cool!!!
                
            }.bone(into: "output.txt")*/ // Same
            
            List {
                Text("WOW")
            }.bone(into: "output.txt") // 001626 UPdateCoalescinCollectionView
            // 01700 ListCollectinViewCellBase new ??? 11/06/26
            
            
            Image("wow.heic")
               // .bone(into: "output.txt")
            
            
        }
    }
}

struct ContentView: View {
    var body: some View {
        Text("Hello, world!")
            .padding()
    }
}

#Preview {
    ContentView()
}

#Playground {
    _ = 1 + 2
}
 
