# Bone
Library that dumps underlying UIKit views from SwiftUI views.
The results are shown as overlay on the view.
You can expand overlay to see layers, sublayers and superclasses of the views.
Consider this code:

```swift
 List {
  Text("A")
}
.bone(into: "output.txt")
```

The dump of view above will be dumped into output.txt file.

![1024-bone-icon](https://github.com/filipvabrousek/Bone/assets/18376136/f54dd7b5-007d-4563-871f-39fea5780bc5)
