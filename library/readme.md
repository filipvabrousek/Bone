# Bone

Research toolkit for looking underneath SwiftUI: the UIKit views and Core Animation layers it
renders into, the private Liquid Glass filter and its shaders, and the AnimationKit engine that
animates the glass.

**Install:** add the Swift package `https://github.com/filipvabrousek/Bone` (branch `main`) and
`import Bone` – or copy this folder into your project and add it to all targets.

![The system's glass button stretched 6× by .glassFlex while dragged, stock on the left](https://raw.githubusercontent.com/filipvabrousek/Bone/main/Bone-27/captures/glass-flex.png)

> **Research / simulator use only.** Bone uses private classes, selectors, ivars and Core Animation
> keys. Never ship it in an App Store build; names change between OS releases.
> It compiles only in Debug builds (empty in Release), so wrap your Bone calls in `#if DEBUG`.

**Platforms**

| | iOS | watchOS | visionOS | macOS |
|---|:-:|:-:|:-:|:-:|
| Hierarchy dump `.bone(into:)` | ✓ | ✓ | ✓ | ✓ |
| 3D hierarchy `.bone3D` · `.bone3DFrom` | | | ✓ | |
| Liquid Glass `.tune` · `.dumpGlass` | ✓ | ✓ | | ✓ |
| `.tune(file:)` · `.dumpGlass(full: true)` | ✓ | | | ✓ |
| `.dumpLayers` | ✓ | ✓ | | ✓ |
| `.tuneLayers` · `.dumpShaders` | ✓ | | | ✓ |
| `.probeGlass` | ✓ | | | ✓ |
| `.boneInspector()` | ✓ | | | ✓ |
| 3D exploded view (in the inspector) | ✓ | | | |
| Timeline bar (in the inspector) | ✓ | | | ✓ |
| `.morphTimeline` · `.morphScrubber` · `.dumpMorph` · `.liquidMorph` · `.glassFlex` | ✓ | | | |

Built with Xcode 27; tested on iOS 27 (simulator and iPhone 14 Pro), watchOS 27 (simulator), visionOS 27 and macOS.

| Modifier | What it does | Docs |
|---|---|---|
| `.bone(into:)` | UIKit hierarchy behind a SwiftUI view → overlay + text/JSON dump (iOS, macOS, visionOS, watchOS) | [hierarchy](https://github.com/filipvabrousek/Bone/blob/main/Bone-27/docs/hierarchy.md) |
| `.bone3D(into:)` · `.bone3DFrom(_:)` | the hierarchy as a 3D tree (visionOS) | [hierarchy](https://github.com/filipvabrousek/Bone/blob/main/Bone-27/docs/hierarchy.md) |
| `.tune(_:)` | override any Liquid Glass parameter, presets, JSON hot reload | [glass tuning](https://github.com/filipvabrousek/Bone/blob/main/Bone-27/docs/glass-tuning.md) |
| `.dumpGlass(_:)` · `.dumpShaders(_:)` | glass inputs and the glass shaders' own uniforms | [glass tuning](https://github.com/filipvabrousek/Bone/blob/main/Bone-27/docs/glass-tuning.md) |
| `.probeGlass(_:)` | which glass inputs really change the pixels | [glass tuning](https://github.com/filipvabrousek/Bone/blob/main/Bone-27/docs/glass-tuning.md) |
| `.boneInspector()` | tap any glass or layer and edit it live; 3D exploded view | [inspector](https://github.com/filipvabrousek/Bone/blob/main/Bone-27/docs/inspector.md) |
| `.tuneLayers(_:where:)` · `.dumpLayers(_:)` | filters, blend modes, transforms on the layers of any view | [layers](https://github.com/filipvabrousek/Bone/blob/main/Bone-27/docs/layers.md) |
| `.morphTimeline()` · `.morphScrubber()` · `.dumpMorph(_:)` | pause, step, scrub and dump the Liquid Glass morphs | [timeline](https://github.com/filipvabrousek/Bone/blob/main/Bone-27/docs/timeline.md) |
| `.liquidMorph(to:isPresented:)` | Apple's glass morph between any two views | [liquid morph](https://github.com/filipvabrousek/Bone/blob/main/Bone-27/docs/liquid-morph.md) |
| `.glassFlex(stretch:follow:)` | the glass button's press and drag stretch, much further | [glass stretch](https://github.com/filipvabrousek/Bone/blob/main/Bone-27/docs/glass-stretch.md) |

Full documentation: [Bone-27/docs](https://github.com/filipvabrousek/Bone/blob/main/Bone-27/docs/index.md).
What changed: [CHANGELOG.md](CHANGELOG.md).
