# Bone documentation

Bone is a set of SwiftUI modifiers that look underneath SwiftUI: the UIKit views and Core
Animation layers it renders into, the private Liquid Glass filter and its shaders, and the
private AnimationKit engine that animates the glass. It reads, tunes, freezes, records and
re-drives the system's own Liquid Glass – in place, not a reimplementation.

> **Research / simulator use only.** Bone uses private classes, selectors, ivars and Core
> Animation keys. Never ship it in an App Store build; names change between OS releases.

## Guides

| Page | Modifiers |
|---|---|
| [Getting started](getting-started.md) | install, demo launch arguments, where files land |
| [Hierarchy dumps](hierarchy.md) | `.bone(into:)`, `.bone3D(into:)`, `.bone3DFrom(_:)`, cross-OS diffing |
| [Glass tuning](glass-tuning.md) | `.tune(_:)`, `.dumpGlass(_:)`, `.dumpShaders(_:)`, `.probeGlass(_:)` |
| [Inspector and 3D](inspector.md) | `.boneInspector()` / `.glassPanel()`, the 3D exploded view |
| [Layers of any view](layers.md) | `.tuneLayers(_:where:)`, `.dumpLayers(_:)` |
| [Timeline and morphs](timeline.md) | timeline bar, `.morphTimeline()`, `.morphScrubber()`, `.dumpMorph(_:)` |
| [Liquid morph](liquid-morph.md) | `.liquidMorph(to:isPresented:)` |
| [Glass stretch](glass-stretch.md) | `.glassFlex(stretch:follow:)` |

Changes over time: [library changelog](../Bone-27/library/CHANGELOG.md).

## In depth

- [Bone internals and novelty](internals/bone-internals.md) (also as [PDF](internals/bone-internals.pdf)) –
  how every part works at the level of layers, ivars and setters, with diagrams, and what is new
  compared with published work.
- [The Liquid Glass system](internals/liquid-glass-system.pdf) ([Typst source](internals/liquid-glass-system.typ)) –
  one diagram of the whole stack, from SwiftUI to the render server's Metal shaders.
