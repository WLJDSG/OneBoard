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

enum LongCaptureOverlayLayout {
    struct Segment {
        let start: CGPoint
        let end: CGPoint
    }

    static func dimPath(in bounds: CGRect, selection: CGRect) -> NSBezierPath {
        let path = NSBezierPath(rect: bounds)
        let hole = selection.intersection(bounds)
        if !hole.isNull { path.appendRect(hole) }
        path.windingRule = .evenOdd
        return path
    }

    static func cornerSegments(in rect: CGRect, length: CGFloat = 22) -> [Segment] {
        let length = min(length, rect.width / 2, rect.height / 2)
        return [
            Segment(start: CGPoint(x: rect.minX, y: rect.minY), end: CGPoint(x: rect.minX + length, y: rect.minY)),
            Segment(start: CGPoint(x: rect.minX, y: rect.minY), end: CGPoint(x: rect.minX, y: rect.minY + length)),
            Segment(start: CGPoint(x: rect.maxX, y: rect.minY), end: CGPoint(x: rect.maxX - length, y: rect.minY)),
            Segment(start: CGPoint(x: rect.maxX, y: rect.minY), end: CGPoint(x: rect.maxX, y: rect.minY + length)),
            Segment(start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.minX + length, y: rect.maxY)),
            Segment(start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.minX, y: rect.maxY - length)),
            Segment(start: CGPoint(x: rect.maxX, y: rect.maxY), end: CGPoint(x: rect.maxX - length, y: rect.maxY)),
            Segment(start: CGPoint(x: rect.maxX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.maxY - length)),
        ]
    }
}

private struct LongCaptureCornerGuide: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for segment in LongCaptureOverlayLayout.cornerSegments(in: rect.insetBy(dx: 2, dy: 2)) {
            path.move(to: segment.start)
            path.addLine(to: segment.end)
        }
        return path
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
        finished = false; cancelled = false; count = 1
        guard let screenIndex = NSScreen.screens.firstIndex(where: { $0.frame.intersects(selectionRect) }) else { return initial }
        let screen = NSScreen.screens[screenIndex]
        let border = NSPanel(contentRect: selectionRect.insetBy(dx: -3, dy: -3), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        border.isOpaque = false
        border.hasShadow = false
        border.backgroundColor = .clear
        border.ignoresMouseEvents = true
        border.level = .floating
        border.contentView = NSHostingView(rootView: LongCaptureCornerGuide().stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round)))
        let controls = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 390, height: 76), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        controls.isFloatingPanel = true
        controls.level = .floating
        controls.isOpaque = false
        controls.backgroundColor = .clear
        controls.contentView = NSHostingView(rootView: LongCaptureControls(model: self))
        let x = min(max(screen.visibleFrame.minX, selectionRect.midX - 195), screen.visibleFrame.maxX - 390)
        let y = selectionRect.minY - 86 >= screen.visibleFrame.minY ? selectionRect.minY - 86 : min(screen.visibleFrame.maxY - 76, selectionRect.maxY + 10)
        controls.setFrameOrigin(CGPoint(x: x, y: y))
        border.orderFrontRegardless()
        controls.orderFrontRegardless()
        let previewPanel = NSPanel(contentRect: CGRect(x: min(selectionRect.maxX + 12, screen.visibleFrame.maxX - 150), y: selectionRect.maxY - 240, width: 140, height: 240), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        previewPanel.level = .floating; previewPanel.isOpaque = false; previewPanel.backgroundColor = .clear
        previewPanel.contentView = NSHostingView(rootView: LongCapturePreview(model: self))
        previewPanel.orderFrontRegardless()
        // 每屏一个无边线、无阴影、鼠标透传的暗罩；选区挖空，捕获过滤器排除自身。
        let masks = NSScreen.screens.map { display -> NSPanel in
            let mask = NSPanel(contentRect: display.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            mask.isOpaque = false; mask.backgroundColor = .clear; mask.hasShadow = false
            mask.ignoresMouseEvents = true; mask.level = .floating
            mask.contentView = LongCaptureDimView(frame: CGRect(origin: .zero, size: display.frame.size),
                selection: selectionRect.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY))
            mask.orderFrontRegardless()
            return mask
        }
        border.orderFrontRegardless(); controls.orderFrontRegardless(); previewPanel.orderFrontRegardless()
        defer { masks.forEach { $0.close() }; border.close(); controls.close(); previewPanel.close() }
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
            if finished || Task.isCancelled { break }
            let cg = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            let frame = cg.map { NSImage(cgImage: $0, size: selectionRect.size) }
            guard let frame else { message = "抓取失败，请检查屏幕录制权限"; continue }
            let prior = previous
            let shift = await Task.detached(priority: .userInitiated) { LongScreenshotStitcher.verticalShift(prior, frame) }.value
            if finished || Task.isCancelled { break }
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
        HStack(spacing: 12) {
            Image(systemName: "rectangle.expand.vertical")
                .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 38, height: 38).background(Color.accentColor, in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 3) {
                Text("长截图 · \(model.count) 帧").font(.system(size: 12, weight: .semibold))
                Text(model.message).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button { model.cancel() } label: { Image(systemName: "xmark").frame(width: 30, height: 30).background(Color.primary.opacity(0.06), in: Circle()) }.help("取消")
            Button { model.finish() } label: { Label("完成", systemImage: "checkmark").font(.system(size: 12, weight: .semibold)).padding(.horizontal, 12).frame(height: 32).foregroundStyle(.white).background(Color.accentColor, in: Capsule()) }.help("完成")
        }.buttonStyle(.plain).padding(12).frame(width: 390, height: 76)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.22)))
            .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
    }
}

