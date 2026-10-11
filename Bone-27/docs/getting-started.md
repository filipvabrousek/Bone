# Getting started

## Install

Copy every file in `library/` into a folder of your project and add them to all targets. There is
no package yet.

> **Research / simulator use only.** Never ship Bone in an App Store build. Wrap its modifiers in
> `#if DEBUG` if they live in an app you also release.

```swift
List {
    Text("Bone")
}
.bone(into: "output.txt")
```

This writes the UIKit hierarchy behind the list to `output.txt` and shows it as an overlay.

## Demo app

The `Bone-27` project shows every feature. Launch arguments (Edit Scheme ▸ Arguments) pick one
row:

| Argument | Shows |
|---|---|
| *(none)* | all demo rows; the first is a glass `Menu` with the timeline |
| `-menu` | only the glass `Menu`, timeline bar open |
| `-liquid` | only the `.liquidMorph` row (`-autotoggle` flips it every 3 s) |
| `-flex` | stock vs `.glassFlex` buttons |
| `-list` | a `List` + `NavigationStack` with controls, glass in rows and toolbar glass |
| `-layers` | `.tuneLayers` on text, symbols and gradients |
| `-probe` | runs `.probeGlass` on a glass button |

On a device, pass arguments after `--`:
`xcrun devicectl device process launch --device <id> <bundle-id> -- -flex`.

## Where files land

- The app's **Documents** folder, always; the path is printed as `OUTPUT FILE:`.
- **`<project>/captures/`** in the iOS/visionOS *simulator* and on native macOS (macOS needs App
  Sandbox disabled). The folder is found via `#filePath`, so rebuild after moving the project.
