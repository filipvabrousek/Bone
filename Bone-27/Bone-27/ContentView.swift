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
                }
                TuneRow(title: ".tune(.noShadow + .noLensing)") {
                    Button("Liquid"){}.font(.largeTitle).padding(20)
                        .glassEffect()
                        .tune(.noShadow + .noLensing, log: "tune.txt")
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

            /* Luminance probes (.getLuminence) – see captures/lum-*.txt
            VStack(spacing: 24) {
                Button("Hello"){}.getLuminence("lum.txt")

                // Glass over real content, so the backdrop luminance gets measured
                ZStack {
                    Image(uiImage: UIImage(named: "backdrop.jpg") ?? UIImage())
                        .resizable().scaledToFill()
                    Button("Image"){}.buttonStyle(.glass)
                }
                .frame(height: 180).clipped()
                .getLuminence("lum-image.txt", keywords: ["lumin", "vibrant", "glassBackground", "backdrop"], after: 5)

                ZStack {
                    Color.black
                    Button("Dark"){}.buttonStyle(.glass)
                }
                .frame(height: 150)
                .getLuminence("lum-dark.txt", keywords: ["lumin", "vibrant", "glassBackground", "backdrop"], after: 5)

                // Navigation bar glass adapts to the content scrolling under it
                // (adaptive luminance with hysteresis) — unlike a plain button.
                NavigationStack {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 0) {
                                Color.white.frame(height: 600)
                                Color.black.frame(height: 900).id("dark")
                            }
                        }
                        .onAppear {
                            // scroll white -> black under the bar so luminance changes
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                withAnimation(.easeInOut(duration: 1.5)) { proxy.scrollTo("dark", anchor: .top) }
                            }
                        }
                    }
                    .navigationTitle("Toolbar")
                    .toolbar { ToolbarItem { Button("Done"){} } }
                }
                .frame(height: 260)
                .getLuminence("lum-toolbar.txt", keywords: ["lumin", "hysteresis", "adaptive"], after: 6)
            }
            */

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
 