private struct LongCapturePreview: View {
    @ObservedObject var model: LongScreenshotCaptureService
    var body: some View {
        VStack(spacing: 6) {
            if let image = model.preview { Image(nsImage: image).resizable().scaledToFit() }
            Text("实时预览 · \(model.count) 帧").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
        }.padding(8).frame(width: 140, height: 240)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.2)))
            .shadow(color: .black.opacity(0.14), radius: 14, y: 6)
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
        var scores: [(Int, Double)] = []
        // 至少保留 35% 重叠；过短的空白/重复区域不能证明滚动。
        for shift in 0...Int(Double(h) * 0.65) {
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
            scores.append((shift, score))
            if score < best { best = score; bestShift = shift }
        }
        guard best < 0.015 else { return nil }
        if bestShift == 0 { return 0 }
        // 重复段落会产生多个同样好的位移。宁可等待用户回滚，也不猜一个偏移追加。
        let tolerance = max(2, Int(CGFloat(h) / previous.size.height))
        if let runner = scores.filter({ abs($0.0 - bestShift) > tolerance }).map(\.1).min(), runner < best + 0.003 { return nil }
        if let stationary = scores.first(where: { $0.0 == 0 })?.1, best > stationary * 0.5 { return nil }
        return CGFloat(bestShift) * previous.size.height / CGFloat(h)
    }

    static func append(_ output: NSImage, frame: NSImage, height: CGFloat) -> NSImage {
        guard let prior = output.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let next = frame.cgImage(forProposedRect: nil, context: nil, hints: nil),
              prior.width == next.width, frame.size.height > 0 else { return output }
        let scale = CGFloat(next.height) / frame.size.height
        let added = min(next.height, max(0, Int((height * scale).rounded())))
        guard added > 0, let strip = next.cropping(to: CGRect(x: 0, y: next.height - added, width: next.width, height: added)),
              let context = CGContext(data: nil, width: prior.width, height: prior.height + added, bitsPerComponent: 8,
                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return output }
        context.interpolationQuality = .none
        context.draw(prior, in: CGRect(x: 0, y: added, width: prior.width, height: prior.height))
        context.draw(strip, in: CGRect(x: 0, y: 0, width: prior.width, height: added))
        guard let result = context.makeImage() else { return output }
        return NSImage(cgImage: result, size: CGSize(width: output.size.width, height: output.size.height + CGFloat(added) / scale))
    }
}

private final class LongCaptureDimView: NSView {
    let selection: CGRect
    init(frame: CGRect, selection: CGRect) { self.selection = selection; super.init(frame: frame) }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        let path = LongCaptureOverlayLayout.dimPath(in: bounds, selection: selection)
        NSColor.black.withAlphaComponent(0.42).setFill()
        path.fill()
    }
}
