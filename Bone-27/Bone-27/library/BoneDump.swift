//
//  BoneDump.swift
//  Bone-27
//
//  .bone(into:) – the hierarchy dump Bone started as. It hosts the modified
//  view, waits for it to render, then walks the platform views under it:
//  each view's class, superclass, layer, sublayers and contents go to the
//  file (Documents/<name>; ".json" writes BoneCapture's deep dump instead),
//  and every view gets a coloured border plus an overlay listing them.
//
//  The walk's state lives in BoneDumpStore (BoneDumpModel.swift); the deep
//  capture is BoneCapture.swift; watchOS has its own in BoneWatch.swift.
//
//  Created by Filip Vabroušek on 15.06.2022.
//

#if DEBUG   // Bone is private API: it compiles to nothing outside Debug builds

#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import UIKit

extension View {

    /// Dumps the views SwiftUI builds for this view to `Documents/<into>` and shows them in an
    /// overlay. `fromRoot` dumps the window's whole root view controller instead.
    public func bone(into: String, fromRoot: Bool = false) -> some View {
        BoneDumpHost(name: into, fromRoot: fromRoot) { self }
    }
}

struct BoneDumpHost<Content: View>: View {
    let content: Content
    let name: String
    let fromRoot: Bool

    init(name: String, fromRoot: Bool = false, @ViewBuilder content: () -> Content) {
        self.name = name
        self.fromRoot = fromRoot
        self.content = content()
    }

    var body: some View {
        Representable(name: name, fromRoot: fromRoot, content: content)
    }

    struct Representable: UIViewRepresentable {
        var name: String
        var fromRoot: Bool = false
        var content: Content

        func makeUIView(context: Context) -> UIView {
            let container = UIView()
            container.backgroundColor = .clear

            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                      let window = scene.windows.first else {
                    print("BONE: no window found")
                    return
                }

                let host: UIViewController
                if fromRoot {
                    host = window.rootViewController!          // the existing root view hierarchy
                } else {
                    host = UIHostingController(rootView: content)
                    container.addSubview(host.view)
                    host.view.frame = container.bounds
                    host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                }
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()

                // the deep dump (BoneCapture) is taken before the borders and the overlay are added
                var jsonDumpData: Data? = nil
                if name.lowercased().hasSuffix(".json") {
                    jsonDumpData = try? BoneCapture.encodedDump(host: host, swiftUIRoot: content)
                }
                if #available(iOS 27.0, *) {
                    BoneCapture.run(named: name, host: host, swiftUIRoot: content)
                }

                host.view.boneDumpSubviews()
                host.view.boneAddDumpOverlay(items: BoneDumpStore.items, dataSources: BoneDumpStore.dataSources)

                let lines = BoneDumpStore.formatted
                    .split(whereSeparator: \.isNewline)
                    .map { String($0) }
                    + ["-------------------------",
                       "OS: \(UIDevice.current.systemName):\(ProcessInfo().operatingSystemVersion.majorVersion)"]
                let result = lines.joined(separator: "\n")

                do {
                    let filename = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                        .appendingPathComponent(name)
                    if let jsonDumpData {
                        try jsonDumpData.write(to: filename)
                    } else {
                        try result.write(to: filename, atomically: true, encoding: .utf8)   // the brief text dump
                    }
                    print("OUTPUT FILE: \(filename)")
                } catch {
                    print("BONE write failed: \(error.localizedDescription)")
                }

                if #available(iOS 27.0, *) {
                    BoneCapture.writeBrief(result)                 // iOS 27+: also mirrored next to the project
                }
            }
            return container
        }

        func updateUIView(_ uiView: UIView, context: Context) {}
    }
}

extension UIView {

