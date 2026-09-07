import SwiftUI

struct NotchShelfView: View {
    @ObservedObject var viewModel: FileStagingViewModel
    var animatesPresentation = false
    @State private var sharingTarget = false
    @State private var stagingTarget = false

    var body: some View {
        GeometryReader { geometry in
            shelfContent
                .scaleEffect(x: geometry.size.width / NotchShelfAnimationLayout.expandedSize.width,
                             y: geometry.size.height / NotchShelfAnimationLayout.expandedSize.height,
                             anchor: .topLeading)
        }
        .scaleEffect(
            x: animatesPresentation && !viewModel.isShelfExpanded ? NotchShelfAnimationLayout.collapsedScale.width : 1,
            y: animatesPresentation && !viewModel.isShelfExpanded ? NotchShelfAnimationLayout.collapsedScale.height : 1,
            anchor: .top)
    }

    private var shelfContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Color.clear.frame(height: 18)
            HStack(spacing: 8) {
                Image(systemName: "tray.fill").foregroundStyle(FeaturePalette.accent)
                Text("文件暂存").font(.system(size: 15, weight: .semibold))
                Text("\(viewModel.stagedFiles.count)").font(.system(size: 10, weight: .medium, design: .rounded))
                    .padding(.horizontal, 7).padding(.vertical, 3).background(.white.opacity(0.09), in: Capsule())
                Spacer()

            }
            HStack(spacing: 10) {
                zone("拖入暂存", subtitle: "放在这里，随时拖走", icon: "tray.and.arrow.down", targeted: stagingTarget, accent: true)
                    .overlay(FileDropTarget(targeted: $stagingTarget) { urls in urls.forEach { viewModel.addFile(url: $0) } })
                zone("隔空投送", subtitle: "AirDrop", icon: "airplayaudio", targeted: sharingTarget, accent: false)
                    .frame(width: 124)
                    .overlay(FileDropTarget(targeted: $sharingTarget) { viewModel.airDrop($0) })
            }
            if viewModel.stagedFiles.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "doc.on.doc").font(.system(size: 22, weight: .regular)).foregroundStyle(.white.opacity(0.2))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("给文件一个临时落脚点").font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.85))
                        Text("拖到这里，再拖入访达或其他应用").font(.system(size: 11)).foregroundStyle(.white.opacity(0.65))
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.stagedFiles) { file in
                            HStack(spacing: 8) {
                                HStack(spacing: 8) {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: file.fileURL)).resizable().frame(width: 30, height: 30)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(file.fileName).font(.system(size: 11, weight: .medium)).lineLimit(1)
                                        Text(ByteCountFormatter.string(fromByteCount: file.fileSize, countStyle: .file))
                                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.65))
                                    }.frame(width: 90, alignment: .leading)
                                }.padding(.vertical, 10).overlay(FileDragSource(url: URL(fileURLWithPath: file.fileURL)))
                                Button { Task { await viewModel.removeFile(file) } } label: {
                                    Image(systemName: "xmark").font(.system(size: 11)).foregroundStyle(.white.opacity(0.65)).frame(width: 20, height: 30)
                                }.buttonStyle(.plain).help("移出暂存，不删除原文件")
                            }.padding(.leading, 10).padding(.trailing, 4)
                                .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }.scrollIndicators(.hidden).frame(maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 26).padding(.bottom, 16)
        .frame(width: NotchShelfAnimationLayout.expandedSize.width, height: NotchShelfAnimationLayout.expandedSize.height)
        .foregroundStyle(.white)
        .background(Color(white: 0.045))
        .environment(\.colorScheme, .dark)
        .clipShape(NotchShelfShape())
        .ignoresSafeArea()
        .alert("文件暂存", isPresented: Binding(get: { viewModel.stagingError != nil }, set: { if !$0 { viewModel.stagingError = nil } })) {
            Button("好") { viewModel.stagingError = nil }
        } message: { Text(viewModel.stagingError ?? "") }
        .alert("隔空投送", isPresented: Binding(get: { viewModel.sharingError != nil }, set: { if !$0 { viewModel.sharingError = nil } })) {
            Button("好") { viewModel.sharingError = nil }
        } message: { Text(viewModel.sharingError ?? "") }
    }

    private func zone(_ title: String, subtitle: String, icon: String, targeted: Bool, accent: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 20, weight: .regular))
                .foregroundStyle(accent ? FeaturePalette.accent : .white.opacity(0.65))
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.white.opacity(0.65))
            }
        }.frame(maxWidth: .infinity).frame(height: 68)
            .background(targeted ? FeaturePalette.accent.opacity(0.22) : .white.opacity(accent ? 0.07 : 0.035), in: RoundedRectangle(cornerRadius: InterfaceMetrics.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: InterfaceMetrics.cardRadius).strokeBorder(targeted ? FeaturePalette.accent.opacity(0.8) : .white.opacity(0.08)))
    }
}

/// 顶部内凹肩线与屏幕边缘相切，避免面板像直角矩形贴在刘海下方。
private struct NotchShelfShape: Shape {
    func path(in rect: CGRect) -> Path {
        let shoulder: CGFloat = 12
        let corner: CGFloat = 24
        let left = rect.minX + shoulder
        let right = rect.maxX - shoulder
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addCurve(to: CGPoint(x: right, y: rect.minY + shoulder),
            control1: CGPoint(x: right, y: rect.minY), control2: CGPoint(x: right, y: rect.minY + 4))
        path.addLine(to: CGPoint(x: right, y: rect.maxY - corner))
        path.addQuadCurve(to: CGPoint(x: right - corner, y: rect.maxY), control: CGPoint(x: right, y: rect.maxY))
        path.addLine(to: CGPoint(x: left + corner, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: left, y: rect.maxY - corner), control: CGPoint(x: left, y: rect.maxY))
        path.addLine(to: CGPoint(x: left, y: rect.minY + shoulder))
        path.addCurve(to: CGPoint(x: rect.minX, y: rect.minY),
            control1: CGPoint(x: left, y: rect.minY + 4), control2: CGPoint(x: left, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
