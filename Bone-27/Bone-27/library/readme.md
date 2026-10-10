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

**Full dump** – `.dumpGlass("glass-full.txt", full: true)` adds the glass element's layer tree
and the **glass shaders' own parameters**, all in one text file (`captures/glass-full.txt`).
`.dumpShaders("shaders.txt", matching: "glass")` writes just the shader part, for any
QuartzCore shader family (`"blur"`, `"vibrant"`, …).

Bone loads QuartzCore's `default.metallib` with Metal (228 functions on iOS 27, 36 glass), and
reflects each glass shader by building a render pipeline with QuartzCore's own vertex function
(the reflection-only API is not implemented in the simulator). One variant per family is
reflected (`reflectAll: true` for all, slower); takes ~0.5 s. You get every buffer, texture and
uniform struct the shader reads – field, byte offset, type – and which filter input feeds it:

```
-- S1: 63 fields, 320 bytes · bound as u in glass_background_all_lpf.u
     16      inner_refraction_amount     float     ← innerRefractionAmount
     20      inner_refraction_inv_height float     ← 1 / innerRefractionHeight
     80      face_cm0                    half4     ← faceColorMatrix{Black, FillColor, MaxLuma, …} (derived)
     160     blur_alpha0                 float     ← blurOpacity0
     312     aberration_dir              float2    ← aberrationAngle (as a direction)
     32      refraction_threshold0       float     –        (no input – set by the render server)
```

Five structs on iOS 27: `glassBackground` (63 fields), its SDF variant (66), the shared
extension block (`u_ext`: `preserve_hue`, `stroke_mode`, `highlight_extension`, …), and
`glassForeground` (13) with its SDF variant (16).

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

**3D** (button in the pick hint) – an exploded view of what SwiftUI drew: every drawn layer
(text, shapes, gradients, glass) becomes a plane at its screen position, pushed back by its
depth in the layer tree. Drag to orbit, two fingers to move, pinch to zoom, double-tap to
reset, slider for the spacing. Tap a plane to tune that layer with the same sliders (glass
planes open the glass inputs); the edit goes to the real layer and is previewed on the plane.
Hold the eye to peek at the real app, ↻ to re-freeze it after tuning glass or scrolling. Planes
are Core Animation layers in a `CATransformLayer`; taps are picked by projecting each plane's
corners. Glass stays glass: its layer tree is cloned (`NSKeyedArchiver`) with its current
inputs, so it refracts the planes behind it in 3D and glass edits preview live. Planes are
clipped like the app clips them (scroll views, `List`, anything with `masksToBounds`), so a
`List` shows its visible rows; launch with `-list` for a List with controls, glass in rows
and the toolbar glass.

**Timeline** (button in the pick hint) – pause, slow down and step the app's animations,
the Liquid Glass morphs included, and scrub a recorded take. ⏸ freezes everything (the glass
stays live: the drop in the bar inspects or tunes it mid-morph, 3D works too), ⏭ advances one
60 Hz frame, and the speed button cycles 1× ½ ¼ ⅒ 1⁄20. A spring only runs forward, so
scrubbing is over a take: ⏺ steps the animation frame by frame, captures the screen after each
step and stops once it has settled; the slider then scrubs the take both ways, Save writes a
contact sheet (`timeline-take.png`). Pause first, then
trigger the animation. `.morphTimeline()` (or `.morphTimeline(speed: 0.1)`) on any view opens
the inspector with the bar already showing:

```swift
Menu { Button("Copy") {} } label: { Label("Options", systemImage: "ellipsis.circle") }
    .buttonStyle(.glass)
    .morphTimeline()
```

`.morphScrubber()` needs no steps at all: 1.2 s after launch it runs the modified control's
primary action (`performPrimaryAction()` – a glass Menu opens), and the morph that starts is
caught on its first frame (the clock pauses on the very tick its manager
wakes up or registers new animations), recorded frame by frame to its end (when UIKit removes
the morph's own layers), and a 0.0–1.0 scrubber appears. "Again" waits for the next one;
`.morphScrubber(trigger: false)` waits for a tap instead (a finger on the app arms the clock). Frame 0 – 0.0 on the
scrubber – is the screen captured just before the morph (the untouched button): the first frame
the clock catches is already a little way in.

```swift
Menu { Button("Copy") {} } label: { Label("Options", systemImage: "ellipsis.circle") }
    .buttonStyle(.glass)
    .morphScrubber()
```

`.dumpMorph("menu-morph.csv")` is `.morphScrubber()` that also writes the morph's animated
values, frame by frame, to a CSV (long format: `frame,time,progress,layer,key,component,value`).
They are read from the CAPresentationModifiers through which AnimationKit hands the morph to the
render server: the blob's `bounds` and `position` springing out, its `cornerRadii` (four CGSizes:
size1…size4), the lensing layer's `filters.displacementMap.inputAmount` and
`filters.gaussianBlur.inputRadius`, the lens container's `sublayerTransform` (m11…m44).

`.liquidMorph(to:isPresented:)` runs Apple's own Liquid Glass morph between any two views:

```swift
Text("Hello")
    .liquidMorph(to: Circle().foregroundStyle(.green).frame(width: 30, height: 30), isPresented: $on)
```

Both ends sit in public glass (`UIVisualEffectView` + `UIGlassEffect`, capsule corners); toggling
`isPresented` morphs one into the other with UIKit's `_UIMagicMorphAnimation` – the AnimationKit
morph of the floating tab bar and search field – through its Objective-C door,
`morphTo:(UITargetedPreview)` once for the source, once for the target. The menu's own
`LiquidMorphAnimation` (with the drop step) has only a Swift API whose arguments are values of
AnimationKit's private protocols, so it is not reachable from outside. Launch with `-liquid` for
the demo row alone (`-autotoggle` flips it every 3 s).

The demo's first row is that menu (`-menu` shows only it). On a device the screen reads back
black, so a take keeps system snapshot views (glass included, scrubbed instantly; Save is
simulator-only).

The morphs are not CAAnimations (`layer.speed` does nothing to them): AnimationKit's
`LiquidMorphAnimation` and the other in-process animations are advanced inside the app by
`InProcessAnimationManager` (two instances, one on the main thread) from `-displayLinkFire:`,
each tick by `deltaTime = timestamp − time`. `BoneAnimationClock` swizzles that method and
rewrites `time` before each tick, so a tick advances by the clock's step: nothing while
paused, exactly one frame when stepping, and when slowed down whole 60 Hz frames every few
ticks – stop-motion, because parts of a morph are smoothed per tick: fed a tiny step every
tick they still run at close to full speed. Scaling Core Animation time as well is
opt-in (`timeline.scalesLayerTime`): slowing the window layer time down makes UIKit finish a
morph at once.

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
