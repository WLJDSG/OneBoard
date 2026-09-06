import SwiftUI
import UniformTypeIdentifiers

struct NotchShelfView: View {
    @ObservedObject var viewModel: FileStagingViewModel
    @State private var sharingTarget = false
    @State private var stagingTarget = false
    var body: some View {
        VStack(spacing: 12) {
            Color.black.frame(height: 22)
            HStack {
                Label("暂存中转", systemImage: "tray.fill").font(.system(size: 12, weight: .semibold))
                Text("\(viewModel.stagedFiles.count) 个文件").font(.caption).foregroundStyle(.white.opacity(0.5))
                Spacer()
                Button { viewModel.airDrop(viewModel.stagedFiles.map { URL(fileURLWithPath: $0.fileURL) }) } label: { Image(systemName: "airplayaudio") }.help("隔空投送暂存文件")
                Button { viewModel.hideFloatingShelf() } label: { Image(systemName: "chevron.up") }.help("收起")
            }.buttonStyle(.plain)
            HStack(spacing: 10) {
                zone("隔空投送", icon: "airplayaudio", targeted: sharingTarget)
                    .overlay(FileDropTarget(targeted: $sharingTarget) { viewModel.airDrop($0) })
                zone("拖入暂存", icon: "tray.and.arrow.down", targeted: stagingTarget)
                    .overlay(FileDropTarget(targeted: $stagingTarget) { urls in urls.forEach { viewModel.addFile(url: $0) } })
            }
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(viewModel.stagedFiles) { file in
                        HStack(spacing: 6) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: file.fileURL)).resizable().frame(width: 24, height: 24)
                            Text(file.fileName).font(.system(size: 10)).lineLimit(1).frame(maxWidth: 110)
                            Button { Task { await viewModel.removeFile(file) } } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.4)) }.buttonStyle(.plain)
                        }.padding(7).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                            .onDrag { NSItemProvider(contentsOf: URL(fileURLWithPath: file.fileURL)) ?? NSItemProvider() }
                    }
                }
            }.scrollIndicators(.hidden)
        }.padding(.horizontal, 16).padding(.bottom, 14).frame(width: 440, height: 220)
            .foregroundStyle(.white)
            .background(LinearGradient(colors: [.black, Color(red: 0.09, green: 0.08, blue: 0.17)], startPoint: .top, endPoint: .bottom))
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 24, bottomTrailingRadius: 24))
            .ignoresSafeArea()
            .alert("隔空投送", isPresented: Binding(get: { viewModel.sharingError != nil }, set: { if !$0 { viewModel.sharingError = nil } })) {
                Button("好") { viewModel.sharingError = nil }
            } message: { Text(viewModel.sharingError ?? "") }
    }
    private func zone(_ title: String, icon: String, targeted: Bool) -> some View {
        Label(title, systemImage: icon).font(.system(size: 12, weight: .medium))
            .frame(maxWidth: .infinity).frame(height: 54)
            .background(targeted ? Color.blue.opacity(0.5) : .white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(targeted ? 0.5 : 0.1)))
    }
}
