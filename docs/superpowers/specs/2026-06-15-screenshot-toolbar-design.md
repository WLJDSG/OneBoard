# Screenshot Toolbar Upgrade Design

## Goal

Upgrade OneBoard's screenshot annotation toolbar to match the core workflow shown in the reference video: fast keyboard-driven tool switching, grouped annotation controls, undo/redo, direct desktop save, OCR, pinning, and clear screenshot size feedback.

This is a two-phase design. Phase 1 upgrades the current post-capture annotation window. Phase 2 can later replace the system `screencapture -i` flow with a custom selection overlay if true in-selection resizing is needed.

## Current Context

The screenshot module already has:

- Region capture through `ScreenshotCaptureService`.
- A post-capture annotation window managed by `ScreenshotViewModel`.
- `AnnotationToolbarView` with rectangle, ellipse, arrow, line, text, mosaic, color, save, pin, OCR, translation, undo, complete, and close.
- `AnnotationService` for annotation layers and rendering.
- `AnnotationViewModel` for mouse handling, drawing, text editing, and window movement.
- `PinnedScreenshotView` for pinned screenshots.

The current toolbar is functional but behaves like a flat row of buttons. The target experience is a compact annotation workbench with keyboard-first tool switching and tool-specific style controls.

## Phase 1 Scope

Phase 1 keeps the existing capture model: the user selects a region, OneBoard receives the captured image, then the annotation window and toolbar appear.

Phase 1 includes:

- Tool switching with number keys.
- Toolbar button tooltips showing shortcut keys.
- Annotation tools: move/select, rectangle, ellipse, arrow, line, text, numbered marker, mosaic.
- Style controls: color and thickness. Text uses the thickness control as font-size adjustment; mosaic uses it as block-size adjustment.
- Left Option and Right Option shortcuts for style adjustment.
- Undo and redo.
- Complete/copy, cancel/close, direct desktop save, pin, and OCR.
- Screenshot size display, for example `1280 x 720`.
- Toolbar grouped by tool, style, history, and output actions.

Phase 1 excludes:

- Freehand pen/brush.
- Eyedropper/color picker from screen.
- Translation toolbar changes.
- Selection resizing before capture completes.
- Replacing `screencapture -i` with a custom capture overlay.

## Toolbar Layout

The toolbar should be a compact floating panel positioned near the screenshot window, matching the current separate-toolbar architecture.

Groups:

1. Tool group
   - `1` Move/select
   - `2` Rectangle
   - `3` Ellipse
   - `4` Arrow
   - `5` Line
   - `6` Text
   - `7` Numbered marker
   - `8` Mosaic

2. Style group
   - Current color swatch.
   - Preset colors.
   - Thickness indicator.
   - Tool-specific value label:
     - Shape/line/arrow: line width.
     - Text: font size.
     - Mosaic: mosaic block size.

3. History group
   - Undo.
   - Redo.

4. Output group
   - Complete/copy.
   - Save to Desktop.
   - Pin.
   - OCR.
   - Cancel/close.

The toolbar should remain readable at small screenshot sizes. If the screenshot is too narrow for a single horizontal row, the implementation may use tighter spacing or wrap into two rows inside the toolbar panel. The first implementation should prefer one row because it matches the current architecture and is easier to scan.

## Keyboard Shortcuts

Shortcuts are active only while the annotation window is focused.

Tool switching:

| Key | Tool |
| --- | --- |
| `1` | Move/select |
| `2` | Rectangle |
| `3` | Ellipse |
| `4` | Arrow |
| `5` | Line |
| `6` | Text |
| `7` | Numbered marker |
| `8` | Mosaic |

Style shortcuts:

| Key | Behavior |
| --- | --- |
| Left Option | Cycle to previous preset color |
| Right Option | Increase thickness/font size/mosaic block size |

History and output:

| Shortcut | Behavior |
| --- | --- |
| `Cmd+Z` | Undo |
| `Cmd+Shift+Z` | Redo |
| `Enter` | Complete and copy rendered screenshot to clipboard |
| `Esc` | Cancel or close |
| `Cmd+S` | Save rendered screenshot directly to Desktop |

Notes:

- The left and right Option keys must be distinguished by key code or modifier flags available from `NSEvent`.
- If distinguishing left and right Option is unreliable on a given keyboard layout, fallback behavior should be documented in code and the toolbar should still expose clickable controls.
- Shortcuts must not fire while the user is actively typing inside a text annotation field, except `Esc` for canceling text editing and `Enter` for committing text where the current text editor already owns that behavior.

## Numbered Marker Tool

The numbered marker tool creates a circular badge with an auto-incrementing number.

Behavior:

- Selecting tool `7` enters numbered marker mode.
- Click places the next badge at the clicked point.
- The first badge number is `1`.
- Each new badge increments the number by one.
- Undo removes the last badge and restores redo capability.
- Redo restores the removed badge with its original number.
- Adding a new layer after undo clears redo history.
- Badge color follows the selected color.
- Badge text should use high contrast:
  - White text on saturated/dark colors.
  - Black text on light colors such as yellow or white.

Layer model:

- Add `.number` to `AnnotationTool`.
- Add an optional `numberValue: Int?` field to `AnnotationLayer`.
- Numbered marker rect should be a stable square size derived from the current style size, with a sensible default around 28 points.

## Style Model

The existing `lineWidth` should be expanded into tool-aware style state.

