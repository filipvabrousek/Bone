# Bone.swift

![250-bone](https://github.com/filipvabrousek/Bone/assets/18376136/857e695b-d1ee-410f-a13e-b6d4bc51580d)

Bone looks underneath SwiftUI. It dumps the UIKit views behind any SwiftUI view, and it reads,
tunes, freezes, records and re-drives the system's own Liquid Glass – in place, not a
reimplementation.

> **Research / simulator use only.** Bone uses private classes, selectors, ivars and Core
> Animation keys. Never ship it in an App Store build; names change between OS releases.

## Get started

Copy every file in [`library/`](library) into a folder of your project and add them to all targets.

```swift
List {
    Text("Bone")
}
.bone(into: "output.txt")
```

The hierarchy is written to `output.txt` and shown as an overlay you can expand to see layers,
sublayers and superclasses.

<img width="1304" height="736" alt="Bone overlay and 3D hierarchy" src="https://github.com/user-attachments/assets/1ebb7a79-d039-4a48-ad88-6ff5f5b5fc7c" />

## What's in it

| Modifier | What it does | Docs |
|---|---|---|
| `.bone(into:)` | UIKit hierarchy behind a SwiftUI view → overlay + text/JSON dump | [Hierarchy dumps](Bone-27/docs/hierarchy.md) |
| `.bone3D(into:)` · `.bone3DFrom(_:)` | the hierarchy as a 3D tree (visionOS) | [Hierarchy dumps](Bone-27/docs/hierarchy.md) |
| `.tune(_:)` | override any Liquid Glass parameter, presets, JSON hot reload | [Glass tuning](Bone-27/docs/glass-tuning.md) |
| `.dumpGlass(_:)` · `.dumpShaders(_:)` | glass inputs and the glass shaders' own uniforms | [Glass tuning](Bone-27/docs/glass-tuning.md) |
| `.probeGlass(_:)` | which glass inputs really change the pixels | [Glass tuning](Bone-27/docs/glass-tuning.md) |
| `.boneInspector()` | tap any glass or layer and edit it live; 3D exploded view | [Inspector and 3D](Bone-27/docs/inspector.md) |
| `.tuneLayers(_:where:)` · `.dumpLayers(_:)` | filters, blend modes, transforms on the layers of any view | [Layers](Bone-27/docs/layers.md) |
| `.morphTimeline()` · `.morphScrubber()` · `.dumpMorph(_:)` | pause, step, scrub and dump the Liquid Glass morphs | [Timeline and morphs](Bone-27/docs/timeline.md) |
| `.liquidMorph(to:isPresented:)` | Apple's glass morph between any two views | [Liquid morph](Bone-27/docs/liquid-morph.md) |
| `.glassFlex(stretch:follow:)` | the glass button's press and drag stretch, much further | [Glass stretch](Bone-27/docs/glass-stretch.md) |

## Documentation

- [Guides](Bone-27/docs/index.md) – one page per topic, with examples, results and how each part works.
- [Getting started](Bone-27/docs/getting-started.md) – demo launch arguments, where files land.
- [Bone internals and novelty](Bone-27/docs/internals/bone-internals.pdf) – every mechanism at the
  level of layers, ivars and setters, with diagrams, and what is new compared with published work.
