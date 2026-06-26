import SwiftUI

/// 待办历史与统计视图
struct TodoHistoryView: View {
    @StateObject private var viewModel = TodoHistoryViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // 头部
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 14, weight: .semibold))
                Text("待办历史")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("关闭") { dismiss() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 总览统计
                    overviewSection

                    Divider().padding(.horizontal)

                    // 每日完成柱状图
                    dailyChartSection

                    Divider().padding(.horizontal)

                    // 来源应用统计
                    sourceAppSection
                }
                .padding()
            }
        }
        .frame(width: 360, height: 440)
        .background(.regularMaterial)
        .task {
            await viewModel.load()
        }
    }

    // MARK: - 总览

    private var overviewSection: some View {
        VStack(spacing: 8) {
            Text("总览")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 0) {
                statItem(title: "总待办", value: "\(viewModel.totalCount)", color: .primary)
                Divider().frame(height: 30)
                statItem(title: "已完成", value: "\(viewModel.totalCompleted)", color: .green)
                Divider().frame(height: 30)
                statItem(title: "完成率", value: viewModel.completionRateText, color: .accentColor)
            }
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.03)))
        }
    }

    private func statItem(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(color)
            Text(title)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 每日完成

    private var dailyChartSection: some View {
        VStack(spacing: 8) {
            Text("每日完成趋势（近30天）")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if viewModel.dailyCounts.isEmpty {
                Text("暂无数据")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
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
                                    .foregroundColor(entry.count > 0 ? .accentColor : .clear)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(entry.count > 0 ? Color.accentColor : Color.secondary.opacity(0.1))
                                    .frame(
                                        width: 8,
                                        height: max(4, CGFloat(entry.count) / CGFloat(max(maxCount, 1)) * 60)
                                    )
                                Text(String(entry.date.suffix(5)))  // MM-DD
                                    .font(.system(size: 7))
                                    .foregroundColor(.secondary)
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
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if viewModel.sourceAppStats.isEmpty {
                Text("暂无数据")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
            } else {
                let maxCount = viewModel.sourceAppStats.map(\.count).max() ?? 1
                let stats = viewModel.sourceAppStats.prefix(10)
                ForEach(Array(stats.enumerated()), id: \.offset) { _, entry in
                    HStack(spacing: 8) {
                        Text(appName(for: entry.bundleId) ?? "未知来源")
                            .font(.system(size: 12))
                            .frame(width: 80, alignment: .leading)
                            .lineLimit(1)

                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.accentColor.opacity(0.6))
                                .frame(width: max(10, CGFloat(entry.count) / CGFloat(maxCount) * geo.size.width))
                        }
                        .frame(height: 12)

                        Text("\(entry.count)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
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
