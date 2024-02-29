# Bone.swift

![250-bone](https://github.com/filipvabrousek/Bone/assets/18376136/857e695b-d1ee-410f-a13e-b6d4bc51580d)

Swift library that dumps underlying UIKit views from SwiftUI views.
The results are shown as overlay on the view.
You can expand overlay to see layers, sublayers and superclasses of the views.


Consider this code:

```swift
 List {
  Text("Bone")
}
.bone(into: "output.txt")
```

The dump of view above will be dumped into output.txt file, and the overlay will be show.

![image](https://github.com/filipvabrousek/Bone/assets/18376136/acf0014d-b594-4d50-b8f4-1d92489ded9e)


