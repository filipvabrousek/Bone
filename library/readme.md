# Bone

Research toolkit for peeking behind SwiftUI — dumps the real UIKit/AppKit
view hierarchy, ViewGraph internals, and renders it as a tappable 3D graph
on visionOS. Simulator/debug use only (uses private introspection selectors).

## Modifiers

### `.bone(into:)` — iOS, visionOS, macOS

```swift
List { Text("WOW") }.bone(into: "output.txt")      // classic brief text dump
List { Text("WOW") }.bone(into: "structure.json")  // deep SwiftUI dump (JSON)
```

The **extension decides the format**:
- `.txt` (or anything non-JSON) → classic brief dump: class, superclass, layer, sublayers per view
- `.json` → deep dump: Mirror of the SwiftUI value tree, hosting view → ViewGraph/renderer,
  `recursiveDescription`, `_autolayoutTrace`, and the full per-node tree with `_ivarDescription`

Also adds colored debug borders + a tappable overlay inspector.
On iOS 27+ each run additionally writes `briefoutput.txt` and timestamped
deep captures (`<name>_capture_<OS>_<timestamp>.txt/.json`) to Documents
**and** `<project>/captures/` (simulator).

### `.bone3D(into:)` — visionOS

```swift
List { Text("Hello") }.bone3D()                    // live 3D hierarchy, no file
List { Text("Hello") }.bone3D(into: "ssu.json")    // + deep JSON dump
List { Text("Hello") }.bone3D(into: "dump.txt")    // + brief text dump
```

Captures the live UIKit hierarchy of the wrapped view and renders it as an
unbounded 3D tree in a volumetric window. Tap a slab for details
(superclass, layer, sublayers, ivars). Optional `into:` writes the dump
(same extension rule as `.bone`).

### `.bone3DFrom(_:)` — visionOS

```swift
List { Text("Hello") }.bone3DFrom("briefoutput.txt")   // brief text dump
List { Text("Hello") }.bone3DFrom("structure.json")    // deep JSON dump
```

Builds the 3D graph from a dump file instead of a live capture — including
the `output_capture_*.json` files. Resolution order: absolute path →
`<project>/captures/` (simulator) → app Documents. Lets you view an
iOS/macOS-captured hierarchy on visionOS and compare platforms.

## Configuration

```swift
BoneCapture.maxIvarLength = 20_000              // chars of ivar dump per node
BoneCapture.maxMirrorDepth = 7                  // Mirror recursion depth
BoneCapture.captureIvarDescriptions = true
BoneCapture.captureRecursiveDescription = true
BoneCapture.captureAutolayoutTrace = true
BoneCapture.ivarDenylist                        // class-name prefixes to skip
```

If a capture crashes (EXC_BAD_ACCESS in a private selector), the last
`BONE introspecting …` console line names the class — add its prefix to
`ivarDenylist`. Known broken: `_UIHostingView` on iOS 26, all
`_TtGC7SwiftUI…` generic classes on visionOS 27 (defaults handle both).

### `.tune(_:)` — Liquid Glass parameters, iOS

```swift
Button("Liquid") {}.glassEffect().tune(.noShadow + .noLensing)
Button("Liquid") {}.glassEffect().tune([.blurRadius: 0, .faceOpacity: 0.3])
Button("Liquid") {}.glassEffect().tune(.flat)
```

Overrides inputs of the `glassBackground` Core Animation filter that draws
Liquid Glass. `GlassInput` (generated in `BoneGlassInputs.swift`) lists all 69
inputs with their iOS 27 values; presets: `.noShadow`, `.noLensing`, `.noBlur`,
`.noHighlight`, `.noBleed`, `.flat`; `.raw([...])` for unknown keys. Values are
re-applied a few times per second because SwiftUI rebuilds the filter on
updates. Before/after: `captures/tune-comparison.jpg`.

### `.dumpGlass(_:only:after:)` — Liquid Glass parameters, iOS

```swift
Button("Liquid") {}.glassEffect().dumpGlass("glass.txt")                                // all inputs
Button("Liquid") {}.glassEffect().dumpGlass("glass.txt", only: [.blurRadius, .shadowOpacity])
Button("Liquid") {}.glassEffect().tune(.noShadow).dumpGlass("tuned.txt", only: [.shadowOpacity])
```

Writes the current inputs of the glass filter, with the same `GlassInput` keys as `.tune`
(`blurRadius  (inputBlurRadius) = 5`). Without `only:` it writes every input plus the other
filters on the glass layers (e.g. `vibrantColorMatrix`). Put it after `.tune` to verify a tuning.

Private Core Animation keys — research/simulator use only, never ship, and
expect renames between OS releases.

## Where files land

- App's **Documents** folder (always; path printed as `OUTPUT FILE:`)
- **`<project>/captures/`** — iOS/visionOS *simulator* and native macOS
  (macOS needs App Sandbox disabled). Located via `#filePath`, so rebuild
  after moving the project.

## Cross-OS diffing

```bash
cd captures
diff <(jq -S . output_capture_iOS26_0_*.json) <(jq -S . output_capture_iOS27_0_*.json)
```

Renamed private classes, hierarchy changes, and ivar-layout differences
between OS releases fall out automatically.
