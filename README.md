# Bone.swift

![250-bone](https://github.com/filipvabrousek/Bone/assets/18376136/857e695b-d1ee-410f-a13e-b6d4bc51580d)

Swift library that dumps underlying UIKit views from SwiftUI views.
The results are shown as overlay on the view.
You can expand overlay to see layers, sublayers and superclasses of the views.
It is also possible to output the code into text file.  
To get started, just copy/paste all files in library into folder in all projects and add it to all targets.


The library contains a single modifier:

```swift
 List {
  Text("Bone")
}
.bone(into: "output.txt")
```

The dump of view above will be dumped into ```output.txt``` file, and the overlay will be shown.

![image](https://github.com/filipvabrousek/Bone/assets/18376136/acf0014d-b594-4d50-b8f4-1d92489ded9e)

Search in Xcode console for ```OUTPUT FILE:``` string to find the location of the text file.

You can the copy and paste the url and open in in terminal like this:

```sh
open file:///var/mobile/Containers/Data/Application/3013CC20-9A66-48C7-9880-5977FF7D072E/Documents/output.txt
```

Platform support:
* iOS
* iPadOS
* visionOS
* macOS
* tvOS
  
* watchOS (only some class names are shown) no UI reflection possible like on other platforms







