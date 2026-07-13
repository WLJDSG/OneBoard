# OneBoard Menu Icon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current overlapping-square menu icon with the approved monochrome One Board panel symbol and verify it in the real macOS menu bar.

**Architecture:** Keep the existing native `NSStatusItem` lifecycle unchanged. Draw one 18×18pt AppKit template image with a rear panel, a dominant front panel, and two content lines, then let macOS tint it for the active menu-bar appearance.

**Tech Stack:** Swift 5.9+, AppKit `NSImage`/`NSBezierPath`, Swift Package Manager, macOS 14.0+.

## Global Constraints

- Preserve `NSStatusItem.squareLength`, `.imageOnly`, and the executable-module creation path.
- Use no `OB` text, debug status title, `autosaveName`, or SF Symbol dependency.
- Do not modify unrelated dirty working-tree files.
- Development verification uses `com.oneboard.mac.dev2`; formal packaging uses `com.oneboard.mac`.

---

### Task 1: Draw and Verify the One Board Menu Icon

**Files:**
- Modify: `OneBoard/Shared/MenuBarManager.swift:281-318`

**Interfaces:**
- Consumes: `MenuBarManager.configure(statusItem:)`
- Produces: `createMenuBarIcon() -> NSImage`, an 18×18pt template image

- [ ] **Step 1: Capture the current visual baseline**

Run the `.dev2` development app and capture the menu bar with:

```bash
screencapture -x /tmp/oneboard-menu-icon-before.png
```

Expected: the current overlapping-square icon is visible and provides the visual baseline.

- [ ] **Step 2: Replace only the icon paths**

Implement `createMenuBarIcon()` with these elements:

```swift
let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
    let rearPanel = NSBezierPath(
        roundedRect: NSRect(x: 6.0, y: 6.0, width: 9.5, height: 9.0),
        xRadius: 2.2,
        yRadius: 2.2
    )
    rearPanel.lineWidth = 1.5
    rearPanel.stroke()

    let frontPanel = NSBezierPath(
        roundedRect: NSRect(x: 2.5, y: 2.5, width: 11.5, height: 11.5),
        xRadius: 2.6,
        yRadius: 2.6
    )
    frontPanel.lineWidth = 1.5
    frontPanel.fill()

    NSColor.white.setStroke()
    let firstLine = NSBezierPath()
    firstLine.move(to: NSPoint(x: 5.2, y: 9.1))
    firstLine.line(to: NSPoint(x: 11.0, y: 9.1))
    firstLine.lineWidth = 1.25
    firstLine.stroke()

    let secondLine = NSBezierPath()
    secondLine.move(to: NSPoint(x: 5.2, y: 6.4))
    secondLine.line(to: NSPoint(x: 9.2, y: 6.4))
    secondLine.lineWidth = 1.25
    secondLine.stroke()
    return true
}
image.isTemplate = true
return image
```

Set black fill/stroke before drawing the panels. Keep the content lines white so the template mask creates visible internal cutouts.

- [ ] **Step 3: Compile**

Run:

```bash
cd OneBoard && swift build
```

Expected: exit code `0` and `Build complete!`.

- [ ] **Step 4: Build and launch `.dev2`**

Run:

```bash
ONEBOARD_BUNDLE_ID_SUFFIX=.dev2 ONEBOARD_CODESIGN_IDENTITY=- bash script/build_app_bundle.sh
pkill -x OneBoard || true
open build/OneBoard.app
```

Expected: bundle ID `com.oneboard.mac.dev2`; process remains alive.

- [ ] **Step 5: Verify the rendered menu icon**

Run:

```bash
screencapture -x /tmp/oneboard-menu-icon-after.png
```

Inspect the image and confirm the rear panel, dominant front panel, and two content-line cutouts are visible with no `OB` text.

- [ ] **Step 6: Inspect the focused diff and remove diagnostics**

Run:

```bash
rg -n '\[DEBUG-menubar\]|button\.title = "OB"' OneBoard || true
git diff --check -- OneBoard/Shared/MenuBarManager.swift
git diff -- OneBoard/Shared/MenuBarManager.swift
```

Expected: no debug markers or whitespace errors; icon changes are isolated from pre-existing uninstall-script edits in the same file.

- [ ] **Step 7: Build and verify the formal DMG**

Run:

```bash
ONEBOARD_CODESIGN_IDENTITY=- bash script/package_app.sh
hdiutil verify build/OneBoard.dmg
```

Expected: packaging exits `0`; DMG checksum is `VALID`.
