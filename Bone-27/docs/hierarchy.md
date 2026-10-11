# Hierarchy dumps

## `.bone(into:)` — iOS, visionOS, macOS

```swift
List { Text("WOW") }.bone(into: "output.txt")      // classic brief text dump
List { Text("WOW") }.bone(into: "structure.json")  // deep SwiftUI dump (JSON)
```

The **extension decides the format**:

- `.txt` (or anything non-JSON) → classic brief dump: class, superclass, layer and sublayers per view.
- `.json` → deep dump: `Mirror` of the SwiftUI value tree, hosting view → ViewGraph/renderer,
  `recursiveDescription`, `_autolayoutTrace`, and the full per-node tree with `_ivarDescription`.

It also adds coloured debug borders and a tappable overlay inspector. On iOS 27+ each run also
writes `briefoutput.txt` and timestamped deep captures (`<name>_capture_<OS>_<timestamp>.txt/.json`)
to Documents **and** `<project>/captures/` (simulator).

**How it works:** the content is hosted in a `UIHostingController` (or the window's root controller
with `fromRoot: true`) and its `subviews` are walked recursively. The deep capture adds UIKit's
private introspection (`-_ivarDescription`, `-recursiveDescription`, `-_autolayoutTrace`) and
`Mirror` of the SwiftUI root value and of `_UIHostingView` – Swift stored properties no ivar list
shows.

## `.bone3D(into:)` — visionOS

```swift
List { Text("Hello") }.bone3D()                    // live 3D hierarchy, no file
List { Text("Hello") }.bone3D(into: "ssu.json")    // + deep JSON dump
List { Text("Hello") }.bone3D(into: "dump.txt")    // + brief text dump
```

![3D hierarchy on visionOS](https://github.com/user-attachments/assets/1ebb7a79-d039-4a48-ad88-6ff5f5b5fc7c)

Captures the live UIKit hierarchy of the wrapped view and renders it as an unbounded 3D tree in a
volumetric window. Tap a slab for details (superclass, layer, sublayers, ivars). The optional
`into:` writes the dump (same extension rule as `.bone`).

## `.bone3DFrom(_:)` — visionOS

```swift
List { Text("Hello") }.bone3DFrom("briefoutput.txt")   // brief text dump
List { Text("Hello") }.bone3DFrom("structure.json")    // deep JSON dump
```

Builds the 3D graph from a dump file instead of a live capture, including the
`output_capture_*.json` files. Resolution order: absolute path → `<project>/captures/` (simulator)
→ app Documents. Lets you view an iOS/macOS-captured hierarchy on visionOS and compare platforms.

## Configuration

```swift
BoneCapture.maxIvarLength = 20_000              // chars of ivar dump per node
BoneCapture.maxMirrorDepth = 7                  // Mirror recursion depth
BoneCapture.captureIvarDescriptions = true
BoneCapture.captureRecursiveDescription = true
BoneCapture.captureAutolayoutTrace = true
BoneCapture.ivarDenylist                        // class-name prefixes to skip
```

If a capture crashes (`EXC_BAD_ACCESS` in a private selector), the last `BONE introspecting …`
console line names the class – add its prefix to `ivarDenylist`. Known broken: `_UIHostingView`
on iOS 26, all `_TtGC7SwiftUI…` generic classes on visionOS 27 (the defaults handle both).

## Cross-OS diffing

```bash
cd captures
diff <(jq -S . output_capture_iOS26_0_*.json) <(jq -S . output_capture_iOS27_0_*.json)
```

Renamed private classes, hierarchy changes and ivar-layout differences between OS releases fall
out automatically.
