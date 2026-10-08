import SwiftUI
import Playgrounds

@main struct MyApp: App {
    var body: some Scene {
        WindowGroup {
           /* Button("Bone"){ // 235715 , 235739 cool!!!
                
            }.bone(into: "output.txt")*/ // Same
            
            /*List {
                Text("WOW")
            }.bone(into: "output.txt")*/ // 001626 UPdateCoalescinCollectionView
            // 01700 ListCollectinViewCellBase new ??? 11/06/26

            // Liquid Glass tuning: same button, three settings, over stripes
            // so the shadow and the lensing (refraction) are easy to see.
            VStack(spacing: 18) {
                TuneRow(title: "default") {
                    Button("Liquid"){}.font(.largeTitle).padding(20)
                        .glassEffect()
                        .dumpGlass("glass-default.txt")                    // all inputs
                }
                TuneRow(title: ".tune(.noShadow + .noLensing)") {
                    Button("Liquid"){}.font(.largeTitle).padding(20)
                        .glassEffect()
                        .tune(.noShadow + .noLensing, log: "tune.txt")
                        .dumpGlass("glass-tuned.txt", only: [.shadowOpacity, .ringShadowOpacity,
                                                             .innerRefractionAmount, .outerRefractionAmount,
                                                             .refractionOpacity, .blurRadius])
                }
                TuneRow(title: "[.blurRadius: 0, .faceOpacity: 0.3, .keyFillHighlightAmount: 1]") {
                    Button("Liquid"){}.font(.largeTitle).padding(20)
                        .glassEffect()
                        .tune([.blurRadius: 0, .faceOpacity: 0.3, .keyFillHighlightAmount: 1])
                }
                TuneRow(title: ".tune(.flat)") {
                    Button("Liquid"){}.font(.largeTitle).padding(20)
                        .glassEffect()
                        .tune(.flat)
                }
            }


            Image("backdrop.jpg")
               // .bone(into: "output.txt")
            
            
        }
    }
}

/// Striped backdrop so refraction and shadow are visible.
struct TuneRow<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                ForEach(0..<24, id: \.self) { i in
                    (i.isMultiple(of: 2) ? Color.black : Color.yellow)
                }
            }
            content
            Text(title).font(.caption2.monospaced()).bold().padding(6)
                .background(.white).frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(height: 150)
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
 
