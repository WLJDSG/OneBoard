# Screenshot Annotation Follow-up Plan

1. Rebuild CodeGraph and inspect screenshot annotation entry points.
2. Record root causes from the two user videos and current source.
3. Update `AnnotationViewModel` drag handling so cursor-window dragging is unthrottled and resets state cleanly.
4. Update text input UX in `AnnotationCanvasView` to use an in-image transparent editor with focus-submit behavior.
5. Fix text layer layout so hover/selection does not apply coordinates twice or alter text position.
6. Add edge resize affordance for text layers using existing `updateTextLayer(id:rect:)`.
7. Stabilize `NSColorPanel` target/action handling in `AnnotationToolbarView`.
8. Update development log and run `swift build` plus `git diff --check`.
