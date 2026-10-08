//
//  BoneGlassInputs.swift
//  Bone-27
//
//  GENERATED from captures/lum-dark.txt (glass button, iOS 27 simulator) –
//  every input of the Liquid Glass "glassBackground" Core Animation filter,
//  plus the hidden ones .probeGlass found live (SwiftUI never sets them).
//  The value in each comment is what the system used for that button; it
//  differs per size/variant (refraction scales with the shape).
//
//  Research / simulator use only – private Core Animation keys.
//

#if canImport(UIKit)

import UIKit

/// A tunable input of the Liquid Glass filter. `rawValue` is the Core Animation key.
enum GlassInput: String, CaseIterable, Hashable {

    // MARK: Bleed – colour bleed of the content into the glass edge
    /// number · iOS 27 button: 11.66666666666668
    case bleedAmount = "inputBleedAmount"
    /// number · iOS 27 button: 0
    case bleedBlurRadius = "inputBleedBlurRadius"
    /// number · iOS 27 button: 0.9
    case bleedColorMatrixBlack = "inputBleedColorMatrixBlack"
    /// number · iOS 27 button: 1.2
    case bleedColorMatrixSaturation = "inputBleedColorMatrixSaturation"
    /// number · iOS 27 button: 1
    case bleedColorMatrixWhite = "inputBleedColorMatrixWhite"
    /// number · iOS 27 button: 1
    case bleedDarkenBlend = "inputBleedDarkenBlend"
    /// number · iOS 27 button: 1
    case bleedDistance0 = "inputBleedDistance0"
    /// number · iOS 27 button: 0
    case bleedDistance1 = "inputBleedDistance1"
    /// number · iOS 27 button: 11.66666666666668
    case bleedHeight = "inputBleedHeight"
    /// number · iOS 27 button: 0
    case bleedOpacity = "inputBleedOpacity"

    // MARK: BlurFill – blur fill layer
    /// number · iOS 27 button: 8
    case blurFillBlurRadius = "inputBlurFillBlurRadius"
    /// number · iOS 27 button: 0
    case blurFillDarkenOpacity = "inputBlurFillDarkenOpacity"
    /// number · iOS 27 button: 0.9
    case blurFillLightenOpacity = "inputBlurFillLightenOpacity"
    /// number · iOS 27 button: 0.5
    case blurFillNormalOpacity = "inputBlurFillNormalOpacity"

    // MARK: Blur – backdrop blur
    /// number · iOS 27 button: -16.66667
    case blurDistance0 = "inputBlurDistance0"
    /// number · iOS 27 button: -1
    case blurDistance1 = "inputBlurDistance1"
    /// number · iOS 27 button: 0
    case blurDistance2 = "inputBlurDistance2"
    /// number · iOS 27 button: 0
    case blurDistance3 = "inputBlurDistance3"
    /// number · iOS 27 button: 0
    case blurOpacity0 = "inputBlurOpacity0"
    /// number · iOS 27 button: 0
    case blurOpacity1 = "inputBlurOpacity1"
    /// number · iOS 27 button: 0.5
    case blurOpacity2 = "inputBlurOpacity2"
    /// number · iOS 27 button: 1
    case blurOpacity3 = "inputBlurOpacity3"
    /// number · iOS 27 button: 5
    case blurRadius = "inputBlurRadius"

    // MARK: Clamp – output clamp
    /// number · iOS 27 button: 1.06961
    case clamp = "inputClamp"
    /// number · iOS 27 button: 0
    case clampPreserveHue = "inputClampPreserveHue"

    // MARK: FaceColorMatrix – face colour matrix – vibrant fill (Configuration.vibrantFill / tint)
    /// number · iOS 27 button: 0.4
    case faceColorMatrixBlack = "inputFaceColorMatrixBlack"
    /// color · iOS 27 button: CGColor
    case faceColorMatrixFillColor = "inputFaceColorMatrixFillColor"
    /// number · iOS 27 button: 1
    case faceColorMatrixMaxLuma = "inputFaceColorMatrixMaxLuma"
    /// number · iOS 27 button: 0.94
    case faceColorMatrixMaxLumaSDR = "inputFaceColorMatrixMaxLumaSDR"
    /// number · iOS 27 button: 1.2
    case faceColorMatrixSaturation = "inputFaceColorMatrixSaturation"
    /// number · iOS 27 button: 1.03
    case faceColorMatrixWhite = "inputFaceColorMatrixWhite"

    // MARK: Face – glass face (platter)
    /// number · iOS 27 button: 1
    case faceOpacity = "inputFaceOpacity"

    // MARK: InnerRefraction – refraction (lensing) – inner
    /// number · iOS 27 button: -16.66666666666669
    case innerRefractionAmount = "inputInnerRefractionAmount"
    /// number · iOS 27 button: 8.333333333333343
    case innerRefractionHeight = "inputInnerRefractionHeight"

    // MARK: OuterRefraction – refraction (lensing) – outer
    /// number · iOS 27 button: 16
    case outerRefractionAmount = "inputOuterRefractionAmount"
    /// number · iOS 27 button: 16
    case outerRefractionHeight = "inputOuterRefractionHeight"

    // MARK: Refraction – refraction (lensing)
    /// number · iOS 27 button: -1
    case refractionDistance0 = "inputRefractionDistance0"
    /// number · iOS 27 button: 0
    case refractionDistance1 = "inputRefractionDistance1"
    /// number · iOS 27 button: 0.6
    case refractionOpacity = "inputRefractionOpacity"

