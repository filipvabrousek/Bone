// The glass shape element (CASDFElementLayer) in its two modes – stock values from an iPhone 14 Pro.
// Compile: typst compile shape-modes.typ shape-modes.svg
#import "@preview/cetz:0.3.4"
#set page(width: auto, height: auto, margin: 10pt, fill: white)
#set text(font: ("SF Pro Text", "Helvetica Neue", "Arial"), size: 8pt)
#show raw: set text(font: ("SF Mono", "Menlo"), size: 7pt)
#let tiny(t) = { set par(justify: false); show raw: set text(size: 6.4pt); text(size: 7pt, t) }

#cetz.canvas(length: 1cm, {
  import cetz.draw: *
  content((1.6, 3.15), text(size: 8pt, weight: "bold")[held: `mode = bounds`])
  rect((0, 0.6), (3.2, 2.4), radius: 0.9, stroke: 0.9pt + rgb("#3c8d50"), fill: rgb("#e6f4ea"))
  content((1.6, 1.5), text(size: 7.5pt)[shape = element \ radius 25.2 → 52.8])
  content((1.6, 0.25), tiny(text(fill: luma(90))[bounds + `cornerRadius`, mapped together]))

  content((6.6, 3.15), text(size: 8pt, weight: "bold")[dragged: `mode = contents`])
  rect((4.6, 0.25), (8.6, 2.65), stroke: (paint: rgb("#d81b60"), dash: "dashed", thickness: 0.8pt), fill: rgb("#fde7f0"))
  rect((5.1, 0.7), (8.1, 2.2), radius: 0.7, stroke: 0.9pt + rgb("#3c8d50"), fill: rgb("#e6f4ea"))
  content((6.6, 1.45), text(size: 7.5pt)[blob 74.8 × 51.1 \ at (−6.7, −4.6)])
  content((8.85, 2.3), anchor: "west", tiny(text(fill: rgb("#d81b60"))[element frame 94 × 70 \ at (−16, −14): bitmap \ 282 × 210 px, 3×]))
  content((8.85, 0.9), anchor: "west", tiny[margin ≈ 9.5 pt holds the \ outside of the distance field \ (zero / one value distance \ 8.9 / −16 pt)])
})
