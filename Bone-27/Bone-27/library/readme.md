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
Liquid Glass. `GlassInput` (generated in `BoneGlassInputs.swift`) lists the 69
inputs SwiftUI sets, with their iOS 27 values, plus 5 hidden ones `.probeGlass`
found live (`.aberrationAmount`, `.aberrationHeight`, `.aberrationOffset`,
`.aberrationAngle`, `.bleedColorMatrixFillColor`). Presets: `.noShadow`,
`.noLensing`, `.noBlur`, `.noHighlight`, `.noBleed`, `.flat`, `.aberration`;
`.raw([...])` for any other key – prefix it to reach another filter of the glass:
`.raw(["vibrantColorMatrix.inputColorMatrix": BoneColorMatrix.value(BoneColorMatrix.invert)])`.
Values are re-applied a few times per second because SwiftUI rebuilds the filter
on updates. Before/after: `captures/tune-comparison.jpg`.

```swift
Button("Liquid") {}.glassEffect().tune(file: "glass-panel.json")
```

`.tune(file:)` loads overrides from JSON (the format `.glassPanel` saves). In the
simulator the file is `<project>/captures/<name>` and is re-read whenever it
changes – edit it on the Mac and watch the glass, no rebuild. Keys are `GlassInput`
case names or Core Animation keys; non-numbers are tagged: `{"color": [r, g, b, a]}`,
`{"size": [w, h]}`, `{"matrix": [20 numbers]}`.

### `.dumpGlass(_:only:after:)` — Liquid Glass parameters, iOS

```swift
Button("Liquid") {}.glassEffect().dumpGlass("glass.txt")                                // all inputs
Button("Liquid") {}.glassEffect().dumpGlass("glass.txt", only: [.blurRadius, .shadowOpacity])
Button("Liquid") {}.glassEffect().tune(.noShadow).dumpGlass("tuned.txt", only: [.shadowOpacity])
```

Writes the current inputs of the glass filter, with the same `GlassInput` keys as `.tune`
(`blurRadius  (inputBlurRadius) = 5`). Without `only:` it writes every input plus the other
filters on the glass layers (e.g. `vibrantColorMatrix`). Put it after `.tune` to verify a tuning.

### `.probeGlass(_:after:)` — which glass inputs are live, iOS

```swift
Button("Liquid") {}.glassEffect().probeGlass("glass-probe.txt")
```

Finds out which filter inputs actually change the rendered glass. For every input
name the SDK exports (`kCAFilterInput…`, 136 on iOS 27, list in
`BoneFilterInputNames.swift`) and every key already on the filter, it sets test
values (numbers 0, 1, 10, 50, −10; toggles; red/green; two colour matrices),
captures the composited screen and counts changed pixels around the glass.
Inputs that changed nothing are tried again with the live hidden inputs switched
on (pass 2) – some only modulate another one. Writes `glass-probe.txt` (report),
`glass-probe.json` and `glass-probe.png` (contact sheet of every live input).
Takes ~3 min for both filters of a glass button. The demo runs it when launched
with `-probe`. Use a structured backdrop: over a flat colour refraction, blur and
aberration are invisible.

iOS 27 simulator, glass button over black/yellow stripes (`captures/glass-probe.*`),
two runs, identical verdicts for all 270 inputs:
- **hidden but live** (never set by SwiftUI): `inputAberrationAmount` – chromatic
  dispersion –, `inputBleedColorMatrixFillColor` – a bleed tint; on
  `vibrantColorMatrix`: `inputBackdropAware`, `inputClampPreserveHue` (tiny)
- **only with aberration on**: `inputAberrationHeight`, `inputAberrationOffset`,
  `inputAberrationAngle`
- 44 of the inputs SwiftUI sets change the image; the rest of the 136 names do
  nothing on this filter (they belong to other Core Animation filters)

How it measures, and why:
- `drawHierarchy` does not reproduce Liquid Glass; UIKit's private
  `_UICreateScreenUIImage` matches `simctl io screenshot` pixel for pixel.
- Right after `CATransaction.flush()` the screen sometimes still shows the previous
  commit, so every capture waits two frames and must agree with the next one
  (runs differ by ≤ 10 px of 201 075).