    // MARK: KeyFillHighlight – specular key-light highlight (Configuration.highlightAngle)
    /// number · iOS 27 button: 0.4
    case keyFillHighlightAmount = "inputKeyFillHighlightAmount"
    /// number · iOS 27 button: 1.570796326794897
    case keyFillHighlightAngle = "inputKeyFillHighlightAngle"
    /// number · iOS 27 button: -0.3
    case keyFillHighlightColorBias = "inputKeyFillHighlightColorBias"
    /// number · iOS 27 button: -0.5333333333333333
    case keyFillHighlightEffectOffset = "inputKeyFillHighlightEffectOffset"
    /// number · iOS 27 button: 0.5333333333333333
    case keyFillHighlightHeight = "inputKeyFillHighlightHeight"
    /// number · iOS 27 button: 1.675516081914556
    case keyFillHighlightSpread = "inputKeyFillHighlightSpread"
    /// number · iOS 27 button: 1.850049007113989
    case keyFillHighlightSpreadSDR = "inputKeyFillHighlightSpreadSDR"

    // MARK: MaxHeadroom – HDR headroom (GlassMaterialProvider.hdrHeadroom)
    /// number · iOS 27 button: 9999
    case maxHeadroom = "inputMaxHeadroom"

    // MARK: RingShadow – ring shadow around the edge
    /// number · iOS 27 button: 5
    case ringShadowBlurRadius = "inputRingShadowBlurRadius"
    /// number · iOS 27 button: 1
    case ringShadowMask = "inputRingShadowMask"
    /// number · iOS 27 button: 8
    case ringShadowOffset = "inputRingShadowOffset"
    /// number · iOS 27 button: 0.06
    case ringShadowOpacity = "inputRingShadowOpacity"
    /// number · iOS 27 button: 4
    case ringShadowStrokeWidth = "inputRingShadowStrokeWidth"

    // MARK: SDR – SDR fallback
    /// number · iOS 27 button: 0
    case sdrGradientDistance0 = "inputSDRGradientDistance0"
    /// number · iOS 27 button: 0
    case sdrGradientDistance1 = "inputSDRGradientDistance1"
    /// number · iOS 27 button: 0
    case sdrHoldingToneEnabled = "inputSDRHoldingToneEnabled"
    /// number · iOS 27 button: 1
    case sdrHoldingToneWhite = "inputSDRHoldingToneWhite"
    /// number · iOS 27 button: 0
    case sdrShadowOpacity = "inputSDRShadowOpacity"

    // MARK: Shadow – drop shadow
    /// number · iOS 27 button: 0
    case shadowAmount = "inputShadowAmount"
    /// number · iOS 27 button: 0
    case shadowBlurRadius = "inputShadowBlurRadius"
    /// number · iOS 27 button: 0
    case shadowColorMatrixBlack = "inputShadowColorMatrixBlack"
    /// color · iOS 27 button: CGColor
    case shadowColorMatrixFillColor = "inputShadowColorMatrixFillColor"
    /// number · iOS 27 button: 1
    case shadowColorMatrixSaturation = "inputShadowColorMatrixSaturation"
    /// number · iOS 27 button: 1
    case shadowColorMatrixWhite = "inputShadowColorMatrixWhite"
    /// number · iOS 27 button: 0
    case shadowDistanceOffset = "inputShadowDistanceOffset"
    /// number · iOS 27 button: 0
    case shadowHeight = "inputShadowHeight"
    /// size · iOS 27 button: NSSize: {0, 8}
    case shadowOffset = "inputShadowOffset"
    /// number · iOS 27 button: 0.04
    case shadowOpacity = "inputShadowOpacity"
    /// number · iOS 27 button: 4
    case shadowRadius = "inputShadowRadius"
    /// number · iOS 27 button: 0
    case shadowVibrancyContribution = "inputShadowVibrancyContribution"

    // MARK: Hidden – not set by SwiftUI on iOS 27, verified live by .probeGlass
    // (glass button over black/yellow stripes, iOS 27 simulator, 8 Oct 2026)
    /// number · hidden – SwiftUI never sets it · probe: 50 → 9.8% of pixels changed
    case aberrationAmount = "inputAberrationAmount"
    /// color · hidden – SwiftUI never sets it · probe: green → 13.2% of pixels changed
    case bleedColorMatrixFillColor = "inputBleedColorMatrixFillColor"
    /// number · hidden – SwiftUI never sets it · only together with the other hidden inputs (probe pass 2) · probe: -10 → 11.6% of pixels changed
    case aberrationAngle = "inputAberrationAngle"
    /// number · hidden – SwiftUI never sets it · only together with the other hidden inputs (probe pass 2) · probe: -10 → 26.9% of pixels changed
    case aberrationHeight = "inputAberrationHeight"
    /// number · hidden – SwiftUI never sets it · only together with the other hidden inputs (probe pass 2) · probe: 50 → 26.9% of pixels changed
    case aberrationOffset = "inputAberrationOffset"
}

extension GlassInput {
    /// What kind of value the input takes (from the iOS 27 capture).
    var valueKind: String {
        switch self {
        case .faceColorMatrixFillColor: return "color"
        case .shadowColorMatrixFillColor: return "color"
        case .bleedColorMatrixFillColor: return "color"
        case .shadowOffset: return "size"
        default: return "number"
        }
    }
}

#endif
