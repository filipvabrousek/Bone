# Glass stretch

## `.glassFlex(stretch:follow:)` — iOS

![Stock and .glassFlex(stretch: 6, follow: 12) while dragged, iPhone 14 Pro](../captures/glass-flex.png)

```swift
Button("Glass") {}.buttonStyle(.glass).glassFlex(stretch: 6, follow: 12)
```

Stretches the system glass button's own flex much further – the swell when pressed and the stretch
toward the finger while held and dragged – and the glass outline grows with the label.

| Parameter | Multiplies | Stock | Default |
|---|---|---|---|
| `stretch` | the swell and the drag stretch | 1 | 6 |
| `follow` | the shift toward the finger | 1 | 12 |

Only glass controls inside the modified view are affected; the rest keep the stock flex. The demo
shows stock next to stretched with `-flex`.

Measured on an iPhone 14 Pro at (6, 12): pressed, glass and label 164 × 106 pt together (stock
77 × 50); dragged, ~150 × 105 following the finger. Stock: press 1.19×, drag 1.23 × 1.13, shift
+4 pt. iOS has no public knob for this – `interactive` is only on/off, even in the iOS 27 SDK.

## How it works

SwiftUI's flex interaction (`UIPlatformGlassFlexInteraction`) drives two layer branches every frame,
and `.glassFlex` maps both:

- **The content** – the layer of `UIPlatformGlassInteractionView`: a scale (`setTransform:` /
  `setAffineTransform:`, from the top-left corner) and a position (recentring plus a small shift
  toward the finger). The scale becomes 1 + stretch·(s − 1), the position is recentred and the
  finger shift multiplied by `follow`.
- **The glass outline** – every layer under SwiftUI's `SDFLayer` host (container,
  `CABackdropLayer`, `CASDFLayer`, `SDFPortalLayer`) gets the shape's bounds and position
  (61 × 39 → 78 × 50 pressed). The size grows by the same rule; the bounds origin (which mirrors the
  position) is mapped too.
- **The shape element** (`CASDFElementLayer`) is a rounded rectangle with its own corner radius while
  held (19.7 → 25.2), and switches to a distance-field bitmap of the stretched blob, ~9.5 pt larger
  than the shape, while dragged. It is scaled about the shape, so a capsule stays a capsule and the
  blob lands on the amplified outline.

On release UIKit stops setting the content for ~1 s while the outline still springs back frame by
frame; the content then follows the outline. `SDFLayer` is a Swift class (`NSClassFromString` does
not find it – it is matched by name). CALayer's setters are swapped once; only layers of a glass
button inside a `.glassFlex` view are changed, each value mapped once (nested setter calls pass
through).

The mapping formulas, the per-frame order of the setters, the shape element's geometry and the bugs
found on the way: [Bone internals – glass stretch in depth](internals/bone-internals.md#8-glass-stretch-glassflexstretchfollow-in-depth).
