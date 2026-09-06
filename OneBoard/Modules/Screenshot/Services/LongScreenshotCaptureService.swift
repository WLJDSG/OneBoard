import AppKit
import CoreGraphics
import SwiftUI
import ScreenCaptureKit

enum LongScreenshotStitcher {
    static func stitch(_ frames: [NSImage], overlapRatio: CGFloat = 0.20) -> NSImage? {
        guard let first = frames.first, first.size.width > 0, first.size.height > 0 else { return nil }
        let usable = frames.filter { abs($0.size.width - first.size.width) < 1 && abs($0.size.height - first.size.height) < 1 }
        guard !usable.isEmpty else { return nil }
        let overlap = min(max(first.size.height * overlapRatio, 0), first.size.height - 1)
        let appendedHeight = first.size.height - overlap
        let outputSize = CGSize(width: first.size.width, height: first.size.height + CGFloat(usable.count - 1) * appendedHeight)
        let output = NSImage(size: outputSize)
        output.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: outputSize).fill()
        for (index, frame) in usable.enumerated() {
            let destinationY = outputSize.height - first.size.height - CGFloat(index) * appendedHeight
            let sourceRect = index == 0
                ? NSRect(origin: .zero, size: first.size)
                : NSRect(x: 0, y: 0, width: first.size.width, height: appendedHeight)
            let destination = NSRect(x: 0, y: destinationY, width: first.size.width, height: sourceRect.height)
            frame.draw(in: destination, from: sourceRect, operation: .copy, fraction: 1)
        }
        output.unlockFocus()
        return output
    }

    static func looksUnchanged(_ lhs: NSImage, _ rhs: NSImage) -> Bool {
        guard let left = bitmap(lhs), let right = bitmap(rhs), left.pixelsWide == right.pixelsWide, left.pixelsHigh == right.pixelsHigh else { return false }
        var difference = 0.0
        var samples = 0
        let xStep = max(1, left.pixelsWide / 12)
        let yStep = max(1, left.pixelsHigh / 12)
        for y in stride(from: 0, to: left.pixelsHigh, by: yStep) {
            for x in stride(from: 0, to: left.pixelsWide, by: xStep) {
                guard let a = left.colorAt(x: x, y: y), let b = right.colorAt(x: x, y: y) else { continue }
                difference += abs(a.redComponent - b.redComponent) + abs(a.greenComponent - b.greenComponent) + abs(a.blueComponent - b.blueComponent)
                samples += 1
            }
        }
        return samples > 0 && difference / Double(samples) < 0.025
    }

    private static func bitmap(_ image: NSImage) -> NSBitmapImageRep? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return NSBitmapImageRep(cgImage: cg)
    }
}

/// 用户手动滚动；控制窗口不激活应用，选区内部完全透传鼠标。
@MainActor
final class LongScreenshotCaptureService: ObservableObject {
    @Published var message = "在框内向下缓慢滚动，完成后点击完成"
    @Published var count = 1
    @Published var preview: NSImage?
    private var finished = false
    private var cancelled = false

    func capture(initial: NSImage, selectionRect: CGRect) async -> NSImage? {
        guard let screenIndex = NSScreen.screens.firstIndex(where: { $0.frame.intersects(selectionRect) }) else { return initial }
        let screen = NSScreen.screens[screenIndex]
        let border = NSPanel(contentRect: selectionRect.insetBy(dx: -3, dy: -3), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        border.isOpaque = false
        border.backgroundColor = .clear
        border.ignoresMouseEvents = true
        border.level = .floating
        border.contentView = NSHostingView(rootView: Rectangle().stroke(Color.accentColor, lineWidth: 2).padding(1))
        let controls = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 440, height: 70), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        controls.isFloatingPanel = true
        controls.level = .floating
        controls.isOpaque = false
        controls.backgroundColor = .clear
        controls.contentView = NSHostingView(rootView: LongCaptureControls(model: self))
        let x = min(max(screen.visibleFrame.minX, selectionRect.minX), screen.visibleFrame.maxX - 440)
        let y = selectionRect.minY - 78 >= screen.visibleFrame.minY ? selectionRect.minY - 78 : min(screen.visibleFrame.maxY - 70, selectionRect.maxY + 8)
        controls.setFrameOrigin(CGPoint(x: x, y: y))
        border.orderFrontRegardless()
        controls.orderFrontRegardless()
        let previewPanel = NSPanel(contentRect: CGRect(x: min(selectionRect.maxX + 12, screen.visibleFrame.maxX - 150), y: selectionRect.maxY - 240, width: 140, height: 240), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        previewPanel.level = .floating; previewPanel.isOpaque = false; previewPanel.backgroundColor = .clear
        previewPanel.contentView = NSHostingView(rootView: LongCapturePreview(model: self))
        previewPanel.orderFrontRegardless()
        let sf = screen.frame
        let outside = [CGRect(x: sf.minX, y: sf.minY, width: max(0, selectionRect.minX - sf.minX), height: sf.height),
                       CGRect(x: selectionRect.maxX, y: sf.minY, width: max(0, sf.maxX - selectionRect.maxX), height: sf.height),
                       CGRect(x: selectionRect.minX, y: sf.minY, width: selectionRect.width, height: max(0, selectionRect.minY - sf.minY)),
                       CGRect(x: selectionRect.minX, y: selectionRect.maxY, width: selectionRect.width, height: max(0, sf.maxY - selectionRect.maxY))]
        let shades = outside.filter { $0.width > 0 && $0.height > 0 }.map { rect -> NSPanel in
            let panel = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.backgroundColor = .black.withAlphaComponent(0.25); panel.isOpaque = false
            panel.ignoresMouseEvents = true; panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
            panel.orderFrontRegardless(); return panel
        }
        defer { border.close(); controls.close(); previewPanel.close(); shades.forEach { $0.close() } }
        // 捕获过滤器只建立一次，永久排除本应用窗口；不再隐藏边框和控件。
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let screenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let display = content.displays.first(where: { $0.displayID == screenID }) else { return nil }
        let excluded = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: excluded, exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = CGRect(x: selectionRect.minX - screen.frame.minX, y: screen.frame.maxY - selectionRect.maxY, width: selectionRect.width, height: selectionRect.height)
        configuration.width = Int(selectionRect.width * screen.backingScaleFactor)
        configuration.height = Int(selectionRect.height * screen.backingScaleFactor)
        configuration.showsCursor = false
        configuration.captureResolution = .best
        // 首帧和后续帧必须经过相同的采集/色彩/像素尺寸路径。
        guard let first = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) else { return nil }
        var output = NSImage(cgImage: first, size: selectionRect.size)
        var previous = output
        preview = output
        while !finished && !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 80_000_000)
            if cancelled { return nil }
            let cg = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            let frame = cg.map { NSImage(cgImage: $0, size: selectionRect.size) }
            guard let frame else { message = "抓取失败，请检查屏幕录制权限"; continue }
            let prior = previous
            let shift = await Task.detached(priority: .userInitiated) { LongScreenshotStitcher.verticalShift(prior, frame) }.value
            guard let shift else {
                message = "未找到重叠，请向上回滚一些，再缓慢向下滚动"
                continue
            }
            guard shift > 0 else { continue }
            guard output.size.height + shift < 24000 else { message = "已达到长度上限，请点击完成"; continue }
            output = LongScreenshotStitcher.append(output, frame: frame, height: shift)
            previous = frame
            preview = output
            count += 1
            message = "已拼接 \(count) 帧 · 继续向下滚动或完成"
        }
        return cancelled || Task.isCancelled ? nil : output
    }

    func finish() { finished = true }
    func cancel() { cancelled = true; finished = true }


}

