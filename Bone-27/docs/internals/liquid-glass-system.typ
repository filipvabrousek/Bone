// Liquid Glass on iOS 26/27 – the whole system, as found with Bone.
// Compile: typst compile liquid-glass-system.typ   (→ liquid-glass-system.pdf)

#import "@preview/fletcher:0.5.8" as fletcher: diagram, node, edge

#set page(width: auto, height: auto, margin: 18pt, fill: white)
#set text(font: ("SF Pro Text", "Helvetica Neue", "Arial"), size: 8.5pt)

// palette
#let app   = rgb("#e8f0fe")   // app process
#let ak    = rgb("#e6f4ea")   // AnimationKit (motion)
#let rs    = rgb("#eceff1")   // render server
#let gpu   = rgb("#fff4e5")   // Metal / GPU
#let bone  = rgb("#fde7f0")   // Bone hooks
#let boneS = rgb("#d81b60")

#let code(t) = text(font: ("SF Mono", "Menlo"), size: 7.5pt, t)
#let box2(title, body) = align(left)[*#title* \ #body]
#let hook(title, body) = align(left)[#text(fill: boneS)[*#title*] \ #body]
#let group(t) = align(top + left, text(size: 10pt, weight: "bold", t))

#align(center, text(size: 15pt, weight: "bold")[Liquid Glass — the whole system])
#align(center, text(size: 9pt, fill: luma(90))[
  iOS 26/27 · as measured with Bone (simulator + iPhone 14 Pro, A16) ·
  #text(fill: boneS)[pink = where Bone hooks in] · private API, research only
])
#v(8pt)

