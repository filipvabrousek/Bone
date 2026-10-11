# Changelog

All notable changes to the Bone library (`library/`). The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Bone has no version numbers yet, so
entries are grouped by date; commit links point to
[github.com/filipvabrousek/Bone](https://github.com/filipvabrousek/Bone).

Research / simulator use only – Bone uses private API and never belongs in an App Store build.

## Unreleased

Nothing yet.

## 2026-10-11

### Added
- `.dumpGlass(_:only:after:)` and `.tune(_:log:)` on **macOS** (`BoneMac.swift`): macOS 26+ draws Liquid
  Glass with the same SDF layers and `glassBackground` filter as iOS. Verified on macOS 27
  (`captures/mac-*.txt`).
- A **Platforms** table in the readmes and on the getting-started page: which modifier runs on iOS,
  watchOS, visionOS and macOS, and what was tested.
- `.dumpGlass(_:only:after:)` and `.tune(_:log:)` on **watchOS**, with the same types as on iOS
  (`GlassInput`, `GlassTuning`, presets). They act on the glass inside the modified view's frame,
  found through the Objective-C runtime; `.tune` re-applies 8× a second. Verified on the watchOS 27
  simulator (`captures/watch-glass.txt`, `watch-tune.txt`, `watch-tuned.txt`).
- `CHANGELOG.md`, backfilled from the repository history.
- `.bone(into:)` on **watchOS** (`BoneWatch.swift`): the real UIKit view tree behind a SwiftUI view on
  Apple Watch, through the Objective-C runtime, in the iOS brief format plus a layer tree with every
  filter's type and input keys. `wbone(name:)` remains as a deprecated alias.
  ([e508c56](https://github.com/filipvabrousek/Bone/commit/e508c56))
- `.glassFlex(stretch:follow:)` – stretches the system glass button's own press swell and drag
  stretch; the glass outline (backdrop, SDF layers, shape element in both its modes) grows with the
  label. ([4d4159a](https://github.com/filipvabrousek/Bone/commit/4d4159a))

### Changed
- The watchOS glass engine became `BoneGlassRuntime.swift`, shared by watchOS and macOS; the shared
  glass types (`BoneGlassTuning.swift`, `BoneGlassInputs.swift`) build on macOS too.
- `GlassValue`, `GlassTuning`, `BoneFilterInputs` and the input-value formatter moved into the
  shared `BoneGlassTuning.swift`; `GlassInput` (`BoneGlassInputs.swift`) now compiles on watchOS too.
- Every library file is excluded on watchOS (`canImport(UIKit) && !os(watchOS)`; the AppKit branches
  are `#elseif canImport(AppKit)`), because `canImport(UIKit)` is true there while `UIView` and
  `CALayer` are unavailable. ([e508c56](https://github.com/filipvabrousek/Bone/commit/e508c56))
- `readme.md` is a short overview; the details moved to `Bone-27/docs/` (one page per topic) and
  `Bone-27/docs/internals/`. ([bbf667a](https://github.com/filipvabrousek/Bone/commit/bbf667a))

### Fixed
- The library builds for **visionOS** again. Since the timeline (2026-10-10) the inspector panel
  referred to `BoneTimeline` and `BoneSlider`, which are not built on visionOS; the timeline parts of
  the panel are now iOS-only and `BoneSlider` has its own file (`BoneSlider.swift`).
- Timeline on a 120 Hz device: every animation manager is caught up when the clock pauses, and a
  take ends when the morph's own values settle, so a take no longer keeps retargeting.
  ([4d4159a](https://github.com/filipvabrousek/Bone/commit/4d4159a))

### Removed
- The root-level `watchOSSpecific.swift` (a regex over `dump()`), replaced by `BoneWatch.swift`.
  ([e508c56](https://github.com/filipvabrousek/Bone/commit/e508c56))

## 2026-10-10

### Added
- `.liquidMorph(to:isPresented:)` – Apple's Liquid Glass morph (`_UIMagicMorphAnimation`) between any
  two SwiftUI views. ([00cbd4d](https://github.com/filipvabrousek/Bone/commit/00cbd4d))
- `.dumpMorph(_:)` – a morph's animated values (blob bounds, position, corner radii, lens
  displacement and blur) frame by frame as CSV.
  ([01522e6](https://github.com/filipvabrousek/Bone/commit/01522e6))
- Timeline (`BoneAnimationClock`, `BoneTimeline`): pause, step, slow down and record the Liquid Glass
  morphs by rewriting AnimationKit's clock; `.morphTimeline()` and `.morphScrubber()` (records the
  morph on launch and gives a 0–1 scrubber); `BoneSlider`, since system sliders freeze with the clock.
  ([95873ea](https://github.com/filipvabrousek/Bone/commit/95873ea))
- 3D exploded view: glass planes are live glass clones (`NSKeyedArchiver`), planes are clipped like
  the app clips them, a `List` demo (`-list`).
  ([e003177](https://github.com/filipvabrousek/Bone/commit/e003177))

### Fixed
- 3D picking uses `zPosition` × facing (sign of the rotation's `m33`).
  ([e003177](https://github.com/filipvabrousek/Bone/commit/e003177))

## 2026-10-09

### Added
- 3D exploded view in the inspector: every drawn layer as a plane, orbit/pan/zoom, tap to tune.
  ([6402e48](https://github.com/filipvabrousek/Bone/commit/6402e48))
- `.dumpShaders(_:matching:)` and `.dumpGlass(_:full: true)` – the glass shaders' own uniforms,
  reflected from QuartzCore's `default.metallib`, mapped to filter inputs.
  ([6402e48](https://github.com/filipvabrousek/Bone/commit/6402e48))

## 2026-10-08

### Added
- `.boneInspector()` – tap text or glass (Auto mode) and adjust it with sliders.
  ([25cab90](https://github.com/filipvabrousek/Bone/commit/25cab90))
- `.probeGlass(_:after:)` – which glass inputs change the pixels, including hidden ones SwiftUI never
  sets (`inputAberrationAmount`, `inputBleedColorMatrixFillColor`); `BoneFilterInputNames.swift`
  (136 SDK input names). ([e172adb](https://github.com/filipvabrousek/Bone/commit/e172adb))
- `.glassPanel()` – live glass editor (sliders, colours, colour matrix, Copy Swift, Save JSON).
  ([e172adb](https://github.com/filipvabrousek/Bone/commit/e172adb))
- `.tune(file:)` with JSON hot reload in the simulator; filter-prefixed raw keys
  (`"vibrantColorMatrix.inputColorMatrix"`); `GlassInput` +5 hidden cases; `.aberration` preset.
  ([e172adb](https://github.com/filipvabrousek/Bone/commit/e172adb))
- `.tuneLayers(_:where:)` / `.dumpLayers(_:)` and the panel's Layer mode – filters, blend modes,
  transforms and contents on the layers of any SwiftUI view.
  ([e172adb](https://github.com/filipvabrousek/Bone/commit/e172adb))
- `.dumpGlass(_:only:after:)` – the glass filter's inputs with values.
  ([c5631fc](https://github.com/filipvabrousek/Bone/commit/c5631fc))
- `.tune(_:)` – override Liquid Glass parameters (`GlassInput`, 69 inputs, presets).
  ([9776e37](https://github.com/filipvabrousek/Bone/commit/9776e37))

### Removed
- `.getLuminence` (luminance probe), added the same day.
  ([c5631fc](https://github.com/filipvabrousek/Bone/commit/c5631fc))

## 2026-06-12

### Added
- `BoneCapture` – deep capture on iOS 27: `_ivarDescription`, `recursiveDescription`,
  `_autolayoutTrace`, `Mirror` of the SwiftUI root and the hosting view; `.json` dumps; timestamped
  captures and `briefoutput.txt` to Documents and `<project>/captures/`.
  ([c6820bc](https://github.com/filipvabrousek/Bone/commit/c6820bc))
- visionOS: `.bone3D(into:)` (live 3D hierarchy) and `.bone3DFrom(_:)` (3D graph from a dump file);
  `BriefDump` parser, `HierarchyBuilder`, `VisionModel`, `BoneVisionUI`.
  ([c6820bc](https://github.com/filipvabrousek/Bone/commit/c6820bc))
- The `Bone-27` sample project. ([93f0033](https://github.com/filipvabrousek/Bone/commit/93f0033))

### Removed
- The old `sample_project` (UnderSwiftUILibrary). ([89164dd](https://github.com/filipvabrousek/Bone/commit/89164dd))

## 2025-09-05

### Added
- `.bone(into:fromRoot:)` – dump from the window's root view controller instead of the wrapped view.
  ([0e35327](https://github.com/filipvabrousek/Bone/commit/0e35327),
  [2638038](https://github.com/filipvabrousek/Bone/commit/2638038))

## 2025-06-19

### Added
- `watchOSSpecific.swift` – `wbone(name:)`, view type names on watchOS from `dump()` of the visible
  interface controller. ([53fa6de](https://github.com/filipvabrousek/Bone/commit/53fa6de))

### Changed
- The dump footer names the OS (`OS: iOS:26`, `OS: visionOS:…`).
  ([cd27862](https://github.com/filipvabrousek/Bone/commit/cd27862))

## 2025-06-13

### Fixed
- Crash on iOS 26 when a sublayer has no contents.
  ([360d4a1](https://github.com/filipvabrousek/Bone/commit/360d4a1),
  [8dce996](https://github.com/filipvabrousek/Bone/commit/8dce996))

## 2024-02-29

### Changed
- Overlay: data-source and legend buttons, show/hide subviews, credits; output path printed as
  `OUTPUT FILE:`. ([418dd28](https://github.com/filipvabrousek/Bone/commit/418dd28),
  [46ce167](https://github.com/filipvabrousek/Bone/commit/46ce167))

## 2024-02-28

### Added
- First public release: `.bone(into:)` dumps the UIKit views behind a SwiftUI view – class,
  superclass, layer, sublayers, contents, list data sources – to a text file and shows them as an
  expandable overlay with coloured debug borders (`FrameworkUI`, `FrameworkModel`, `CommonViews`,
  `Extensions`). ([835eb91](https://github.com/filipvabrousek/Bone/commit/835eb91))

### Changed
- `dump(into:)` renamed to `bone(into:)`. ([a3226a5](https://github.com/filipvabrousek/Bone/commit/a3226a5))

## 2022 – 2024

Bone began as *UnderSwiftUI* (`FrameworkUI.swift`, June 2022), a private experiment in dumping the
views SwiftUI creates; `CommonViews.swift` and a watchOS target followed in January 2024.
