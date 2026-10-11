// Bone – how it works, and what is new.
// Compile: typst compile bone-internals.typ   (→ bone-internals.pdf)

#import "@preview/fletcher:0.5.8" as fletcher: diagram, node, edge
#import "@preview/cetz:0.3.4"

#set document(title: "Bone – internals and novelty", author: "Filip Vabroušek")
#set page(paper: "a4", margin: (x: 1.8cm, y: 1.9cm), numbering: "1",
  header: context { if counter(page).get().first() > 1 [#text(size: 8pt, fill: luma(120))[Bone – internals and novelty #h(1fr) iOS 27 · 11 Oct 2026]] })
#set text(font: ("SF Pro Text", "Helvetica Neue", "Arial"), size: 9.6pt, lang: "en")
#set par(justify: true, leading: 0.62em)
#set heading(numbering: "1.1")
#show heading.where(level: 1): it => { v(0.6em); text(size: 14pt, weight: "bold", it); v(0.2em) }
#show heading.where(level: 2): it => { v(0.3em); text(size: 11pt, weight: "bold", it) }
#show raw: set text(font: ("SF Mono", "Menlo"), size: 8.4pt)
#show raw.where(block: true): it => block(fill: luma(246), inset: 7pt, radius: 4pt, width: 100%, it)
#show link: set text(fill: rgb("#1a5fb4"))
#show table: set par(justify: false)
#show figure: set par(justify: false)
#set table(align: left)

// palette (same as liquid-glass-system.typ)
#let app   = rgb("#e8f0fe")
#let ak    = rgb("#e6f4ea")
#let rs    = rgb("#eceff1")
#let gpu   = rgb("#fff4e5")
#let bone  = rgb("#fde7f0")
#let boneS = rgb("#d81b60")
#let newc  = rgb("#e6f4ea")
#let oldc  = rgb("#f5f5f5")

#let small(t) = { set par(justify: false); show raw: set text(size: 6.9pt); text(size: 7.6pt, t) }
#let card(title, body) = { set par(justify: false); show raw: set text(size: 7.2pt); align(left)[*#title* \ #small(body)] }
#let hook(title, body) = { set par(justify: false); show raw: set text(size: 7.2pt); align(left)[#text(fill: boneS)[*#title*] \ #small(body)] }
#let tiny(t) = { set par(justify: false); show raw: set text(size: 6.4pt); text(size: 7pt, t) }
#let note(body) = block(fill: rgb("#fff8e1"), stroke: (left: 2pt + rgb("#f9a825")), inset: 7pt, width: 100%, body)
#let fig(body, caption) = figure(body, caption: caption, kind: image, supplement: "Figure")

// ───────────────────────────── title ─────────────────────────────
#align(center)[
  #v(1.2cm)
  #text(size: 22pt, weight: "bold")[Bone]
  #v(-0.4em)
  #text(size: 13pt)[How it works – at the level of layers, ivars and setters – and what is new]
  #v(0.3em)
  #text(size: 9pt, fill: luma(90))[iOS 27 (24A437) · iPhone 14 Pro (A16) + simulator · 11 October 2026 · #link("https://github.com/filipvabrousek/Bone")[github.com/filipvabrousek/Bone]]
]
#v(0.6cm)

#note[*Research only.* Everything below uses private classes, selectors, ivars and Core Animation keys,
found and verified by measurement on iOS 27. Names and behaviour change between OS releases. Never
ship any of it in an App Store build.]

#v(0.3cm)
Bone is a set of SwiftUI modifiers that look *underneath* SwiftUI: the UIKit views and Core
Animation layers SwiftUI renders into, the private Liquid Glass filter and its shaders, and the
private AnimationKit engine that animates the glass. It started as a hierarchy dumper
(`.bone(into:)`) and grew into a toolkit that reads, tunes, freezes, records and re-drives the
system's own Liquid Glass – in place, on the real glass, not on a reimplementation.

#outline(depth: 2, indent: 1.2em)

#pagebreak()

// ───────────────────────────── 1 ─────────────────────────────
= Feature map