#diagram(
  spacing: (14pt, 22pt),
  node-stroke: 0.6pt + luma(140),
  node-corner-radius: 5pt,
  node-inset: 7pt,
  edge-stroke: 0.8pt + luma(80),
  mark-scale: 70%,

  // ───────────────────────── App process ─────────────────────────
  // API
  node((1, 0), box2([SwiftUI], [#code(".glassEffect()") · #code("GlassEffectContainer") \ #code(".buttonStyle(.glass)") · #code("Menu")]),
       fill: white, name: <swiftui>, width: 150pt),
  node((2, 0), box2([UIKit], [#code("UIVisualEffectView") + #code("UIGlassEffect") \ #code("UIButton.Configuration.glass()")]),
       fill: white, name: <uikit>, width: 150pt),

  // UIKit glass views
  node((1, 1), box2([Glass views], [#code("UIPlatformGlassInteractionView") \ #code("_UILiquidLensView") (slider lens) \ #code("HostingUIButton") (a glass Menu)]),
       fill: white, name: <views>, width: 150pt),
  node((2, 1), box2([Context menu], [#code("_UIContextMenuLiquidMorph-") \ #code("PresentationAnimation") \ → #code("_UILiquidMorphAnimation")]),
       fill: white, name: <ctxmenu>, width: 150pt),

  // layer tree
  node((0, 2), box2([#code("CABackdropLayer")], [samples what is behind \ filter #code("glassBackground") – ~70 inputs: \ blur, refraction in/out, highlights, \ rim, shadow, tint, bleed (+5 hidden: \ #code("aberrationAmount") …)]),
       fill: white, name: <backdrop>, width: 150pt),
  node((1, 2), box2([#code("CASDFLayer") · #code("CASDFElementLayer")], [the shape as a signed distance field \ (#code("inputSourceSublayerName \"@0\"")) \ → smooth merging of glass shapes]),
       fill: white, name: <sdf>, width: 150pt),
  node((2, 2), box2([Vibrancy · interaction], [#code("vibrantColorMatrix") – legible text on glass \ #code("glassForeground") – only while dragged \ (slider lens)]),
       fill: white, name: <vibrant>, width: 150pt),

  node((1, 3), box2([#code("CATransaction") commit], [layer tree + filter inputs → render server]),
       fill: white, name: <commit>, width: 150pt),

  // AnimationKit
  node((4, 1), box2([Morph animations], [#code("LiquidMorphAnimation") (menus, drop step) \ #code("MagicMorphAnimation") (tab bar, search) \ settings: #code("MorphAnimationSettings") \ (PTSettings: springs 0.3 s / 0.8)]),
       fill: white, name: <morphs>, width: 165pt),
  node((4, 2), box2([#code("InProcessAnimationManager") ×2], [main thread + animation thread \ ticked by #code("CADisplayLink") #code("-displayLinkFire:") \ each tick: #code("deltaTime = timestamp − time")]),
       fill: white, name: <managers>, width: 165pt),
  node((4, 3), box2([#code("InProcessAnimatableLayer")], [springs → #code("CAPresentationModifier")s: \ blob #code("bounds") · #code("position") · #code("cornerRadii") \ #code("LensingLayer"): #code("displacementMap") + #code("gaussianBlur") \ #code("LensingPortalContainer"): #code("sublayerTransform")]),
       fill: white, name: <animlayer>, width: 165pt),
  node((2.2, 3), box2([#code("CAMatch…Animation")], [SDF elements follow \ the animated layers]),
       fill: white, name: <match>, width: 105pt),

  // ───────────────────────── Render server ─────────────────────────
  node((0.5, 5), box2([Compositor], [backdrop sample → blur → refraction along \ the SDF edge → highlights, rim, shadow → \ vibrancy · presentation modifiers applied]),
       fill: white, name: <compositor>, width: 190pt),
  node((2.5, 5), box2([QuartzCore #code("default.metallib") (Metal)], [228 functions (simulator) · 249 (A16) \ ~36 glass · uniforms ↔ filter inputs \ vertex: #code("variable_blur_vert_lpf"), #code("sdf_filter_vert_lpf")]),
       fill: gpu, name: <metallib>, width: 190pt),
  node((1.5, 6), box2([GPU → display], [one composited frame · ProMotion 120 Hz (A16) \ only here does glass exist as pixels]),
       fill: gpu, name: <display>, width: 190pt),

  // ───────────────────────── groups ─────────────────────────
  node(enclose: (<swiftui>, <uikit>, <views>, <ctxmenu>, <backdrop>, <sdf>, <vibrant>, <commit>, <morphs>, <managers>, <animlayer>, <match>),
       fill: app, stroke: 0.8pt + rgb("#4a78c2"), inset: 16pt, layer: -2, snap: false,
       group[App process]),
  node(enclose: (<morphs>, <managers>, <animlayer>),
       fill: ak, stroke: 0.6pt + rgb("#3c8d50"), inset: 8pt, layer: -1, snap: false,
       align(bottom + right, text(size: 8.5pt, weight: "bold", fill: rgb("#2e7d32"))[AnimationKit · motion])),
  node(enclose: (<compositor>, <metallib>, <display>),
       fill: rs, stroke: 0.8pt + luma(120), inset: 16pt, layer: -2, snap: false,
       align(bottom + left, text(size: 10pt, weight: "bold")[Render server (out of process)])),

  // ───────────────────────── flow ─────────────────────────
  edge(<swiftui>, <views>, "-|>"),
  edge(<uikit>, <views>, "-|>"),
  edge(<swiftui>, <ctxmenu>, "-|>"),
  edge(<views>, <backdrop>, "-|>"),
  edge(<views>, <sdf>, "-|>"),
  edge(<views>, <vibrant>, "-|>"),
  edge(<backdrop>, <commit>, "-|>"),
  edge(<sdf>, <commit>, "-|>"),
  edge(<vibrant>, <commit>, "-|>"),
  edge(<ctxmenu>, <morphs>, "-|>"),
  edge(<morphs>, <managers>, "-|>"),
  edge(<managers>, <animlayer>, "-|>", label: text(size: 7pt)[every frame], label-side: left),
  edge(<animlayer>, <match>, "-|>"),
  edge(<match>, <sdf>, "-|>", bend: 25deg),
  edge(<commit>, <compositor>, "-|>", label: text(size: 7pt)[layer tree], label-side: right),
  edge(<animlayer>, (4, 5), <compositor>, "-|>", label: text(size: 7pt)[presentation modifiers], label-pos: 0.3),
  edge(<compositor>, <metallib>, "<|-|>", label: text(size: 7pt)[runs]),
  edge(<compositor>, <display>, "-|>"),

  // ───────────────────────── Bone hooks ─────────────────────────
  node((6, 0.9), hook([#code(".liquidMorph(to:isPresented:)")], [#code("_UIMagicMorphAnimation") \ #code("morphTo:(UITargetedPreview)") \ any two views, in glass]),
       fill: bone, stroke: 0.7pt + boneS, name: <h-liquid>, width: 150pt),
  node((-1.7, 1.2), hook([#code(".tune") · panel · #code(".probeGlass")], [set / probe filter inputs live \ #code("filters.glassBackground.") \ #code("    input…")]),
       fill: bone, stroke: 0.7pt + boneS, name: <h-tune>, width: 150pt),
  node((-1.7, 2.4), hook([#code(".dumpGlass") · #code(".dumpLayers") · 3D], [read the layer tree & inputs \ 3D: glass cloned via #code("NSKeyedArchiver")]),
       fill: bone, stroke: 0.7pt + boneS, name: <h-dump>, width: 150pt),
  node((6, 2), hook([#code("BoneAnimationClock")], [swizzles #code("-displayLinkFire:"), \ rewrites #code("time") → pause, step, \ slow motion · #code(".morphTimeline")]),
       fill: bone, stroke: 0.7pt + boneS, name: <h-clock>, width: 150pt),
  node((6, 3.3), hook([#code(".dumpMorph") · #code(".morphScrubber")], [reads the presentation modifiers \ per frame → CSV · takes]),
       fill: bone, stroke: 0.7pt + boneS, name: <h-morph>, width: 150pt),
  node((3.6, 6), hook([#code(".dumpShaders")], [reflects the metallib: \ uniform structs ↔ inputs]),
       fill: bone, stroke: 0.7pt + boneS, name: <h-shaders>, width: 120pt),
  node((-1.2, 6), hook([captures], [#code("_UICreateScreenUIImage") (simulator) \ #code("snapshotView") (device: pixels read black) \ #code("drawHierarchy") draws no glass]),
       fill: bone, stroke: 0.7pt + boneS, name: <h-capture>, width: 150pt),

  edge(<h-liquid>, <morphs>, "--|>", stroke: 0.7pt + boneS),
  edge(<h-tune>, <backdrop>, "--|>", stroke: 0.7pt + boneS),
  edge(<h-dump>, <backdrop>, "--|>", stroke: 0.7pt + boneS),
  edge(<h-clock>, <managers>, "--|>", stroke: 0.7pt + boneS),
  edge(<h-morph>, <animlayer>, "--|>", stroke: 0.7pt + boneS),
  edge(<h-shaders>, <metallib>, "--|>", stroke: 0.7pt + boneS),
  edge(<h-capture>, <display>, "--|>", stroke: 0.7pt + boneS),
)
