# Hierarchy dumps

## `.bone(into:)` — iOS, visionOS, macOS, watchOS

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

## `.bone(into:)` on watchOS

```swift
List { Text("Hello") }.bone(into: "watch.txt")
```

The same modifier works on Apple Watch (`BoneWatch.swift`). watchOS has no public UIKit – the SDK
marks `UIView`, `UIWindow`, `UIApplication` and `CALayer` unavailable – but the watch runs the same
UIKitCore and QuartzCore underneath, and SwiftUI hosts its views in `_UIHostingView` as on iOS. So
the walk goes through the Objective-C runtime (classes by name, `respondsToSelector:` before every
key-value read). It writes the brief dump (`watch.txt`, same format, `OS: watchOS:27`) and the layer
tree with every filter's type and input keys (`watch-layers.txt`).

What a watchOS 27 dump shows (simulator, `NavigationStack` + `List` + a glass button):

- `SPApplication` → `UIWindow` → `SPHostingViewController` → `_UIHostingView`;
- a `List` is the same `UpdateCoalescingCollectionView` as on iOS, its rows in watch-only
  `PUICPlatterCellContainerView`s (PepperUICore); the navigation bar is
  `PUICStackedNavigationBar` with `SaltUICore.NavigationBarHostingView`;
- the glass button is a `UIPlatformGlassInteractionView` over `SwiftUI.SDFLayer` →
  `CABackdropLayer` with **`glassBackground` (70 inputs)** and `vibrantColorMatrix`, `CASDFLayer` →
  `CASDFElementLayer`, `SDFPortalLayer` – the iPhone's Liquid Glass structure;
- the scroll edge effect is a `CABackdropLayer` with `variableBlur`, `gaussianBlur`, `sdrNormalize`.

Not on watchOS: `_UIMagicMorphAnimation` and `_UILiquidMorphAnimation` (no context menus), so
`.liquidMorph` and the menu-morph timeline do not apply. The older `wbone(name:)` still works as a
deprecated alias.

**On macOS** the walk names each view from Swift's `dump` of it, which is slow for big SwiftUI
hosting views: a small view takes seconds, but on macOS 27 a `List` did not finish within
7 minutes (the dump of SwiftUI's environment runs at 100% CPU).

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