#figure(
  table(
    columns: (auto, 1fr, 1fr),
    inset: 5pt, stroke: 0.4pt + luma(200),
    fill: (x, y) => if y == 0 { luma(235) },
    [*Modifier / tool*], [*What it does*], [*How (one line)*],
    [`.bone(into:)`], [UIKit view tree behind a SwiftUI view, overlay + file], [hosts the view in a `UIHostingController`, walks `subviews`; `_ivarDescription`, `recursiveDescription`, `Mirror` → JSON],
    [`.bone3D()` · `.bone3DFrom(_:)`], [the tree as 3D slabs (visionOS)], [same walk → RealityKit entities],
    [`.tune(_:)`], [override any Liquid Glass parameter], [KVC key paths `filters.<name>.<input>` on the backdrop layer, re-applied],
    [`.dumpGlass(_:)`], [all ≈70 glass inputs with values], [reads the filter objects' input keys],
    [`.probeGlass(_:)`], [which inputs really change the pixels], [136 SDK input names × test values, composited-screen pixel diff],
    [`.dumpShaders(_:)`], [the glass shaders' own uniforms], [QuartzCore `default.metallib` + Metal pipeline reflection],
    [`.boneInspector()`], [tap any glass or layer, edit live on sliders], [overlay window, hit-testing by layer frames, same KVC writes],
    [3D exploded view], [every drawn layer as a plane, live glass in 3D], [`CATransformLayer` planes, glass cloned with `NSKeyedArchiver`],
    [`.tuneLayers(_:)` · `.dumpLayers`], [filters/blend/transform on the layers of any view], [targets layer kinds (`CGDrawingLayer`, `ColorShapeLayer`…)],
    [`BoneAnimationClock`], [pause, step, slow motion of the glass morphs], [swizzled `-displayLinkFire:`, rewritten ivar `time`],
    [`.morphTimeline()` · `.morphScrubber()`], [record a morph, scrub it 0 → 1], [clock steps + capture per frame; trigger from touch + manager wake-up],
    [`.dumpMorph(_:)`], [the morph's animated values per frame, CSV], [`Mirror` down to `CAPresentationModifier`s],
    [`.liquidMorph(to:isPresented:)`], [Apple's glass morph between any two views], [`_UIMagicMorphAnimation` `morphTo:` with targeted previews],
    [`.glassFlex(stretch:follow:)`], [the glass button's press/drag stretch × N], [swizzled `CALayer` setters, content + outline + shape element mapped],
  ),
  caption: [What Bone does and the mechanism behind each part.],
)

== Architecture

#fig(
  diagram(
    spacing: (8pt, 18pt),
    node-stroke: 0.6pt + luma(140), node-corner-radius: 4pt, node-inset: 5pt,
    edge-stroke: 0.7pt + luma(90), mark-scale: 70%,

    // modifiers
    node((0, 0), card([Hierarchy], [`.bone` · `.bone3D`]), fill: bone, stroke: 0.6pt + boneS, name: <m1>, width: 84pt),
    node((1, 0), card([Glass parameters], [`.tune` · `.dumpGlass` \ `.probeGlass` · `.dumpShaders`]), fill: bone, stroke: 0.6pt + boneS, name: <m2>, width: 84pt),
    node((2, 0), card([Inspector], [panel · 3D · `.tuneLayers`]), fill: bone, stroke: 0.6pt + boneS, name: <m3>, width: 84pt),
    node((3, 0), card([Motion], [clock · timeline · \ `.morphScrubber` \ `.dumpMorph`]), fill: bone, stroke: 0.6pt + boneS, name: <m4>, width: 84pt),
    node((4, 0), card([Driving glass], [`.liquidMorph` · \ `.glassFlex`]), fill: bone, stroke: 0.6pt + boneS, name: <m5>, width: 84pt),

    // techniques
    node((0, 1), card([view walk], [subviews, private \ introspection, Mirror]), fill: white, name: <t1>, width: 84pt),
    node((1, 1), card([KVC key paths], [filters.name.input, \ re-applied ≈4×/s]), fill: white, name: <t2>, width: 84pt),
    node((2, 1), card([layer search], [frames, filter types, \ archive/unarchive]), fill: white, name: <t3>, width: 84pt),
    node((3, 1), card([swizzle + ivars], [method IMPs swapped, \ ivars, raw offsets]), fill: white, name: <t4>, width: 84pt),
    node((4, 1), card([private calls], [classes by name, \ IMPs as C functions]), fill: white, name: <t5>, width: 84pt),

    // system
    node((0.5, 2), card([UIKit / SwiftUI views], [hosting views, inherited views, the glass interaction view]), fill: app, name: <s1>, width: 108pt),
    node((2, 2), card([Core Animation layer tree], [backdrop + `glassBackground`, \ SDF layers and elements]), fill: app, name: <s2>, width: 108pt),
    node((3.5, 2), card([AnimationKit (private)], [in-process managers ×2, \ liquid / magic morphs]), fill: ak, name: <s3>, width: 108pt),
    node((2, 3), card([Render server], [QuartzCore `default.metallib`; composites the glass – the only place it exists as pixels]), fill: gpu, name: <s4>, width: 110pt),

    edge(<m1>, <t1>, "-|>"), edge(<m2>, <t2>, "-|>"), edge(<m3>, <t3>, "-|>"),
    edge(<m3>, <t2>, "-|>"), edge(<m4>, <t4>, "-|>"), edge(<m5>, <t4>, "-|>"), edge(<m5>, <t5>, "-|>"),
    edge(<t1>, <s1>, "-|>"), edge(<t2>, <s2>, "-|>"), edge(<t3>, <s2>, "-|>"),
    edge(<t4>, <s3>, "-|>"), edge(<t4>, <s2>, "-|>"), edge(<t5>, <s3>, "-|>"),
    edge(<s1>, <s2>, "-|>"), edge(<s3>, <s2>, "-|>"),
    edge(<s2>, <s4>, "-|>", label: small[`CATransaction` commit], label-side: left),
    edge(<m2>, (1, 3), <s4>, "--|>", stroke: 0.6pt + boneS),
  ),
  [Bone's layers: modifiers (pink) → the few techniques they share → the system parts they reach. AnimationKit reaches the layer tree through presentation modifiers; dashed: `.dumpShaders` reads the render server's Metal library directly.],
)

#pagebreak()

// ───────────────────────────── 2 ─────────────────────────────
= The toolbox – techniques everything is built from

== Anchor views
Almost every modifier is `background(SomeRepresentable(...))`: a zero-size `UIViewRepresentable`
whose `UIView` lands in the same window as the modified content. Its frame in window coordinates
marks *the area the modifier applies to* (glass inside it is tuned, flexed or probed); its
`window` is the entry point for layer searches. `.glassFlex` keeps its anchors in a weak
`NSHashTable` so a hook can ask “is this layer inside a `.glassFlex` view?”.

== Finding the glass
Liquid Glass is not a view. On iOS 27 a glass shape is a small layer tree under SwiftUI's
`SDFLayer` (a Swift class – `NSClassFromString("SDFLayer")` does *not* find it, matching by
`String(describing:)` does):

```
SDFLayer                          host – resting size, e.g. 61×39
├─ _UIInheritedView layer
│  └─ UIPlatformGlassInteractionView   content: label, glow
└─ CALayer                        container = the shape's frame
   ├─ CABackdropLayer             glassBackground (~70 inputs),
   │  │                           vibrantColorMatrix
   │  └─ CASDFLayer "@0"          CASDFOutputEffect
   │     └─ CALayer
   │        └─ CASDFElementLayer  THE shape: bounds + radius,
   │                              or a distance-field bitmap
   ├─ SDFPortalLayer              the content inside the glass
   └─ CASDFLayer                  rim highlight, via a portal
```

Bone finds glass by walking a window's layer tree for layers whose `filters`/`backgroundFilters`
contain a filter of type `glassBackground` (`BoneGlassLayers.glassLayers`).

== Writing private filter inputs
A Core Animation filter input is reachable by key path on the layer that owns the filter:
`layer.setValue(v, forKeyPath: "filters.glassBackground.inputBlurRadius")`. `setValue(nil, …)`
removes the input again (the filter falls back to its default). SwiftUI rebuilds the filter on
hover, press and state changes, so tuned values are re-applied a few times per second.

== Swizzling and ivars
Two private engines are steered by replacing one Objective-C method each:
`method_setImplementation(m, imp_implementationWithBlock(block))`, with the original IMP kept as
a `@convention(c)` function pointer (`unsafeBitCast(method_getImplementation(m), …)`) and called
from the block. A generic `@convention(c)` type is not representable, so there is one concrete
hook per argument type (`CGRect`, `CGPoint`, `CATransform3D`, `CGAffineTransform`, `CGFloat`).
Swift ivars of private classes are reached with `class_getInstanceVariable` + raw offsets, and
Swift private storage (no ivars exposed) with `Mirror`.

== Seeing the result
#table(
  columns: (auto, 1fr), inset: 5pt, stroke: 0.4pt + luma(200),
  [*Where*], [*Method*],
  [simulator], [`_UICreateScreenUIImage` – matches `simctl` screenshots, glass included. After a `CATransaction.flush()` wait 2 frames and require two identical captures (the first can still show the previous commit).],
  [device, in-app], [pixels of the composited screen read back black; `UIScreen.snapshotView` keeps the glass as a live view (scrubbable, not saveable). `drawHierarchy` draws *no* glass anywhere.],
  [device, from the Mac], [`xcrun devicectl device capture screenshot` – the real composited screen (≈1.3 s per frame; black while the display is off).],
)

#pagebreak()

// ───────────────────────────── 3 ─────────────────────────────
= Hierarchy dumps

`.bone(into:)` places a `UIViewRepresentable` container, waits for layout, hosts the content in a
`UIHostingController` (or takes the window's root controller with `fromRoot: true`) and walks
`subviews` recursively. Per view it records class, superclass, layer and sublayers – the
*brief dump* (`output.txt`, depth encoded by leading `-`). With iOS 27 it also runs
`BoneCapture`:

- private UIKit introspection: `-_ivarDescription` (all ivars incl. SwiftUI host state),
  `-recursiveDescription` (LLDB's `po view`), `-_autolayoutTrace`;
- `Mirror` of the SwiftUI root value *and* of the `_UIHostingView` – Swift stored properties
  that no ivar list shows: the ViewGraph, renderer, preference bridges;
- a `Codable` node tree → `<name>_capture.json` / `.txt`.

On visionOS `.bone3D()` turns the same walk into RealityKit slabs (`BoneHierarchyBuilder`), and
`.bone3DFrom(_:)` rebuilds the graph from a brief dump made on another OS – the basis of the
cross-OS diffing.

// ───────────────────────────── 4 ─────────────────────────────
= Liquid Glass parameters

#fig(
  diagram(
    spacing: (12pt, 16pt),
    node-stroke: 0.6pt + luma(140), node-corner-radius: 4pt, node-inset: 6pt,
    edge-stroke: 0.7pt + luma(90), mark-scale: 70%,
    node((0, 0), hook([`.tune([.blurRadius: 0, …])`], [typed `GlassInput` (69 + 5 hidden) \ presets `.noShadow + .flat` \ `.raw([...])`, `.tune(file:)`]), fill: bone, stroke: 0.6pt + boneS, name: <tu>, width: 120pt),
    node((1, 0), card([find glass layers], [walk window → filter type \ `glassBackground`]), fill: white, name: <fi>, width: 110pt),
    node((2, 0), card([KVC write], [`filters.<name>.<input>` \ every ≈0.25 s (SwiftUI rebuilds)]), fill: white, name: <kv>, width: 120pt),
    node((2, 1), card([`CABackdropLayer`], [`glassBackground` inputs \ blur, refraction, rim, shadow…]), fill: app, name: <bl>, width: 120pt),
    node((1, 1), card([render server], [glass shaders, uniforms ← inputs]), fill: gpu, name: <rs>, width: 110pt),
    node((0, 1), hook([`.dumpGlass` · `.dumpShaders`], [read inputs · reflect `default.metallib` \ 228 fns (sim) / 249 (A16), ≈36 glass]), fill: bone, stroke: 0.6pt + boneS, name: <du>, width: 120pt),
    edge(<tu>, <fi>, "-|>"), edge(<fi>, <kv>, "-|>"), edge(<kv>, <bl>, "-|>"),
    edge(<bl>, <rs>, "-|>"), edge(<du>, <bl>, "--|>", stroke: 0.6pt + boneS, bend: -18deg),
    edge(<du>, <rs>, "--|>", stroke: 0.6pt + boneS),
  ),
  [Tuning and dumping the glass filter.],
)

*`.probeGlass`* answers “which inputs are live?” empirically. For every input name the SDK exports
(136 `kCAFilterInput…` constants extracted from `QuartzCore.tbd`) plus every key already on the
filter, it sets a few test values, captures the composited screen and counts the pixels that
changed around the glass. Inputs that changed nothing are tried again with the live hidden ones
switched on, because some only modulate another (an aberration height needs an amount). Result
on iOS 27: SwiftUI never sets `inputAberrationAmount`, `inputBleedColorMatrixFillColor` (and the
vibrant filter's `inputBackdropAware`, `inputClampPreserveHue`), yet they render.

*`.dumpShaders`* loads QuartzCore's own `default.metallib` with Metal and reflects the glass
fragment functions. The reflection-only API is missing in the simulator, so each fragment is
paired with QuartzCore's *own* vertex function (`variable_blur_vert_lpf`, `sdf_filter_vert_lpf`)
in a render pipeline and reflected from there; vertex functions must be specialised, or Metal
aborts. Each uniform field is matched to the filter input that feeds it by name
(`inner_refraction_amount ← innerRefractionAmount`).

// ───────────────────────────── 5 ─────────────────────────────
= Inspector and the 3D exploded view

`.boneInspector()` adds an overlay `UIWindow` (the pink drop). A tap is resolved against layer
frames, not views – on iOS 27 text is a bare `CGDrawingLayer`, an SF Symbol a `ColorShapeLayer`,
a gradient a `GradientLayer`, none with a `UIView`. Glass opens its filter inputs (slider, typed
value, toggle, colour, size, 4×5 colour matrix; hidden inputs first, in purple), anything else
its `CALayer` (opacity, corners, border, shadow, 3D transform, blend mode, filters). Edits go to
the real layer through the same KVC paths; *Copy Swift* emits the `.tune`/`.tuneLayers` line,
*Save JSON* a file `.tune(file:)` hot-reloads in the simulator. The overlay window makes itself
key on touch – SwiftUI buttons in a non-key window ignore taps.

#fig(
  diagram(
    spacing: (12pt, 14pt),
    node-stroke: 0.6pt + luma(140), node-corner-radius: 4pt, node-inset: 6pt,
    edge-stroke: 0.7pt + luma(90), mark-scale: 70%,
    node((0, 0), card([walk drawn layers], [text, shapes, gradients, glass; \ depth in the layer tree → z]), fill: white, name: <w>, width: 118pt),
    node((1, 0), card([render each alone], [sublayers hidden for the render; \ clipped by `masksToBounds` ancestors]), fill: white, name: <r>, width: 130pt),
    node((2, 0), card([glass stays glass], [backdrop tree + filter values \ `NSKeyedArchiver` round-trip → live clone]), fill: bone, stroke: 0.6pt + boneS, name: <g>, width: 130pt),
    node((1, 1), card([`CATransformLayer` scene], [planes at screen position, pushed back by depth; \ orbit / pan / pinch = one `sublayerTransform`]), fill: app, name: <t>, width: 200pt),
    node((1, 2), card([picking], [project each plane's corners with the same matrix; \ hit = max(`zPosition` × facing), facing = sign(`m33`)]), fill: white, name: <p>, width: 200pt),
    edge(<w>, <r>, "-|>"), edge(<r>, <t>, "-|>"), edge(<g>, <t>, "-|>"), edge(<w>, <g>, "-|>", bend: 25deg), edge(<t>, <p>, "-|>"),
  ),
  [3D exploded view. A cloned glass plane refracts the planes behind it in 3D, and edits preview on the clone.],
)

// ───────────────────────────── 6 ─────────────────────────────
= Motion: the AnimationKit clock

The iOS 26/27 glass morphs (button → menu, tab bar, search) are *not* CAAnimations:
`layer.speed` on the window does nothing to them. They are advanced inside the app by the private
AnimationKit: `LiquidMorphAnimation` / `MagicMorphAnimation`, ticked by
`InProcessAnimationManager` – *two* instances, one on the main thread and one on an animation
thread – from a display link calling `-displayLinkFire:`. Each tick advances by
`deltaTime = link.timestamp − time`, where `time` is a `Double` ivar. Animated values reach the
render server as `CAPresentationModifier`s on `InProcessAnimatableLayer`s;
`CAMatchPropertyAnimation`/`CAMatchMoveAnimation` tie the SDF elements to them.

#fig(
  diagram(
    spacing: (12pt, 16pt),
    node-stroke: 0.6pt + luma(140), node-corner-radius: 4pt, node-inset: 6pt,
    edge-stroke: 0.7pt + luma(90), mark-scale: 70%,
    node((0, 0), card([`CADisplayLink`], [60/120 Hz]), fill: white, name: <dl>, width: 70pt),
    node((1, 0), hook([swizzled tick], [`-displayLinkFire:` sets `time = timestamp − step`; step = 0 paused, 1/60 stepping, whole frames every N ticks in slow motion]), fill: bone, stroke: 0.6pt + boneS, name: <sw>, width: 130pt),
    node((2, 0), card([original IMP], [`deltaTime = timestamp − time` \ = exactly the clock's step]), fill: ak, name: <or>, width: 115pt),
    node((2, 1), card([`InProcessAnimationManager` ×2], [springs of `LiquidMorphAnimation` …]), fill: ak, name: <ma>, width: 140pt),
    node((1, 1), card([`InProcessAnimatableLayer`], [`CAPresentationModifier`s: \ blob bounds/position/cornerRadii, \ lens displacement + blur]), fill: ak, name: <al>, width: 130pt),
    node((0, 1), card([render server], [draws the frame]), fill: gpu, name: <rs>, width: 70pt),
    edge(<dl>, <sw>, "-|>"), edge(<sw>, <or>, "-|>"), edge(<or>, <ma>, "-|>"), edge(<ma>, <al>, "-|>"), edge(<al>, <rs>, "-|>"),
  ),
  [`BoneAnimationClock`: the tick still happens, but its length is Bone's.],
)

Details that took measurement:

- *Pause* = zero-length ticks. On a device a morph frozen from its start shows its *final* layout
  until one tick advances, so the clock auto-steps one frame when a manager's `TickEntry` count
  (Swift array count at storage + 16) rises while paused.
- *Slow motion* by tiny per-tick steps ran ≈5× too fast (per-tick smoothing inside AnimationKit);
  only stop-motion – whole 1/60 s frames every N ticks – is exact.
- *Settle at pause.* A manager that idles and wakes later catches up on lost time; if it skips
  steps the two managers' halves of a morph drift apart and the morph keeps retargeting. At pause
  every manager is caught up; a manager waking while paused still receives each step.
- iOS 26 glass controls (the system `Slider`) run on AnimationKit too and *freeze* with the clock
  – Bone's panels use their own `BoneSlider` (a `DragGesture`).

== Takes, scrubbing and values

#fig(
  diagram(
    spacing: (10pt, 14pt),
    node-stroke: 0.6pt + luma(140), node-corner-radius: 4pt, node-inset: 5pt,
    edge-stroke: 0.7pt + luma(90), mark-scale: 70%,
    node((0, 0), card([arm], [swizzled `sendEvent:` – a touch arms the clock for 2 s (at launch: the control's primary action after 1.2 s)]), fill: bone, stroke: 0.6pt + boneS, name: <a>, width: 100pt),
    node((1, 0), card([trigger], [a manager wakes from idle (> 0.1 s between ticks) or its `TickEntry` count rises]), fill: white, name: <tr>, width: 100pt),
    node((2, 0), card([frame 0], [screen captured just \ before the trigger]), fill: white, name: <f0>, width: 85pt),
    node((3, 0), card([step + capture, repeat], [one 1/60 step, then capture (simulator pixels, device `snapshotView`)]), fill: white, name: <st>, width: 95pt),
    node((3, 1), card([settle], [morph values (rounded to 0.01) still for 8 frames → end of take]), fill: white, name: <se>, width: 95pt),
    node((2, 1), card([scrub 0 → 1], [slider over the take; frames pre-decoded at 2×]), fill: app, name: <sc>, width: 85pt),
    node((0.5, 1), hook([`.dumpMorph` CSV], [`Mirror`: coordinator → layerContext → \ animatablePropertyStore → \ presentationModifiers (keyPath, value)]), fill: bone, stroke: 0.6pt + boneS, name: <dm>, width: 150pt),
    edge(<a>, <tr>, "-|>"), edge(<tr>, <f0>, "-|>"), edge(<f0>, <st>, "-|>"), edge(<st>, <se>, "-|>"),
    edge(<se>, <sc>, "-|>"), edge(<st>, <dm>, "--|>", stroke: 0.6pt + boneS, bend: 20deg),
  ),
  [`.morphScrubber()`: a take of the real morph, one exact frame per step, without manual steps.],
)

`.dumpMorph` writes the long format `frame,time,progress,layer,key,component,value`.
`NSValue`s are decoded by the *prefix* of their `objCType` (`{CGRect` contains `CGPoint` – a
substring match crashed) after stripping the struct name (`CACornerRadii` contains type-code
letters).

// ───────────────────────────── 7 ─────────────────────────────
= Driving Apple's morph on our own views: `.liquidMorph`

The menu's `LiquidMorphAnimation` has only a Swift API whose arguments are existentials of
AnimationKit's private protocols, so it cannot be called from outside. Its sibling
`_UIMagicMorphAnimation` (tab bar, search field) has an Objective-C door:

#fig(
  diagram(
    spacing: (10pt, 12pt),
    node-stroke: 0.6pt + luma(140), node-corner-radius: 4pt, node-inset: 5pt,
    edge-stroke: 0.7pt + luma(90), mark-scale: 70%,
    node((0, 0), card([both ends], [glass effect views \ (`UIGlassEffect`, capsule) \ hosting SwiftUI]), fill: app, name: <e>, width: 110pt),
    node((1, 0), card([init, client container], [`setClientContainerView:` – \ the morph's coordinate space]), fill: white, name: <i>, width: 120pt),
    node((2, 0), card([`morphTo:` source, reparent YES], [`UITargetedPreview` (visiblePath + \ `UIPreviewTarget`) → lifted into \ UIKit's `MagicMorphView`]), fill: white, name: <s>, width: 125pt),
    node((2, 1), card([unhide target, `morphTo:` target], [glass stretches between the shapes, \ contents blur across, lensing]), fill: ak, name: <t>, width: 125pt),
    node((1, 1), card([completion], [hide source, layout resumes]), fill: white, name: <c>, width: 120pt),
    edge(<e>, <i>, "-|>"), edge(<i>, <s>, "-|>"), edge(<s>, <t>, "-|>"), edge(<t>, <c>, "-|>"),
  ),
  [`-[_UIMagicMorphAnimation morphTo:reparentWithoutAnimation:alongsideAnimations:completion:]`, called through its IMP.],
)

#pagebreak()

// ───────────────────────────── 8 ─────────────────────────────
= Glass stretch: `.glassFlex(stretch:follow:)` in depth

```swift
Button("Glass") {}.buttonStyle(.glass).glassFlex(stretch: 6, follow: 12)
```

A glass button swells when pressed (stock 1.19×) and stretches toward a dragging finger
(1.23 × 1.13, shift +4 pt for a 170 pt drag). There is no public knob: in the iOS 27 SDK the
whole API is `Glass.interactive(_ isEnabled: Bool)` and `UIGlassEffect.interactive`. The private
driver is SwiftUI's `UIPlatformGlassFlexInteraction` (via `PlatformGlassInteractionProxy` and the
view graph), and `MorphAnimationSettings` – AnimationKit's tuning domain – is ignored by it.
`.glassFlex` therefore works one level lower: on the layer setters the interaction calls.

== What the interaction writes every frame

#fig(
  diagram(
    spacing: (12pt, 14pt),
    node-stroke: 0.6pt + luma(140), node-corner-radius: 4pt, node-inset: 5pt,
    edge-stroke: 0.7pt + luma(90), mark-scale: 70%,
    node((1, 0), card([`UIPlatformGlassFlexInteraction`], [press, hold, drag → springs]), fill: app, name: <fx>, width: 150pt),
    node((0, 1), card([content branch], [`UIPlatformGlassInteractionView` layer \ `setTransform:` / `setAffineTransform:` \ (scale, anchor 0,0) + `setPosition:`]), fill: white, name: <cb>, width: 150pt),
    node((2, 1), card([outline branch], [every layer under `SDFLayer` outside the content: \ container, `CABackdropLayer`, `CASDFLayer`, \ `SDFPortalLayer` – the same `setBounds:` + `setPosition:`]), fill: white, name: <ob>, width: 175pt),
    node((2, 2), card([shape element `CASDFElementLayer`], [held: bounds + `setCornerRadius:` (19.7 → 25.2) \ dragged: `mode = contents`, a 3× distance-field \ bitmap in a frame ≈9.5 pt larger]), fill: white, name: <el>, width: 175pt),
    node((0, 2), card([on release], [content setters stop for ≈1 s; \ the outline springs back frame by frame]), fill: white, name: <rl>, width: 150pt),
    edge(<fx>, <cb>, "-|>"), edge(<fx>, <ob>, "-|>"), edge(<ob>, <el>, "-|>"), edge(<cb>, <rl>, "--|>"),
  ),
  [The two branches, measured on the phone with setter counters: content 287/288/186 calls (`setAffineTransform:`/`setTransform:`/`setPosition:`), outline 265/265 (`setBounds:`/`setPosition:`) in one press.],
)

== The hooks
`CALayer`'s `setTransform:`, `setAffineTransform:`, `setPosition:`, `setBounds:` and
`setCornerRadius:` are swapped once, app-wide. Each hook first asks *role(of: layer)*: the
content (its delegate is a `UIPlatformGlassInteractionView`), the shape element, another outline
layer (an `SDFLayer` within six superlayers, not inside the content), or nothing – then whether
the layer's resting centre lies in a `.glassFlex` anchor. Everything else passes through with
the original IMP. A depth counter lets setter calls nested inside a mapped call pass through, so
each value is mapped exactly once (the first version double-mapped and flipped 61 ↔ 76 pt).

== The mapping
With $s$ the stock scale (content transform, or outline size ÷ resting size $r$), $k$ = `stretch`
and $f$ = `follow`:

$ s' = 1 + k (s - 1) $
$ "shift" = p + (s - 1) r / 2 #h(2em) p' = -(s' - 1) r / 2 + f dot "shift" $

The content's transform uses $s'$; its position $p'$. Every outline layer gets size $r s'$ and
position $p'$ – and its *bounds origin* too: the stock origin mirrors the position (children
cancel it), so leaving it unmapped shifted the glass up-left by exactly the growth.

== The shape element in two modes

#fig(
  cetz.canvas(length: 1cm, {
    import cetz.draw: *
    // held: rounded rectangle = the shape
    content((1.6, 3.15), text(size: 8pt, weight: "bold")[held: `mode = bounds`])
    rect((0, 0.6), (3.2, 2.4), radius: 0.9, stroke: 0.9pt + rgb("#3c8d50"), fill: rgb("#e6f4ea"))
    content((1.6, 1.5), text(size: 7.5pt)[shape = element \ radius 25.2 → 52.8])
    content((1.6, 0.25), tiny(text(fill: luma(90))[bounds + `cornerRadius`, mapped together]))

    // dragged: bitmap frame bigger than the blob
    content((6.6, 3.15), text(size: 8pt, weight: "bold")[dragged: `mode = contents`])
    rect((4.6, 0.25), (8.6, 2.65), stroke: (paint: rgb("#d81b60"), dash: "dashed", thickness: 0.8pt), fill: rgb("#fde7f0"))
    rect((5.1, 0.7), (8.1, 2.2), radius: 0.7, stroke: 0.9pt + rgb("#3c8d50"), fill: rgb("#e6f4ea"))
    content((6.6, 1.45), text(size: 7.5pt)[blob 74.8 × 51.1 \ at (−6.7, −4.6)])
    content((8.85, 2.3), anchor: "west", tiny(text(fill: rgb("#d81b60"))[element frame 94 × 70 \ at (−16, −14): bitmap \ 282 × 210 px, 3×]))
    content((8.85, 0.9), anchor: "west", tiny[margin ≈ 9.5 pt holds the \ outside of the distance field \ (zero / one value distance \ 8.9 / −16 pt)])
  }),
  [Stock geometry of the glass shape while held and while dragged (values from the phone, one frame).],
)

Mapping the element like the other layers blew the 9.5 pt margin up with the shape: a second,
much larger glass body around the correct one (the lighter “plate” in the user's screenshot).
The element is therefore scaled *about the shape*: with the stock shape frame $S$ (from the
outline layers) and its mapped frame $S'$, $k_"xy" = S' / S$ per axis, and

$ E' = S'_"origin" + (E_"origin" - S_"origin") dot k_"xy", #h(2em) |E'| = |E| dot k_"xy", #h(2em) rho' = rho dot min(S') / min(S) $

which reduces to the plain mapping in bounds mode ($E = S$) and keeps a capsule a capsule
(radius 52.8 = half of 105.5).

== Ordering within a frame

#fig(
  diagram(
    spacing: (9pt, 22pt),
    node-stroke: 0.6pt + luma(140), node-corner-radius: 3pt, node-inset: 4pt,
    edge-stroke: 0.7pt + luma(90), mark-scale: 65%,
    node((0, 0), small[element \ position], fill: rgb("#fde7f0"), name: <a>, width: 58pt),
    node((1, 0), small[element \ bounds], fill: rgb("#fde7f0"), name: <b>, width: 58pt),
    node((2, 0), small[container \ bounds], fill: white, name: <c>, width: 58pt),
    node((3, 0), small[container \ position], fill: white, name: <d>, width: 58pt),
    node((4, 0), small[backdrop, SDF, \ portal …], fill: white, name: <e>, width: 58pt),
    node((5, 0), small[content: \ affine, position], fill: white, name: <f>, width: 64pt),
    edge(<a>, <b>, "-|>"), edge(<b>, <c>, "-|>"), edge(<c>, <d>, "-|>"), edge(<d>, <e>, "-|>"), edge(<e>, <f>, "-|>"),
    edge(<d>, (3, 1), (0.5, 1), <a>, "-|>", stroke: 0.7pt + boneS, label: small[Bone: re-map the element with this frame's shape], label-side: left, label-pos: 0.5),
  ),
  [The element receives its values *before* the shape's. Mapped with last frame's shape, the finger-shift term multiplied a one-frame lag by `follow` (12) into a 6.7 pt offset; it is re-mapped when the container's values arrive.],
)

On release UIKit sets no content values for about a second while the outline still springs back;
whenever the content's own setters have been quiet for > 50 ms, it follows the outline (scale and
position from the outline's stock size and position).

== Bugs on the way – each found by a phone measurement

#table(
  columns: (auto, 1fr, 1fr), inset: 5pt, stroke: 0.4pt + luma(200),
  fill: (x, y) => if y == 0 { luma(235) },
  [*Symptom*], [*Cause*], [*Fix*],
  [label scaled, glass stock-size], [only the content was hooked], [outline branch: every layer under `SDFLayer`],
  [glass flipped 61 ↔ 76 pt], [a nested setter mapped twice], [depth guard: nested calls pass through],
  [“behaved the old way”], [`NSClassFromString("SDFLayer")` never matched], [match the Swift class by name],
  [glass shifted up-left], [bounds origin left stock], [map the origin like the position],
  [label stays big after release], [content gets no setters for ≈1 s], [content follows the outline],
  [rounded rectangle, dark bands], [corner radius left stock (25 on a 164×106 shape)], [scale `cornerRadius`],
  [asymmetric glass while dragging], [element set before the shape: lag × `follow`], [re-map after the container],
  [huge outer glass while dragging], [bitmap frame's 9.5 pt margin amplified], [scale the element about the shape],
)

== Result (iPhone 14 Pro, stretch 6, follow 12)
Pressed: glass and label 164 × 106 pt together (stock 77 × 50). Dragged: ≈150 × 105 following
the finger, one blob, no plate, glass = label every frame; release bounce amplified (down to
≈35 × 23) and back to 61 × 39. Not adjusted: the distance values inside the bitmap, so the rim's
refraction band keeps its stock width.

// ───────────────────────────── 9 ─────────────────────────────
= Measuring on the phone

The simulator's touch injection became unreliable for long presses and drags, so the glass stretch
was measured on the iPhone with a probe build (a scratch copy of the project – the library itself
contains no probe code):

- *Launch with arguments:* `xcrun devicectl device process launch … <bundle> -- -flex -flexcheck`.
  Without the `--` devicectl parses `-flex` as its own `-f -l…` options and the app gets nothing.
- *Per-frame log:* a `CADisplayLink` in the app logs the content's and the backdrop's on-screen
  rectangle (model and presentation) when they change, plus animation keys and presentation
  modifiers under the glass; the file is rewritten every second, so a run that stops is visible.
- *Property dumps:* every property of every layer under the `SDFLayer` host, at rest and at the
  widest press – the diff showed `cornerRadius` 19.7 → 25.2 on the element.
- *Filter-input change log:* all filter inputs and SDF properties under both buttons, changes only
  – it showed `mode = contents` and the distance values appearing exactly when a drag starts.
- *Setter traces:* who calls which setter, with role and anchor decisions – it showed the outline
  hooks returning “no role” (the `SDFLayer` class bug) and the element-before-shape order.
- *Screenshots from the Mac* every ≈1.3 s during the gesture (`devicectl … capture screenshot`):
  the only view of what the render server really composited.

// ───────────────────────────── 10 ─────────────────────────────
= Novelty – what is new, and how sure

Searches on 8–11 October 2026: web (several phrasings, Chinese and Japanese sources), Apple
Developer Forums, WWDC sessions, Medium/Substack write-ups, Reddit/HN/X, jailbreak tweak news,
Swift Package Index, GitHub repository and code search for the private names and techniques, and
the iOS 27 SDK's own Swift interfaces.

#table(
  columns: (0.75fr, 1.3fr, 1.15fr), inset: 5pt, stroke: 0.4pt + luma(200),
  fill: (x, y) => if y == 0 { luma(235) } else if x == 2 { newc },
  [*Area*], [*Closest prior art*], [*New in Bone*],
  [Glass parameters \ `.tune` \ `.dumpGlass` \ `.probeGlass`], [Cranpose `NativeTrace` (iOS, archives and zeroes live inputs), SSFSKIM/designer `LayerDump` (macOS, read-only), CAFilterBuiltins (own filter, 55 inputs), reimplementations (ShatteredGlass, CustomLiquidGlass, LiquidGlassKit)], [a SwiftUI modifier API that tunes the *system* glass in place, typed inputs and presets; empirically found hidden live inputs],
  [Shader uniforms \ `.dumpShaders`], [lennondotw/interaction-lab liquid-glass-internals (macOS, metallib uniforms)], [in-app on iOS (simulator + device) via pipeline reflection; uniform ↔ filter-input mapping],
  [3D exploded view], [Xcode, Reveal, Lookin (Mac); #link("https://github.com/alexslee/DesignReviewer")[DesignReviewer], InAppViewDebugger (in-app, UIView snapshots)], [live glass in 3D (archived clones), planes per *drawn layer*, glass tuning from a plane],
  [Morph clock, timeline \ `.morphScrubber` \ `.dumpMorph`], [`layer.speed`/`timeOffset` pausing (#link("https://developer.apple.com/library/ios/qa/qa1673/_index.html")[QA1673], #link("https://github.com/mathewsanders/Scrubber")[Scrubber]) – no effect on these morphs; nothing published on AnimationKit's in-process animation manager or the liquid morph], [first public pause, step, scrub and value dump of the real system morphs],
  [`.liquidMorph`], [no separate search made], [Apple's magic morph on any two SwiftUI views (through `morphTo:`)],
  [Glass stretch \ `.glassFlex`], [own stretch effects (#link("https://github.com/Polarizz/Gelatin")[Gelatin], #link("https://github.com/DnV1eX/LiquidGlassKit")[LiquidGlassKit], web/Flutter/Android rebuilds); flex *removed* (#link("https://github.com/Apollo-Reborn/Apollo-Reborn")[Apollo-Reborn]); flex kept while reskinning (#link("https://github.com/willfaust/Madeira")[Madeira GlassSkin])], [amplifying the *system* flex in place with the real outline following; the two branches, the element's contents mode with its 9.5 pt margin, the per-frame order, the quiet release],
)

== Glass stretch – the two deep passes in detail

- *Public API:* the iOS 27 SDK (`SwiftUICore.swiftinterface`, `UIGlassEffect.h`) exposes only an
  on/off `interactive`; WWDC26 sessions add no strength parameter. Developers on the
  #link("https://developer.apple.com/forums/tags/swiftui?page=16")[Apple forums] ask how to *stop*
  the stretch on draggable glass; no answer gives a knob.
- *Code using the private names:* `UIPlatformGlassFlexInteraction` appears only in header dumps and
  in Apollo-Reborn (removes the interaction from Edit/Done buttons).
  `UIPlatformGlassInteractionView` is only located or labelled: #link("https://github.com/ericbomgardner/tabless")[tabless]
  (frame for layout), #link("https://github.com/DataDog/dd-sdk-ios")[DataDog session replay]
  (layer semantics), #link("https://github.com/GenericJam/mob")[GenericJam/mob] (tree statistics),
  #link("https://github.com/Vercantez/openuikit")[openuikit] (geometry notes),
  #link("https://github.com/wix/Detox/issues/4982")[Detox \#4982] (glass layers occlude taps).
  No hooks of its setters, no `SDFLayer` bounds hooks, no `CASDFElementLayer` radius hooks.
- *Distance-field keys* (`contentsZeroValueDistance`, `contentsOneValueDistance`) appear only in
  header dumps, rebuilds and a probe of glass at rest – nobody documents the drag-time
  `mode = contents` switch.
- *Teardowns:* #link("https://github.com/AlexStrNik/ShatteredGlass")[ShatteredGlass] (macOS 26,
  static layer stack), #link("https://www.natashatherobot.com/p/liquidglass-button-ios-26")[“Anatomy of a LiquidGlass Button”]
  (public modifiers only).
- *Packages:* all 15 “liquid glass” packages on
  #link("https://swiftpackageindex.com/search?query=liquid+glass")[Swift Package Index] restyle or
  rebuild; none changes the system stretch. Jailbreak tweaks
  (#link("https://www.idownloadblog.com/2025/06/30/cc26/")[CC26], Liquidass) backport the look.

#note[*How sure.* “First” here means *first public*: private repositories, unpublished tweaks and
Apple's own internal tools (AnimationKit ships a tuning domain, `MorphAnimationSettings`, with
`showMeshes` and `speed`) cannot be searched. The internals in sections 6 and 8 were measured on
one iPhone 14 Pro with iOS 27 (24A437) and the iOS 27 simulator.]
