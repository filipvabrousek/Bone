//
//  BoneGlassPanelViews.swift
//  Bone-27
//
//  The inspector's views: the drop button, the pick hint, the glass card with
//  one row per input, and the 4×5 colour-matrix editor. The layer card is in
//  BoneLayerPanel.swift, the timeline bars in BoneTimeline.swift and
//  BoneMacTimeline.swift.
//

#if DEBUG   // Bone is private API: it compiles to nothing outside Debug builds

#if (canImport(UIKit) && !os(watchOS)) || os(macOS)

import Combine
import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

// MARK: - Views

struct BoneGlassPanelView: View {
    @ObservedObject var model: BoneGlassPanelModel

    var body: some View {
        ZStack {
            if model.exploded {
                #if canImport(UIKit)
                BoneExplodedScreen(model: model)
                #endif
            } else if model.picking {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .global) { model.pick(at: $0) }
                outlines(model.outlines, dash: [])
                VStack(spacing: 8) {
                    Picker("Mode", selection: $model.mode) {
                        ForEach(BonePanelMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 270)
                    .onChange(of: model.mode) { model.refreshOutlines() }
                    Text(model.status).font(.callout.bold())
                    HStack {
                        #if canImport(UIKit)
                        Button { model.openExploded() } label: { Label("3D", systemImage: "square.3.layers.3d") }
                            .buttonStyle(.bordered)
                        #endif
                        #if (canImport(UIKit) && !os(visionOS)) || os(macOS)
                        Button { model.openTimeline() } label: { Label("Timeline", systemImage: "timeline.selection") }
                            .buttonStyle(.bordered)
                        #endif
                        Button("Cancel") { model.cancelPicking() }.buttonStyle(.borderedProminent).tint(.pink)
                    }
                }
                .padding(14)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 8)
            } else if model.isOpen {
                if model.showing == .layer {
                    BoneLayerOutline(editor: model.layerEditor)
                } else if !model.probing {
                    outlines([model.selection], dash: [6, 4])
                }
                VStack(spacing: 0) {
                    if !model.atTop { Spacer(minLength: 0) }
                    Group {
                        if model.showing == .layer {
                            BoneLayerCard(model: model, editor: model.layerEditor)
                        } else {
                            BoneGlassCard(model: model)
                        }
                    }
                        .containerRelativeFrame(.vertical) { h, _ in h * 0.46 }
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { model.cardRect = $0 }
                        .onDisappear { model.cardRect = .zero }
                    if model.atTop { Spacer(minLength: 0) }
                }
                .padding(.horizontal, 8)
            } else if model.timelineOpen {
                #if canImport(UIKit) && !os(visionOS)
                BoneTimelineScreen(model: model, timeline: model.timeline)
                #elseif os(macOS)
                BoneMacTimelineScreen(model: model, timeline: model.macTimeline)
                #endif
            } else {
                Button { model.startPicking() } label: {
                    Image(systemName: "drop.halffull")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .frame(width: 54, height: 54)
                        .background(Circle().fill(Color.pink.gradient))
                        .shadow(radius: 6)
                }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { model.buttonRect = $0 }
                .onDisappear { model.buttonRect = .zero }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(20)
            }
        }
    }

    private func outlines(_ rects: [CGRect], dash: [CGFloat]) -> some View {
        Canvas { ctx, _ in
            for r in rects where !r.isNull {
                ctx.stroke(Path(roundedRect: r.insetBy(dx: -3, dy: -3), cornerRadius: 10), with: .color(.pink),
                           style: StrokeStyle(lineWidth: 2.5, dash: dash))
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct BoneGlassCard: View {
    @ObservedObject var model: BoneGlassPanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Liquid Glass").font(.headline)
                    Text(model.status).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
                Button { model.switchToLayer() } label: { Image(systemName: "textformat") }
                Button { model.startPicking() } label: { Image(systemName: "scope") }
                Button { model.atTop.toggle() } label: {
                    Image(systemName: model.atTop ? "rectangle.bottomhalf.inset.filled" : "rectangle.tophalf.inset.filled")
                }
                Button { model.close() } label: { Image(systemName: "xmark.circle.fill") }
            }
            .font(.title3)
            if model.filters.count > 1 {
                Picker("Filter", selection: $model.filterIndex) {
                    ForEach(model.filters.indices, id: \.self) { i in Text(model.filters[i].type).tag(i) }
                }
                .pickerStyle(.segmented)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip("Probe", "waveform.path.ecg") { model.probe() }
                    chip("Copy Swift", "doc.on.doc") { model.copySwift() }
                    chip("Save JSON", "square.and.arrow.down") { model.saveJSON() }
                    chip("Reset all", "arrow.uturn.backward") { model.resetAll() }
                    ForEach(BoneGlassPanelModel.presets) { p in chip(p.name, nil) { model.apply(p) } }
                }
            }
            TextField("Search inputs", text: $model.search)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .autocorrectionDisabled()
                .boneNoAutocapitalization()
            if let code = model.code {
                Text(code)
                    .font(.caption2.monospaced())
                    .textSelection(.enabled)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(model.knobGroups()) { g in
                        Text(g.id.uppercased()).font(.caption2.bold()).foregroundStyle(.secondary).padding(.top, 4)
                        ForEach(g.knobs) { BoneKnobRow(model: model, knob: $0) }
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
    }

    private func chip(_ title: String, _ icon: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon) }
                Text(title)
            }
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.pink.opacity(0.15), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct BoneKnobRow: View {
    @ObservedObject var model: BoneGlassPanelModel
    let knob: BoneKnob

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(knob.label)
                    .font(.caption.monospaced())
                    .foregroundStyle(knob.hidden ? Color.purple : Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if model.isChanged(knob) {
                    Button { model.reset(knob) } label: { Image(systemName: "arrow.uturn.backward.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.pink)
                }
                Spacer(minLength: 4)
                accessory
            }
            control
        }
    }

    @ViewBuilder private var accessory: some View {
        switch knob.kind {
        case .number:
            TextField("", value: model.number(knob), format: BoneGlassPanelModel.numberFormat)
                .font(.caption.monospaced())
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .boneDecimalKeyboard()
                .frame(width: 92)
            Button { model.widen(knob) } label: { Image(systemName: "arrow.left.and.right.circle") }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        case .toggle:
            Toggle("", isOn: model.toggle(knob)).labelsHidden()
        case .color:
            ColorPicker("", selection: model.color(knob), supportsOpacity: true).labelsHidden()
        default:
            EmptyView()
        }
    }

    @ViewBuilder private var control: some View {
        switch knob.kind {
        case .number:
            BoneSlider(value: model.number(knob), in: model.range(knob))
        case .size:
            HStack(spacing: 6) {
                Text("w").font(.caption2)
                BoneSlider(value: model.size(knob, 0), in: -100...100)
                Text("h").font(.caption2)
                BoneSlider(value: model.size(knob, 1), in: -100...100)
            }
        case .matrix:
            BoneMatrixEditor(model: model, knob: knob)
        case .toggle, .color:
            EmptyView()
        default:
            Text("\(knob.kind.rawValue) value – not editable here").font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct BoneMatrixEditor: View {
    @ObservedObject var model: BoneGlassPanelModel
    let knob: BoneKnob

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Grid(horizontalSpacing: 3, verticalSpacing: 3) {
                GridRow {
                    ForEach(["r", "g", "b", "a", "bias"], id: \.self) { Text($0).font(.caption2).foregroundStyle(.secondary) }
                }
                ForEach(0..<4, id: \.self) { r in
                    GridRow {
                        ForEach(0..<5, id: \.self) { c in
                            TextField("", value: model.matrixCell(knob, r * 5 + c), format: BoneGlassPanelModel.numberFormat)
                                .font(.caption2.monospaced())
                                .multilineTextAlignment(.trailing)
                                .textFieldStyle(.roundedBorder)
                                .boneDecimalKeyboard()
                        }
                    }
                }
            }
            HStack(spacing: 6) {
                ForEach(BoneMatrixPreset.all) { p in
                    Button(p.name) { model.setMatrix(knob, p.floats) }.font(.caption2).buttonStyle(.bordered)
                }
            }
        }
    }
}

#endif

#endif   // DEBUG