- Inputs are restored in place – `setValue(nil, forKeyPath:)` removes a key. Putting
  a filter object back takes the render server about a frame, so that is only the
  fallback; every restore is checked against the baseline.

### `.boneInspector()` / `.glassPanel()` — visual inspector, iOS

```swift
WindowGroup { ContentView().boneInspector() }   // same as .glassPanel()
```

Adds a floating pink drop. Tap it, then tap text, glass or any element – no mode to
choose (Auto; Glass and Layer force one kind). Glass opens the glass inputs, anything
else the layer it is drawn into, all on sliders. **Aa** on a glass card jumps to the
text drawn on that glass, the **drop** on a layer card back to the glass around it.
Auto outlines glass and text; every other element is still tappable.

For glass – your own
`.glassEffect()` views and system bars alike. Every input of the glass filters
(`glassBackground`, `vibrantColorMatrix`) gets a control: slider plus typed value
(⇔ widens the range), toggle, colour picker, size, 4×5 colour-matrix editor.
Hidden inputs are listed first, in purple. Changes go to the real glass at once
and are re-applied when SwiftUI rebuilds it; on a view that also has `.tune`, the
panel wins for the inputs it holds.

- **Probe** – `.probeGlass` on the picked glass and filter (the panel hides itself
  meanwhile); inputs it finds live are added to the list.
- **Copy Swift** – `.tune([...])` code for the current changes, to the clipboard.
- **Save JSON** – `captures/glass-panel.json`, for `.tune(file:)`.
- presets, Reset all, per-input reset, move the panel up/down.

### `.tuneLayers(_:where:)` / `.dumpLayers(_:)` — any SwiftUI view, iOS

```swift
Text("Hello").tuneLayers([.rotationY: 35, .shadowOpacity: 1, .shadowRadius: 8], where: .text)
Button("Go") {}.buttonStyle(.borderedProminent).tuneLayers([.filters: .filters([.colorHueRotate(2.2)])])
Image(systemName: "star.fill").tuneLayers([.blendMode: .blend(.difference)], where: .shape)
Text("Hi").tuneLayers([.contents: .image(UIImage(named: "photo")!)], where: .text)
VStack { … }.tuneLayers(.outline, where: .all)      // pink border on every layer
VStack { … }.dumpLayers("layers.txt")                 // what is there, and which targets match
```

On iOS 27 SwiftUI draws most primitives into bare CALayers without a UIView
(`Text("Hello").bone(into:)` → `_UIHostingView<Text>` › `CGDrawingLayer (layer)`):
Text and button labels are `CGDrawingLayer` bitmaps, SF Symbols and filled shapes
`ColorShapeLayer`, gradient fills `GradientLayer`; glass keeps real views. Every one
of them takes:
- `LayerProperty`: opacity, hidden, cornerRadius, masksToBounds, backgroundColor, border,
  shadow, 3D transform about the centre (rotation, rotationX/Y + perspective, scale,
  translation – composed with SwiftUI's own), `blendMode` (22 Core Animation blend
  modes), `filters`, `contents` (replace the bitmap), `contentsGravity`; `.raw([...])`
  for any other key or key path
- `BoneFilter`: gaussianBlur, colorMatrix, colorInvert, colorSaturate, colorHueRotate,
  colorBrightness, colorContrast, colorMonochrome, multiplyColor, luminanceToAlpha,
  `.raw(type, inputs)` for any other `kCAFilter…` type – all verified on a Text layer
  in the iOS 27 simulator; added after SwiftUI's own filters
- `LayerTarget`: `.leaves` (default – every drawn element), `.text`, `.shape`,
  `.gradient`, `.glass`, `.all`, `.className("…")`, `.custom`, combined with `||`

Layers are SwiftUI's choice – it may merge or recreate them – so targets are layer
kinds and values are re-applied a few times per second. Text stays a bitmap: you can
filter, warp, mask or replace it, not edit glyphs.

The glass panel has a **Layer** mode (switch in the pick hint): tap any element, edit
its layer live (sliders, colours, blend picker, filter controls, ↑/↓ to the parent or
a sublayer), Copy Swift gives the `.tuneLayers` line. The demo shows all of it when
launched with `-layers`.

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