    /// Walks the view tree depth-first: appends each view to BoneDumpStore and outlines it in its colour.
    func boneDumpSubviews(_ depth: Int = 0) {
        BoneDumpStore.idx += 1
        BoneDumpStore.formatted += "\n \n \n"
        for _ in 0..<depth { BoneDumpStore.formatted += "-" }
        if depth > 0 { BoneDumpStore.formatted += ">" }

        let superclass = (self.superclass.map { "\($0)" } ?? "").filter { !$0.isWhitespace }
        BoneDumpStore.formatted += "\(String(describing: type(of: self))):"
        if superclass != "empty" {
            BoneDumpStore.formatted += "\n superclass: \(superclass) \n"
        }
        BoneDumpStore.formatted += "\n layer: \(layer.debugDescription[..<layer.debugDescription.firstIndex(of: ";")!])"

        if let sublayers = layer.sublayers {
            BoneDumpStore.formatted += " \n sublayers: \(sublayers.map { $0.debugDescription[..<$0.debugDescription.firstIndex(of: ";")!] }.joined(separator: " / "))"
        }

        var contents = "empty"
        if let sublayers = layer.sublayers, sublayers[0].contents != nil {
            BoneDumpStore.formatted += " \n contents:"
            for sublayer in sublayers {
                if let ct = BoneDumpText.brackets(in: sublayer.contents.debugDescription) {
                    contents = ct
                    BoneDumpStore.formatted += sublayers.count > 1 ? "\(ct) / " : "\(ct) "
                }
            }
        }

        // a List: what feeds the collection view
        if superclass == "UICollectionView", value(forKey: "_dataSource") != nil {
            let ds: Any? = value(forKey: "_dataSource")            // dumped as an Optional, as it always was
            var text = String()
            dump(ds, to: &text)

            var source = ""
            if text.range(of: "dataSource:") != nil {
                source = BoneDumpText.word(after: "dataSource:", offset: 1, in: text, ifContains: "dataSource:")
            } else if text.range(of: "baseClass =") != nil {
                source = BoneDumpText.word(after: "baseClass", offset: 2, in: text, ifContains: "baseClass =")
            } else if text.range(of: "super:") != nil {
                source = BoneDumpText.word(after: "super:", offset: 1, in: text, ifContains: "super:")
            }
            BoneDumpStore.dataSources.append(.init(name: "DataSource", color: .orange, superclass: source, layer: "none",
                                                   sublayers: [], layerArray: [], contents: ""))
            BoneDumpStore.formatted += "\n DataSource: \(source)"

            for (marker, label) in [("recorder:", "Recorder"), ("base:", "Base"), ("super:", "Super")]
            where text.range(of: marker) != nil {
                let value = BoneDumpText.word(after: Substring(marker), offset: 1, in: text, ifContains: marker)
                BoneDumpStore.dataSources.append(.init(name: label, color: .systemPink, superclass: value, layer: "none",
                                                       sublayers: [], layerArray: [], contents: ""))
                BoneDumpStore.formatted += label == "Super" ? "Super: \(value) \n" : "\(label): \(value)"
            }
        }

        let colored = BoneDumpStore.idx <= BoneDumpStore.colors.count - 1
        if colored {
            BoneDumpStore.items.append(BoneDumpItem(name: String(describing: type(of: self)),
                                                    color: BoneDumpStore.colors[BoneDumpStore.idx],
                                                    superclass: superclass,
                                                    layer: layer.debugDescription,
                                                    sublayers: layer.sublayers,
                                                    layerArray: BoneDumpText.layerInfo(in: layer.debugDescription).layers,
                                                    contents: contents))
        }

        layer.borderWidth = 3.0
        if colored {
            layer.borderColor = BoneDumpStore.colors[BoneDumpStore.idx].cgColor
        }

        for subview in subviews {
            subview.boneDumpSubviews(depth + 1)
        }
    }

    /// The overlay listing the dumped views, with a button that hides it.
    func boneAddDumpOverlay(items: [BoneDumpItem], dataSources: [BoneDumpItem]) {
        let list = UIHostingController(rootView: BoneDumpOverlay(items: items, dataSources: dataSources))

        #if os(visionOS)
        let width: CGFloat = 550
        let height: CGFloat = 600
        #else
        let width = UIScreen.main.bounds.size.width
        let height = UIScreen.main.bounds.height - 120
        #endif

        list.view.frame = CGRect(x: 0, y: 20, width: width, height: height)
        list.view.alpha = 0.7

        let wrapper = BonePassThroughView()
        wrapper.frame = CGRect(x: 0, y: 20, width: width, height: height)

        let toggle = UIHostingController(rootView: Button {
            list.view.isHidden.toggle()
        } label: {
            Text("Toggle overlay")
                .bold()
                .frame(width: 160)
        })
        toggle.view.frame = CGRect(x: 0, y: 0, width: width, height: 20)
        toggle.view.backgroundColor = .clear

        wrapper.addSubview(list.view)
        wrapper.addSubview(toggle.view)
        addSubview(wrapper)
    }
}

/// Takes a touch only where one of its subviews does.
final class BonePassThroughView: UIView {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        subviews.contains { $0.hitTest(convert(point, to: $0), with: event) != nil }
    }
}

struct BoneDumpOverlay: View {
    var items: [BoneDumpItem]
    var dataSources: [BoneDumpItem]

    @State private var showDataSources = false
    @State private var showLegend = false

    var body: some View {
        ScrollView(.vertical) {
            if !dataSources.isEmpty {
                Button {
                    showDataSources.toggle()
                } label: {
                    Text("Show data sources")
                        .frame(width: 160)
                }
                .padding(.bottom, 12)
                .padding(.top, 12)
            }

            Button {
                showLegend.toggle()
            } label: {
                Text("Legend")
                    .frame(width: 160)
            }

            VStack(alignment: .leading) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    BoneDumpRow(item: item)
                }
            }
            .sheet(isPresented: $showDataSources) {
                BoneDumpSourcesSheet(show: $showDataSources, dataSources: dataSources)
                    .padding()
            }
            .sheet(isPresented: $showLegend) {
                BoneDumpLegend(show: $showLegend)
            }
        }
        .padding()
    }
}

