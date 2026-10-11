# Liquid morph

## `.liquidMorph(to:isPresented:)` — iOS

Runs Apple's own Liquid Glass morph between any two views:

```swift
Text("Hello")
    .liquidMorph(to: Circle().foregroundStyle(.green).frame(width: 30, height: 30), isPresented: $on)
```

![Text morphing into a glass panel, frame by frame](../captures/magic-morph-text.png)

Both ends sit in public glass (`UIVisualEffectView` + `UIGlassEffect`, capsule corners). Toggling
`isPresented` morphs one into the other with UIKit's `_UIMagicMorphAnimation` – the AnimationKit
morph of the floating tab bar and the search field: the glass stretches between the two shapes, the
contents blur across, the lensing refracts what is behind.

**How it works:** the morph is driven through its Objective-C door,
`morphTo:reparentWithoutAnimation:alongsideAnimations:completion:` with a `UITargetedPreview` – once
for the source (lifted into UIKit's `MagicMorphView`), once for the target. The target appears
centred on the source; layout keeps the source's size. Without the class (before iOS 26) the two
just cross-fade.

The menu's own `LiquidMorphAnimation` (with the drop step) has only a Swift API whose arguments are
values of AnimationKit's private protocols, so it is not reachable from outside.

Launch the demo with `-liquid` for this row alone (`-autotoggle` flips it every 3 s).
