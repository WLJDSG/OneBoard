import SwiftUI
import QuickLook
import QuickLookThumbnailing
import ImageIO

enum ClipboardCategory: String, CaseIterable, Identifiable {
    case all = "全部", text = "文本", image = "图片", link = "链接", color = "颜色", file = "文件"
    var id: String { rawValue }
    func matches(_ entry: ClipboardEntry) -> Bool {
        if self == .all { return true }
        if self == .image { return entry.isImage }
        if self == .file { return entry.contentTypeEnum == .fileURL }
        guard !entry.isImage, entry.contentTypeEnum != .fileURL else { return false }
        let text = String((entry.plainText ?? "").prefix(2048)).trimmingCharacters(in: .whitespacesAndNewlines)
        let isLink = !text.contains(where: { $0.isWhitespace }) && URL(string: text).map { ["https", "http"].contains($0.scheme?.lowercased() ?? "") && $0.host != nil } == true
        let isColor = text.range(of: "^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$", options: .regularExpression) != nil
        if self == .link { return isLink }
        if self == .color { return isColor }
        return !isLink && !isColor
    }
}

struct ClipboardBrowserView: View {
    @ObservedObject var viewModel: ClipboardListViewModel
    @State private var category = ClipboardCategory.all
    @State private var selectedID: Int64?
    private var filtered: [ClipboardEntry] { viewModel.entries.filter { category.matches($0) } }
    private var selected: ClipboardEntry? { filtered.first { $0.id == selectedID } ?? filtered.first }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                ForEach(ClipboardCategory.allCases) { item in
                    Button { category = item; selectedID = nil } label: {
                        Text(item.rawValue).font(.system(size: 12, weight: .medium)).padding(.horizontal, 10).padding(.vertical, 8)
                            .background(category == item ? Color.accentColor.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                    }.buttonStyle(.plain)
                }
                Spacer()
                Text("共 \(filtered.count) 条").font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 14)
            HSplitView {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(filtered) { entry in
                            ClipboardRowView(entry: entry, onTap: { selectedID = entry.id },
                                onPin: { Task { await viewModel.togglePin(entry) } },
                                onDelete: { Task { await viewModel.delete(entry) } },
                                onDoubleTap: { viewModel.selectAndPaste(entry) })
                            .padding(.vertical, 8)
                            .background(selected?.id == entry.id ? Color.accentColor.opacity(0.13) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
                            .contextMenu {
                                Button("复制") { viewModel.copy(entry) }
                                Button("粘贴到原应用") { viewModel.selectAndPaste(entry) }
                            }
                        }
                    }.padding(10)
                }.frame(minWidth: 270, idealWidth: 330, maxWidth: 430)
                Group {
                    if let entry = selected {
                        ClipboardDetailView(entry: entry, viewModel: viewModel).id(entry.id)
                    } else {
                        ContentUnavailableView("暂无内容", systemImage: "doc.on.clipboard", description: Text("复制内容后会自动记录，也可以切换筛选条件"))
                    }
                }.frame(minWidth: 350, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private struct ClipboardDetailView: View {
    let entry: ClipboardEntry
    @ObservedObject var viewModel: ClipboardListViewModel
    @State private var previewImage: NSImage?
    private var fileURL: URL? {
        guard entry.contentTypeEnum == .fileURL, let raw = String(data: entry.data, encoding: .utf8) else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.hasPrefix("file://") ? URL(string: value) : URL(fileURLWithPath: value)
    }
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("预览").font(.headline)
                Spacer()
                Button("复制") { viewModel.copy(entry) }
                Button("粘贴") { viewModel.selectAndPaste(entry) }
                Button { Task { await viewModel.togglePin(entry) } } label: { Image(systemName: entry.isPinned ? "pin.fill" : "pin") }
                Button { Task { await viewModel.delete(entry) } } label: { Image(systemName: "trash") }
            }
            Group {
                if entry.isImage {
                    if let image = previewImage {
                        Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
                } else if let url = fileURL {
                    if FileManager.default.fileExists(atPath: url.path) {
                        ClipboardFilePreview(url: url)
                    } else { ContentUnavailableView("文件已移动或删除", systemImage: "doc.badge.ellipsis", description: Text(url.lastPathComponent)) }
                } else {
                    ScrollView {
                        Text(entry.plainText ?? String(data: entry.data, encoding: .utf8) ?? "无法预览此内容")
                            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .topLeading).padding(12)
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                Text(entry.sourceAppBundleId?.split(separator: ".").last.map(String.init) ?? "剪贴板")
                Text(entry.createdAt, style: .relative)
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: Int64(entry.data.count), countStyle: .file))
            }.font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }.padding(18).background(.background.opacity(0.65), in: RoundedRectangle(cornerRadius: 20)).padding(10)
        .task {
            guard entry.isImage else { return }
            previewImage = await ClipboardThumbnailCache.image(for: entry)
            let data = entry.data
            let cg = await Task.detached(priority: .userInitiated) {
                guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil as CGImage? }
                return CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1800] as CFDictionary)
            }.value
            if !Task.isCancelled, let cg { previewImage = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)) }
        }
    }
}

struct ClipboardFilePreview: View {
    let url: URL
    @State private var thumbnail: NSImage?
    @State private var failed = false
    @State private var previewURL: URL?
    var body: some View {
        VStack {
            if let thumbnail { Image(nsImage: thumbnail).resizable().scaledToFit() }
            else if failed { Image(systemName: "doc").font(.system(size: 54)).foregroundStyle(.secondary) }
            else { ProgressView() }
            Text(url.lastPathComponent).lineLimit(2)
            Button("快速查看") { previewURL = url }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .quickLookPreview($previewURL)
        .task(id: url) {
            thumbnail = nil; failed = false
            let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 1000, height: 1000), scale: 1, representationTypes: .all)
            do {
                let result = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
                guard !Task.isCancelled else { return }
                thumbnail = result.nsImage
            } catch { if !Task.isCancelled { failed = true } }
        }
    }
}