struct BoneDumpRow: View {
    var item: BoneDumpItem

    var body: some View {
        DisclosureGroup {
            HStack {
                VStack(alignment: .leading) {
                    Text(item.superclass)
                        .multilineTextAlignment(.leading)

                    Text(item.layer.debugDescription[..<item.layer.debugDescription.firstIndex(of: ";")!].dropFirst(1))
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.orange)
                        .bold()

                    if let sublayers = item.sublayers {
                        ForEach(sublayers, id: \.self) { sublayer in
                            Text(sublayer.description)
                                .multilineTextAlignment(.leading)
                        }
                        .foregroundColor(Color(.green))
                    }

                    Text(item.contents).foregroundStyle(.cyan)
                }
                .padding(.leading, 21)

                Spacer()
            }
        } label: {
            Text(item.name)
                .multilineTextAlignment(.leading)
                .foregroundColor(Color(item.color))
        }
    }
}

struct BoneDumpSourcesSheet: View {
    var show: Binding<Bool>
    var dataSources: [BoneDumpItem]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                Button {
                    show.wrappedValue.toggle()
                } label: {
                    Image(systemName: "xmark")
                        .fontWeight(.black)
                }
                .padding(.bottom)

                ForEach(dataSources, id: \.id) { source in
                    Text(source.name).bold()
                    Text(source.superclass)
                }
            }
            BoneDumpCredits()
        }
    }
}

#elseif canImport(AppKit)

import AppKit
import SwiftUI

extension View {

    /// Dumps the views SwiftUI builds for this view to `Documents/<into>` and lists them beside it.
    public func bone(into: String) -> some View {
        BoneDumpHost(name: into) { self }
    }
}

struct BoneDumpHost<Content: View>: View {
    let content: Content
    let name: String

    init(name: String, @ViewBuilder content: () -> Content) {
        self.name = name
        self.content = content()
    }

    @State private var show = false
    @State private var showLegend = false

    var body: some View {
        ZStack {
            HStack {
                if show {
                    ScrollView {
                        Button("Legend") {
                            showLegend.toggle()
                        }
                        .sheet(isPresented: $showLegend) {
                            BoneDumpLegend(show: $showLegend)
                        }

                        VStack {
                            ForEach(BoneDumpStore.items, id: \.name) { item in
                                DisclosureGroup {
                                    VStack(alignment: .leading) {
                                        Text(item.superclass.trimmingCharacters(in: .whitespacesAndNewlines))
                                            .boneDumpTitle()

                                        Text(item.layer)
                                            .boneDumpTitle()
                                            .foregroundStyle(.orange)

                                        if let sublayers = item.sublayers {
                                            ForEach(sublayers, id: \.name) { sublayer in
                                                Text(sublayer.description)
                                                    .boneDumpTitle()
                                                    .foregroundStyle(.green)
                                            }
                                        }

                                        Text(item.contents)
                                            .boneDumpTitle()
                                            .foregroundStyle(.cyan)
                                    }
                                } label: {
                                    Text(item.name)
                                        .foregroundStyle(Color(cgColor: item.color.cgColor))
                                        .boneDumpTitle()
                                }
                                .padding()
                            }
                        }
                    }
                    .frame(width: 400, height: 800)
                } else {
                    Text("Loading")
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { show = true }
                        }
                        .frame(width: 300, height: 600)
                }

                Representable(name: name, content: content)
            }
        }
    }

    struct Representable: NSViewRepresentable {
        var name: String
        var content: Content?

        func makeNSView(context: Context) -> NSView {
            let host = NSHostingController(rootView: content)
            host._render(seconds: 1)

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                // the deep dump (BoneCapture) is taken before the borders are added
                var jsonDumpData: Data? = nil
                if name.lowercased().hasSuffix(".json") {
                    jsonDumpData = try? BoneCapture.encodedDump(host: host, swiftUIRoot: content as Any)
                }

                host.view.boneDumpSubviews()

                var lines = BoneDumpStore.formatted.split(whereSeparator: \.isNewline)
                lines.append("-------------------------")
                lines.append("OS: iOS\(ProcessInfo().operatingSystemVersion.majorVersion)")
                let result = lines.joined(separator: "\n")

                let filename = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent(name)
                do {
                    if let jsonDumpData {
                        try jsonDumpData.write(to: filename)
                    } else {
                        try result.write(to: filename, atomically: true, encoding: .utf8)   // the brief text dump
                    }
                    print("OUTPUT FILE: \(filename)")
                } catch {
                    print("BONE write failed: \(error.localizedDescription)")
                }
            }
            return host.view
        }

        func updateNSView(_ nsView: NSView, context: Context) {}
    }
}

