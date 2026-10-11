# Inspector and the 3D exploded view

## `.boneInspector()` / `.glassPanel()` — iOS, macOS

```swift
WindowGroup { ContentView().boneInspector() }   // same as .glassPanel()
```

Adds a floating pink drop. Tap it, then tap text, glass or any element – no mode to choose (Auto;
Glass and Layer force one kind). Glass opens the glass inputs, anything else the layer it is drawn
into, all on sliders. **Aa** on a glass card jumps to the text drawn on that glass, the **drop** on a
layer card back to the glass around it. Auto outlines glass and text; every other element is still
tappable.

### On macOS

The same inspector runs on the Mac: a transparent window attached above the app window hosts the
same panel, and a mouse monitor lets clicks through except over the drop button and the cards (and
everywhere while picking) – AppKit has no per-point pass-through like UIKit's `hitTest`. Click the
drop, then click glass or any element; glass and layer cards, presets, Copy Swift, Save JSON and
Probe work as on iOS (Probe needs Screen Recording). The 3D view and the timeline are iOS-only.

### Glass

Works on your own `.glassEffect()` views and system bars alike. Every input of the glass filters
(`glassBackground`, `vibrantColorMatrix`) gets a control: slider plus typed value (⇔ widens the
range), toggle, colour picker, size, 4×5 colour-matrix editor. Hidden inputs are listed first, in
purple. Changes go to the real glass at once and are re-applied when SwiftUI rebuilds it; on a view
that also has `.tune`, the panel wins for the inputs it holds.

- **Probe** – [`.probeGlass`](glass-tuning.md#probeglass_after--which-inputs-are-live-ios) on the
  picked glass and filter (the panel hides itself meanwhile); inputs it finds live are added to the list.
- **Copy Swift** – `.tune([...])` code for the current changes, to the clipboard.
- **Save JSON** – `captures/glass-panel.json`, for [`.tune(file:)`](glass-tuning.md#tunefile).
- Presets, Reset all, per-input reset, move the panel up/down.

### Layers

Tap any element and edit the layer SwiftUI drew it into – sliders, colours, blend picker, filter
controls, ↑/↓ to the parent or a sublayer. Copy Swift gives the matching
[`.tuneLayers`](layers.md) line.

### Timeline

The **Timeline** button in the pick hint opens the timeline bar – see
[Timeline and morphs](timeline.md).

## 3D exploded view

The **3D** button in the pick hint shows an exploded view of what SwiftUI drew: every drawn layer
(text, shapes, gradients, glass) becomes a plane at its screen position, pushed back by its depth in
the layer tree.

- Drag to orbit, two fingers to move, pinch to zoom, double-tap to reset, slider for the spacing.
- Tap a plane to tune that layer with the same sliders (glass planes open the glass inputs); the edit
  goes to the real layer and is previewed on the plane.
- Hold the eye to peek at the real app, ↻ to re-freeze it after tuning glass or scrolling.

**Glass stays glass:** its layer tree is cloned (`NSKeyedArchiver`) with its current inputs, so it
refracts the planes behind it in 3D and glass edits preview live. Planes are clipped like the app
clips them (scroll views, `List`, anything with `masksToBounds`), so a `List` shows its visible rows;
launch the demo with `-list` for a List with controls, glass in rows and the toolbar glass.

**How it works:** planes are Core Animation layers in a `CATransformLayer`; text, shapes and
gradients are rendered on their own (sublayers hidden for the render). Taps are picked by projecting
each plane's corners with the same matrix; the hit is the plane with the largest `zPosition` × facing
(facing = sign of the rotation's `m33`).
