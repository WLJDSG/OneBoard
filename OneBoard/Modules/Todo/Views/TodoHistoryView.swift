import SwiftUI

/// 待办历史与统计视图
struct TodoHistoryView: View {
    @StateObject private var viewModel = TodoHistoryViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            FeaturePanelHeader(title: "待办历史", subtitle: "完成趋势与来源统计", icon: "clock.arrow.circlepath") {
                FeaturePanelIconButton(icon: "xmark", title: "关闭") { dismiss() }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 总览统计
                    SettingsCard { overviewSection.padding(16) }


                    // 每日完成柱状图
                    SettingsCard { dailyChartSection.padding(16) }


                    // 来源应用统计
                    SettingsCard { sourceAppSection.padding(16) }
                }
                .padding()
            }
        }
        .frame(width: 360, height: 440)
        .featurePanelStyle()
        .task {
            await viewModel.load()
        }
    }

    // MARK: - 总览

    private var overviewSection: some View {
        VStack(spacing: 8) {
            Text("总览")
                .oneBoardFont(.caption)
                .foregroundColor(FeaturePalette.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 0) {
                statItem(title: "总待办", value: "\(viewModel.totalCount)", color: FeaturePalette.text)
                Divider().frame(height: 30)
                statItem(title: "已完成", value: "\(viewModel.totalCompleted)", color: OneBoardColors.success)
                Divider().frame(height: 30)
                statItem(title: "完成率", value: viewModel.completionRateText, color: FeaturePalette.accent)
            }
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: OneBoardRadius.lg).fill(FeaturePalette.text.opacity(0.03)))
        }
    }

    private func statItem(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .oneBoardFont(.titleLarge)
                .foregroundColor(color)
            Text(title)
                .oneBoardFont(.captionSmall)
                .foregroundColor(FeaturePalette.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 每日完成

    private var dailyChartSection: some View {
        VStack(spacing: 8) {
            Text("每日完成趋势（近30天）")
                .oneBoardFont(.caption)
                .foregroundColor(FeaturePalette.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if viewModel.dailyCounts.isEmpty {
                Text("暂无数据")
                    .oneBoardFont(.callout)
                    .foregroundColor(FeaturePalette.secondary)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
            } else {
                let maxCount = viewModel.dailyCounts.map(\.count).max() ?? 1
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .bottom, spacing: 2) {
                        ForEach(viewModel.dailyCounts, id: \.date) { entry in
                            VStack(spacing: 2) {
                                Text("\(entry.count)")
                                    .font(.system(size: 8))
                                    .foregroundColor(entry.count > 0 ? FeaturePalette.accent : .clear)
                                RoundedRectangle(cornerRadius: OneBoardRadius.sm)
                                    .fill(entry.count > 0 ? FeaturePalette.accent : FeaturePalette.secondary.opacity(0.1))
                                    .frame(
                                        width: 8,
                                        height: max(4, CGFloat(entry.count) / CGFloat(max(maxCount, 1)) * 60)
                                    )
                                Text(String(entry.date.suffix(5)))  // MM-DD
                                    .font(.system(size: 7))
                                    .foregroundColor(FeaturePalette.secondary)
                            }
                        }
                    }
                }
                .frame(height: 80)
            }
        }
    }

    // MARK: - 来源应用

    private var sourceAppSection: some View {
        VStack(spacing: 8) {
            Text("来源应用分布")
                .oneBoardFont(.caption)
                .foregroundColor(FeaturePalette.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if viewModel.sourceAppStats.isEmpty {
                Text("暂无数据")
                    .oneBoardFont(.callout)
                    .foregroundColor(FeaturePalette.secondary)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
            } else {
                let maxCount = viewModel.sourceAppStats.map(\.count).max() ?? 1
                let stats = viewModel.sourceAppStats.prefix(10)
                ForEach(Array(stats.enumerated()), id: \.offset) { _, entry in
                    HStack(spacing: 8) {
                        Text(appName(for: entry.bundleId) ?? "未知来源")
                            .oneBoardFont(.callout)
                            .frame(width: 80, alignment: .leading)
                            .lineLimit(1)

                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: OneBoardRadius.sm)
                                .fill(FeaturePalette.accent.opacity(0.6))
                                .frame(width: max(10, CGFloat(entry.count) / CGFloat(maxCount) * geo.size.width))
                        }
                        .frame(height: 12)

                        Text("\(entry.count)")
                            .oneBoardFont(.caption)
                            .foregroundColor(FeaturePalette.secondary)
                            .frame(width: 30, alignment: .trailing)
                    }
                }
            }
        }
    }

    private func appName(for bundleId: String?) -> String? {
        guard let bundleId else { return nil }
        let known: [String: String] = [
            "com.apple.Safari": "Safari",
            "com.google.Chrome": "Chrome",
            "com.microsoft.VSCode": "VS Code",
        ]
        if let name = known[bundleId] { return name }
        return bundleId.components(separatedBy: ".").last
    }
}
