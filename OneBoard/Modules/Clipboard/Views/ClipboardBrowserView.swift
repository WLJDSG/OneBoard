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
                        Text(item.rawValue)
                    }.buttonStyle(FeatureSelectionStyle(selected: category == item))
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
                            .background(selected?.id == entry.id ? FeaturePalette.accent.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
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
                        FeatureEmptyState(title: "暂无内容", subtitle: "复制内容后会自动记录，也可以切换筛选条件", icon: "doc.on.clipboard")
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
                Button("粘贴") { viewModel.selectAndPaste(entry) }.buttonStyle(SettingsActionStyle(prominent: true))
                FeaturePanelIconButton(icon: entry.isPinned ? "pin.fill" : "pin", title: entry.isPinned ? "取消置顶" : "置顶", selected: entry.isPinned) { Task { await viewModel.togglePin(entry) } }
                FeaturePanelIconButton(icon: "trash", title: "删除记录") { Task { await viewModel.delete(entry) } }
            }
            Group {
                if entry.isImage {
                    if let image = previewImage {
                        Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
                } else if let url = fileURL {
                    ClipboardFilePreview(url: url)
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
        }.padding(16).featureCardStyle().padding(10)
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
    @State private var allowedProtectedPreview = false
    private var needsAccessGuide: Bool {
        PermissionManager.isOtherAppDataURL(url) && !allowedProtectedPreview
    }
    var body: some View {
        VStack {
            if needsAccessGuide {
                Image(systemName: "lock.doc").font(.system(size: 36)).foregroundStyle(.secondary)
                Text("此文件位于其他 App 的数据目录")
                Text("可先为 OneBoard 开启完全磁盘访问，重启后重试；已授权时可继续预览。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("管理完全磁盘访问权限") { PermissionManager.shared.openFullDiskAccessSettings() }
                Button("继续预览") { allowedProtectedPreview = true }
            } else if let thumbnail { Image(nsImage: thumbnail).resizable().scaledToFit() }
            else if failed { Image(systemName: "doc").font(.system(size: 54)).foregroundStyle(.secondary) }
            else { ProgressView() }
            Text(url.lastPathComponent).lineLimit(2)
            Button("快速查看") { previewURL = url }.disabled(needsAccessGuide)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .quickLookPreview($previewURL)
        .task(id: "\(url.absoluteString)|\(needsAccessGuide)") {
            thumbnail = nil; failed = false
            guard !needsAccessGuide else { return }
            let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 1000, height: 1000), scale: 1, representationTypes: .all)
            do {
                let result = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
                guard !Task.isCancelled else { return }
                thumbnail = result.nsImage
            } catch {
                if !Task.isCancelled {
                    failed = true
                    PermissionManager.shared.handleFileAccessError(error)
                }
            }
        }
    }
}
