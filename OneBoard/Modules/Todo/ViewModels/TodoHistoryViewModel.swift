import Foundation
import SwiftUI

/// 待办历史统计 ViewModel
@MainActor
final class TodoHistoryViewModel: ObservableObject {
    @Published var dailyCounts: [(date: String, count: Int)] = []
    @Published var sourceAppStats: [(bundleId: String?, count: Int)] = []
    @Published var totalCompleted: Int = 0
    @Published var totalCount: Int = 0

    private let repository = TodoRepository()

    var completionRateText: String {
        guard totalCount > 0 else { return "0%" }
        let rate = Double(totalCompleted) / Double(totalCount) * 100
        return String(format: "%.0f%%", rate)
    }

    func load() async {
        do {
            dailyCounts = try await repository.dailyCompletionCount(days: 30)
            sourceAppStats = try await repository.sourceAppStats()
            totalCompleted = try await repository.totalCompleted()
            totalCount = try await repository.totalCount()
        } catch {
            print("[TodoHistoryViewModel] 加载统计失败: \(error)")
        }
    }
}
