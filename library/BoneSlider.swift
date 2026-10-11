//
//  BoneSlider.swift
//  Bone-27
//
//  The slider every Bone panel uses (glass inputs, layer editor, 3D spacing,
//  timeline scrubber) – plain SwiftUI, so it builds wherever the panels do.
//  Also the small text-field modifiers that only exist on iOS.
//

#if DEBUG   // Bone is private API: it compiles to nothing outside Debug builds

#if (canImport(UIKit) && !os(watchOS)) || os(macOS)

import SwiftUI

/// A slider drawn and dragged by SwiftUI alone. The system Slider is a Liquid Glass
/// control on iOS 26+: its thumb follows the finger with an AnimationKit spring, so it
/// freezes with everything else while the timeline holds the clock – every panel uses
/// this one instead.
struct BoneSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double?

    init(value: Binding<Double>, in range: ClosedRange<Double>, step: Double? = nil) {
        _value = value
        self.range = range
        self.step = step
    }

    var body: some View {
        GeometryReader { g in
            let knob: CGFloat = 24
            let span = max(range.upperBound - range.lowerBound, .ulpOfOne)
            let f = CGFloat(min(max((value - range.lowerBound) / span, 0), 1))
            let x = f * (g.size.width - knob)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.25)).frame(height: 5)
                Capsule().fill(Color.accentColor).frame(width: x + knob / 2, height: 5)
                Circle()
                    .fill(.white)
                    .frame(width: knob, height: knob)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    .offset(x: x)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { d in
                let t = min(max((d.location.x - knob / 2) / max(g.size.width - knob, 1), 0), 1)
                var v = range.lowerBound + Double(t) * span
                if let step, step > 0 { v = range.lowerBound + ((v - range.lowerBound) / step).rounded() * step }
                if v != value { value = v }
            })
        }
        .frame(height: 30)
    }
}

extension View {
    /// .keyboardType(.decimalPad) on iOS; nothing on macOS.
    func boneDecimalKeyboard() -> some View {
        #if canImport(UIKit)
        keyboardType(.numbersAndPunctuation)
        #else
        self
        #endif
    }

    /// .textInputAutocapitalization(.never) on iOS; nothing on macOS.
    func boneNoAutocapitalization() -> some View {
        #if canImport(UIKit)
        textInputAutocapitalization(.never)
        #else
        self
        #endif
    }
}

#endif

#endif   // DEBUG
