import SwiftUI
import Playgrounds

@main struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            ContentView()
                .boneInspector()   // glass debug UI: tap the pink drop – glass, text, any layer, 3D
            #else
            ContentView()
            #endif
            /*
            Text("Hello")
                .tuneLayers([.rotationY: 35,
                             .shadowOpacity: 1,
                             .shadowRadius: 8],
                            where: .text)
                .dumpLayers("layers.txt")
            */
        }
    }
}

struct ContentView: View {
    var body: some View {
       /* Button("Bone"){ // 235715 , 235739 cool!!!
            
        }.bone(into: "output.txt")*/ // Same
        
        /*List {
            Text("WOW")
        }.bone(into: "output.txt")*/ // 001626 UPdateCoalescinCollectionView
        // 01700 ListCollectinViewCellBase new ??? 11/06/26

        // Launch arguments (Edit Scheme ▸ Arguments):
        //   -layers  any SwiftUI view: tune the layers it is drawn into
        //   -probe   which glass inputs change the rendering → captures/glass-probe.txt/.json/.png
        if CommandLine.arguments.contains("-layers") {
            LayersDemo()
        } else if CommandLine.arguments.contains("-probe") {
            ProbeDemo()
        } else {
            GlassDemo()
        }

        Image("backdrop.jpg")
           // .bone(into: "output.txt")
    }
}

/// Liquid Glass tuning: same button, three settings, over stripes so the
/// shadow and the lensing (refraction) are easy to see. The pink drop
/// (.boneInspector) edits any of them live.
struct GlassDemo: View {
    var body: some View {
        VStack(spacing: 18) {
            TuneRow(title: "default") {
                Button("Liquid"){}.font(.largeTitle).padding(20)
                    .glassEffect()
                    .dumpGlass("glass-default.txt")                    // all inputs
                    .dumpGlass("glass-full.txt", full: true)           // + layer tree + shader parameters
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
    }
}

/// Any SwiftUI view: tune the layers it is drawn into.
struct LayersDemo: View {
    var body: some View {
        VStack(spacing: 28) {
            Text("Hello Text").font(.largeTitle.bold()).foregroundStyle(.orange)
                .tuneLayers([.rotationY: 35, .shadowOpacity: 1, .shadowRadius: 8,
                             .shadowColor: .color(.systemPink)], where: .text)
            Button("Bordered") {}.buttonStyle(.borderedProminent)
                .tuneLayers([.filters: .filters([.colorHueRotate(2.2)])])
            Image(systemName: "star.fill").font(.system(size: 60)).foregroundStyle(.yellow)
                .tuneLayers([.rotation: 15, .filters: .filters([.gaussianBlur(1.5)])], where: .shape)
            RoundedRectangle(cornerRadius: 16).fill(.blue.gradient).frame(width: 200, height: 60)
                .tuneLayers([.blendMode: .blend(.difference), .rotationX: 40], where: .gradient)
            Text("outline shows every layer").font(.headline)
                .tuneLayers(.outline, where: .all)
        }
        .dumpLayers("layers.txt")
    }
}

/// Which glass inputs change the rendering? → captures/glass-probe.*
struct ProbeDemo: View {
    var body: some View {
        TuneRow(title: ".probeGlass()") {
            Button("Liquid"){}.font(.largeTitle).padding(20)
                .glassEffect()
                .probeGlass("glass-probe.txt")
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

#Preview {
    ContentView()
}

#Playground {
    _ = 1 + 2
}
 
