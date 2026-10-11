# Getting started

## Install

Copy every file in `library/` into a folder of your project and add them to all targets. There is
no package yet.

> **Research / simulator use only.** Never ship Bone in an App Store build. Wrap its modifiers in
> `#if DEBUG` if they live in an app you also release.

```swift
List {
    Text("Bone")
}
.bone(into: "output.txt")
```

This writes the UIKit hierarchy behind the list to `output.txt` and shows it as an overlay.

## Platforms

| | iOS | watchOS | visionOS | macOS |
|---|:-:|:-:|:-:|:-:|
| Hierarchy dump `.bone(into:)` | ✓ | ✓ | ✓ | ✓ |
| 3D hierarchy `.bone3D` · `.bone3DFrom` | | | ✓ | |
| Liquid Glass `.tune` · `.dumpGlass` | ✓ | ✓ | | ✓ |
| `.dumpLayers` | ✓ | ✓ | | ✓ |
| `.tuneLayers` · `.dumpShaders` | ✓ | | | ✓ |
| `.probeGlass` · `.boneInspector` (3D view) | ✓ | | | |
| Timeline · `.morphScrubber` · `.dumpMorph` · `.liquidMorph` · `.glassFlex` | ✓ | | | |

- **Tested:** iOS 27 – simulator and an iPhone 14 Pro; watchOS 27 – simulator; visionOS 27; macOS.
  Built with Xcode 27. Deployment targets: iOS, watchOS and visionOS 27.0, macOS 26.5.
- **Liquid Glass** arrived with iOS 26, but the glass tools were only measured on iOS 27 – private
  names and filter inputs change between releases.
- **watchOS** has no public UIKit; Bone reaches the watch's UIKit and Core Animation through the
  Objective-C runtime (see [Hierarchy dumps](hierarchy.md#boneinto-on-watchos) and
  [Glass tuning](glass-tuning.md#on-watchos-and-macos)).
- **visionOS** has no SwiftUI Liquid Glass (`glassEffect` is unavailable there). The inspector and
  layer tools compile on visionOS but are untested; the timeline and morph tools are iOS-only, as
  they drive iOS's AnimationKit morphs.
- **macOS** draws Liquid Glass like iOS (the same SDF layers and `glassBackground` filter), so
  `.tune`, `.dumpGlass`, `.tuneLayers`, `.dumpLayers` and `.dumpShaders` work there, plus the
  hierarchy dump. Captures need App Sandbox disabled.
- **`.tuneLayers` on watchOS** is not possible as on iOS: `CALayer` and `CATransform3D` are hidden
  from the watchOS SDK; `.dumpLayers` reads the layers through the runtime instead.

## Demo app

The `Bone-27` project shows every feature. Launch arguments (Edit Scheme ▸ Arguments) pick one
row:

| Argument | Shows |
|---|---|
| *(none)* | all demo rows; the first is a glass `Menu` with the timeline |
| `-menu` | only the glass `Menu`, timeline bar open |
| `-liquid` | only the `.liquidMorph` row (`-autotoggle` flips it every 3 s) |
| `-flex` | stock vs `.glassFlex` buttons |
| `-list` | a `List` + `NavigationStack` with controls, glass in rows and toolbar glass |
| `-layers` | `.tuneLayers` on text, symbols and gradients |
| `-probe` | runs `.probeGlass` on a glass button |

On a device, pass arguments after `--`:
`xcrun devicectl device process launch --device <id> <bundle-id> -- -flex`.

## Where files land

- The app's **Documents** folder, always; the path is printed as `OUTPUT FILE:`.
- **`<project>/captures/`** in the iOS/visionOS *simulator* and on native macOS (macOS needs App
  Sandbox disabled). The folder is found via `#filePath`, so rebuild after moving the project.
