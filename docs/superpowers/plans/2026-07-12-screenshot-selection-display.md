# Screenshot Selection Display Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a Retina screenshot display at the selected screen-point size while preserving native pixels, and make the selected area transparent inside the dark capture overlay.

**Architecture:** Keep coordinate conversion and pixel cropping in `ScreenshotCropMapper`. Treat the cropped `CGImage` dimensions as storage pixels and the overlay selection dimensions as the resulting `NSImage` logical point size. Render the overlay as one translucent fill with a clear-blend cutout, then draw selection chrome above it.

**Tech Stack:** Swift 5.9+, AppKit, SwiftUI, Core Graphics, Swift Package Manager, macOS 14.0+ project behavior.

## Global Constraints

- Preserve the cropped image's native Retina pixels; do not downsample.
- The annotation window's logical display size must equal the selected screen area.
- Before selection, the full overlay is dark; while dragging, only the selected area is transparent.
- Do not alter save rendering, annotation rendering, or screenshot-window lifecycle behavior beyond the existing double-release fix.
- Avoid unrelated edits in the dirty working tree.

---

### Task 1: Correct Screenshot Logical Size and Overlay Cutout

**Files:**
- Modify: `OneBoard/Modules/Screenshot/Views/ScreenshotOverlayView.swift:183-235`
- Verify: `OneBoard/Tests/ScreenshotOverlayCropTests.swift`

**Interfaces:**
- Consumes: `ScreenshotCropMapper.cropRect(forOverlayRect:screenFrame:imagePixelSize:) -> CGRect`
- Produces: a cropped `NSImage` whose `CGImage` retains pixel dimensions and whose `size` equals `selectionRect.size`

- [ ] **Step 1: Confirm the existing 2x mapping expectation**

Review the existing test case and confirm that a point-space selection maps to a pixel-space crop:

```swift
let crop = ScreenshotCropMapper.cropRect(
    forOverlayRect: CGRect(x: 980, y: 700, width: 80, height: 80),
    screenFrame: CGRect(x: 0, y: 0, width: 1000, height: 750),
    imagePixelSize: CGSize(width: 2000, height: 1500)
)
XCTAssertEqual(crop, CGRect(x: 1960, y: 0, width: 40, height: 100))
```

The repository's current `OneBoardTests` target imports the minimal executable instead of `OneBoardKit`, so `swift test` is not a valid runnable seam for this change. Do not broaden this screenshot fix into a repository-wide test-target migration.

- [ ] **Step 2: Restore the transparent selection cutout**

After filling `bounds` with the dark overlay and before drawing the border, clear the selected region and restore normal blending:

```swift
ctx.saveGState()
ctx.setBlendMode(.clear)
ctx.fill(rect)
ctx.restoreGState()
```

Keep the existing accent border and size label after this block so they remain visible above the cutout.

- [ ] **Step 3: Use point dimensions for the result image's logical size**

Construct the result image with the overlay selection size instead of the pixel crop size:

```swift
let result = NSImage(cgImage: cropped, size: rect.size)
```

Do not resize `cropped`; the backing `CGImage` must keep its native pixel width and height.

- [ ] **Step 4: Run compile verification**

Run:

```bash
cd OneBoard
swift build
```

Expected: exit code `0` and `Build complete!`.

- [ ] **Step 5: Build the isolated development bundle**

Run:

```bash
ONEBOARD_BUNDLE_ID_SUFFIX=.dev2 ONEBOARD_CODESIGN_IDENTITY=- bash script/build_app_bundle.sh
```

Expected: exit code `0`, bundle ID `com.oneboard.mac.dev2`, and `Built .../build/OneBoard.app`.

- [ ] **Step 6: Perform the original-path regression check**

Launch the development app with Zombie detection, press `Option-A`, drag a visible region, and confirm all of the following:

- Before dragging, the entire screen is darkened.
- During dragging, the selected region is transparent and the outside remains dark.
- The annotation image window occupies the same logical screen size as the selection.
- The captured content boundaries match the selected region.
- Terminal output contains no `message sent to deallocated instance` and the OneBoard process remains alive.

- [ ] **Step 7: Inspect the focused diff**

Run:

```bash
git diff --check -- OneBoard/Modules/Screenshot/Views/ScreenshotOverlayView.swift OneBoard/Modules/Screenshot/Services/ScreenshotCaptureService.swift
git diff -- OneBoard/Modules/Screenshot/Views/ScreenshotOverlayView.swift OneBoard/Modules/Screenshot/Services/ScreenshotCaptureService.swift
```

Expected: no whitespace errors; every changed line relates to screenshot sizing, overlay transparency, or the already-diagnosed window double-release.

- [ ] **Step 8: Package and verify the DMG after user-path validation**

Run:

```bash
ONEBOARD_CODESIGN_IDENTITY=- bash script/package_app.sh
hdiutil verify build/OneBoard.dmg
```

Expected: packaging exits `0`, followed by `hdiutil verify` reporting the DMG as valid.