Recommended model:

- `selectedColor: NSColor`
- `lineWidth: CGFloat`
- `fontSize: CGFloat`
- `mosaicBlockSize: CGFloat`
- `numberBadgeSize: CGFloat`

Right Option behavior:

- Shape, arrow, and line tools: increase `lineWidth`.
- Text tool: increase `fontSize`.
- Mosaic tool: increase `mosaicBlockSize`.
- Number tool: increase `numberBadgeSize`.

Clickable controls should allow decreasing values even though the requested keyboard shortcut only specifies increase. This keeps the UI recoverable if a value becomes too large.

Suggested value ranges:

- `lineWidth`: 1...12
- `fontSize`: 12...48
- `mosaicBlockSize`: 4...24
- `numberBadgeSize`: 20...48

## Undo And Redo

`AnnotationService` should own history state.

Behavior:

- `undo()` removes the last layer and pushes it onto a redo stack.
- `redo()` restores the most recently undone layer.
- Adding a new layer clears the redo stack.
- Removing a specific layer clears the redo stack.
- Clearing all layers stores the removed layers in a way that can be redone as a group only if this is simple in the implementation; otherwise the first implementation may disable redo after clear. Since toolbar scope does not include a clear-all button, this does not block Phase 1.

Toolbar state:

- Undo button disabled when there are no layers.
- Redo button disabled when redo stack is empty.
- `Cmd+Z` and `Cmd+Shift+Z` should follow the same enabled behavior.

## Save To Desktop

`Cmd+S` and the save button should save the rendered screenshot directly to Desktop.

Behavior:

- No save panel.
- Filename format: `OneBoard Screenshot yyyy-MM-dd HH.mm.ss.png`.
- Destination: `~/Desktop`.
- If Desktop cannot be resolved, fallback to the existing save behavior or show a lightweight failure message.
- Save should include all annotations.

## Screenshot Size Display

The annotation UI should show the captured image pixel size.

Behavior:

- Show a compact label such as `1280 x 720`.
- Use pixel size from the image bitmap representation when available, not only the display size.
- Place it near the toolbar or in a small non-interactive overlay near the screenshot edge.
- The label should not be rendered into the final copied/saved image.

## Rendering

Rendering must include:

- Base screenshot.
- Rectangle, ellipse, arrow, line, text, numbered marker, and mosaic layers.

Rendering must exclude:

- Toolbar.
- Screenshot size label.
- Selection handles or editing affordances.

Coordinate mapping should continue to respect the current `displaySize` to image pixel size conversion so annotations line up on Retina screenshots.

## Files To Modify

- `OneBoard/Modules/Screenshot/Models/AnnotationLayer.swift`
  - Add `.number`.
  - Add icon and display name.
  - Add optional number value.

- `OneBoard/Modules/Screenshot/Services/AnnotationService.swift`
  - Add redo stack.
  - Add number creation.
  - Add tool-aware style values.
  - Add numbered marker rendering.
  - Update mosaic rendering to use configurable block size.

- `OneBoard/Modules/Screenshot/ViewModels/AnnotationViewModel.swift`
  - Add click handling for numbered markers.
  - Add keyboard handling entry points or route commands from the view.
  - Preserve text editing behavior so numeric shortcuts do not interrupt typing.

- `OneBoard/Modules/Screenshot/Views/AnnotationToolbarView.swift`
  - Rebuild toolbar groups.
  - Add shortcut labels in help text.
  - Add dynamic style controls.
  - Add redo action.
  - Route save action to Desktop.

- `OneBoard/Modules/Screenshot/Views/AnnotationCanvasView.swift`
  - Add keyboard monitor for annotation-window shortcuts if not centralized elsewhere.
  - Display screenshot size label.
  - Render number layer preview and selected/editing affordances.

- `OneBoard/Modules/Screenshot/ViewModels/ScreenshotViewModel.swift`
  - Add or update save-to-Desktop behavior if save remains owned by this view model.

## Testing Strategy

Add focused tests where the current project test structure allows it.

Required behavior checks:

- Numbered markers increment from 1.
- Undo removes the last layer and enables redo.
- Redo restores the original layer and number.
- Adding a new annotation after undo clears redo.
- Save-to-Desktop filename generation is deterministic when given a fixed date provider, if the implementation extracts filename generation into a testable helper.
- Rendering a numbered marker returns an image and does not crash.

Manual verification:

- Start screenshot capture from the configured shortcut.
- Draw each supported tool.
- Switch tools with `1` through `8`.
- Use left Option to cycle colors.
- Use right Option to increase style size.
- Confirm `Cmd+Z`, `Cmd+Shift+Z`, `Enter`, `Esc`, and `Cmd+S`.
- Confirm `Cmd+S` writes a PNG to Desktop.
- Confirm OCR still opens the result bubble.
- Confirm pin still creates a pinned screenshot.

## Phase 2 Direction

If the later goal is to fully match the reference video's in-selection experience, replace `screencapture -i` with a custom capture overlay:

- Full-screen transparent overlay across active displays.
- Drag-to-select region.
- Live size label while dragging.
- Resize handles before capture finalization.
- Toolbar attached to the active selection before the final image is rendered.
- Capture selected pixels through CoreGraphics or ScreenCaptureKit.

Phase 2 should be planned separately because it changes the screenshot capture foundation rather than only the annotation toolbar.