extension NSView {

    /// Walks the view tree depth-first. Names come from Swift's `dump` of each view –
    /// slow for big SwiftUI hosting views (their environment dumps at length).
    func boneDumpSubviews(_ depth: Int = 0) {
        BoneDumpStore.idx += 1
        BoneDumpStore.formatted += "\n \n \n"
        for _ in 0..<depth { BoneDumpStore.formatted += "-" }
        if depth > 0 { BoneDumpStore.formatted += ">" }

        var dumped = String()
        dump(self, to: &dumped)

        var superclass = "empty"
        if dumped.range(of: "baseClass =") != nil {
            let words = dumped.split(separator: " ")
            superclass = String(words[words.firstIndex(of: "baseClass")! + 2])
        } else if dumped.range(of: "super:") != nil {
            let words = dumped.split(separator: " ")
            superclass = String(words[words.firstIndex(of: "super:")! + 1])
        }

        let layerDump = BoneDumpText.matchBetween(pattern: "layer: <(SwiftUI[^:]*)", in: dumped).first ?? "empty"
        let contentsDump = BoneDumpText.matches(for: "contents = <[a-zA-Z].*", in: dumped).first ?? "empty"
        let sublayersDump = BoneDumpText.matches(for: "sublayers = <[a-zA-Z].*", in: dumped).first ?? "empty"

        if sublayersDump != "empty" {
            BoneDumpStore.formatted += "\n Sublayers: \(sublayersDump) \n"
        }
        BoneDumpStore.formatted += "\(String(describing: type(of: self))): \(superclass)\n"
        if layerDump != "empty" {
            BoneDumpStore.formatted += "\n \(layerDump) \n"
        }
        if contentsDump != "empty" {
            BoneDumpStore.formatted += "\n Contents: \(contentsDump) \n"
        }

        var layerName = layerDump
        if layerName.count > 8 { layerName.removeFirst(8) }

        BoneDumpStore.items.append(BoneDumpItem(name: String(describing: type(of: self)),
                                                color: BoneDumpStore.colors[BoneDumpStore.idx],
                                                superclass: superclass,
                                                layer: layerName,
                                                sublayers: layer?.sublayers,
                                                contents: contentsDump))

        wantsLayer = true
        layer?.borderWidth = 0.5
        layer?.borderColor = BoneDumpStore.colors[BoneDumpStore.idx].cgColor

        if let sublayers = layer?.sublayers {
            BoneDumpStore.formatted += "Sublayers: " + sublayers.map(\.description).joined()
        }

        for subview in subviews {
            subview.boneDumpSubviews(depth + 1)
        }
    }
}

private extension View {
    func boneDumpTitle() -> some View {
        font(.title3)
            .bold()
            .fontDesign(.rounded)
            .multilineTextAlignment(.leading)
    }
}

#endif

#if (canImport(UIKit) && !os(watchOS)) || canImport(AppKit)

/// What the colours in the dump overlay mean.
struct BoneDumpLegend: View {
    @Environment(\.colorScheme) private var scheme
    var show: Binding<Bool>

    var body: some View {
        VStack {
            HStack {
                Button {
                    show.wrappedValue.toggle()
                } label: {
                    Image(systemName: "xmark").fontWeight(.black)
                }
                .padding(.top, 21)
                .padding(.bottom)
                Spacer()
            }
            .padding()

            Spacer()

            VStack {
                row("Superclass", scheme == .dark ? Color.white : Color.black)
                row("Layer", .orange)
                row("Sublayers", .green)
                row("Contents", .cyan)
                Spacer()
            }
            .padding()
            .frame(width: 230, height: 400)

            BoneDumpCredits()
            Spacer()
        }
    }

    private func row(_ label: String, _ color: Color) -> some View {
        HStack {
            Text(label)
                .multilineTextAlignment(.leading)
                .frame(width: 110, alignment: .leading)
            Spacer()
            Circle()
                .fill(color)
                .stroke(.gray, style: .init())
                .frame(width: 30, height: 30)
                .padding(.trailing, 21)
        }
    }
}

struct BoneDumpCredits: View {
    var body: some View {
        VStack {
            Text("Made with ❤️ by").bold()
            Text("Filip Vabrousek").bold().padding(.bottom, 12)
            Link("twitter.com/filipvabrousek", destination: URL(string: "https://twitter.com/filipvabrousek")!)
                .bold()
                .padding(.bottom, 12)
            Link("filipvabrousek.com", destination: URL(string: "http://filipvabrousek.com")!).bold()
        }
        .foregroundStyle(.gray)
        .padding()
    }
}

#endif

#endif   // DEBUG