private struct LongCaptureControls: View {
    @ObservedObject var model: LongScreenshotCaptureService
    var body: some View {
        HStack {
            Image(systemName: "rectangle.expand.vertical").foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 3) {
                Text("长截图 · \(model.count) 帧").font(.system(size: 12, weight: .semibold))
                Text(model.message).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button { model.cancel() } label: { Image(systemName: "xmark").foregroundStyle(.red) }.help("取消")
            Divider().frame(height: 20)
            Button { model.finish() } label: { Image(systemName: "checkmark").foregroundStyle(.green) }.help("完成")
        }.buttonStyle(.plain).padding(12).frame(width: 440, height: 70).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct LongCapturePreview: View {
    @ObservedObject var model: LongScreenshotCaptureService
    var body: some View {
        VStack(spacing: 4) {
            if let image = model.preview { Image(nsImage: image).resizable().scaledToFit() }
            Text("实时预览").font(.system(size: 10)).foregroundStyle(.secondary)
        }.padding(6).frame(width: 140, height: 240).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

extension LongScreenshotStitcher {
    /// 对齐相邻帧的内容；返回真实新增高度，拒绝无重叠或低纹理画面。
    static func verticalShift(_ previous: NSImage, _ next: NSImage) -> CGFloat? {
        guard let a = bitmap(previous), let b = bitmap(next), a.pixelsWide == b.pixelsWide, a.pixelsHigh == b.pixelsHigh else { return nil }
        let h = a.pixelsHigh, w = a.pixelsWide
        guard h > 32, w > 16 else { return nil }
        let columns = Array(stride(from: w / 8, to: w * 7 / 8, by: max(1, w / 24)))
        let n = columns.count
        func samples(_ bitmap: NSBitmapImageRep) -> [Double] {
            var result = [Double](repeating: 0, count: h * n)
            guard let cg = bitmap.cgImage else { return result }
            var gray = [UInt8](repeating: 0, count: w * h)
            gray.withUnsafeMutableBytes { bytes in
                guard let context = CGContext(data: bytes.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
                context.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
                for y in 0..<h {
                    for (i, x) in columns.enumerated() {
                        result[y * n + i] = Double(bytes[y * w + x]) / 255
                    }
                }
            }
            return result
        }
        let left = samples(a), right = samples(b)
        var best = Double.infinity
        var bestShift = 0
        for shift in 0...Int(Double(h) * 0.85) {
            var error = 0.0
            var contrast = 0.0
            var total = 0.0
            var samples = 0
            for y in stride(from: h / 16, to: h - shift - h / 16, by: max(1, h / 256)) {
                for i in 0..<n {
                    let l = left[(y + shift) * n + i]
                    let r = right[y * n + i]
                    error += abs(l - r)
                    contrast += l * l
                    total += l
                    samples += 1
                }
            }
            guard samples > 50 else { continue }
            let variance = contrast / Double(samples) - pow(total / Double(samples), 2)
            guard variance > 0.001 else { continue }
            let score = error / Double(samples)
            if score < best { best = score; bestShift = shift }
        }
        return best < 0.015 ? CGFloat(bestShift) * previous.size.height / CGFloat(h) : nil
    }

    static func append(_ output: NSImage, frame: NSImage, height: CGFloat) -> NSImage {
        let result = NSImage(size: CGSize(width: output.size.width, height: output.size.height + height))
        result.lockFocus()
        output.draw(in: CGRect(x: 0, y: height, width: output.size.width, height: output.size.height), from: .zero, operation: .copy, fraction: 1)
        frame.draw(in: CGRect(x: 0, y: 0, width: frame.size.width, height: height), from: CGRect(x: 0, y: 0, width: frame.size.width, height: height), operation: .copy, fraction: 1)
        result.unlockFocus()
        return result
    }
}
