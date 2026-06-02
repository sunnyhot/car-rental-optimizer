import CarRentalDomain
import Foundation
import SwiftUI

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var request = AppDefaults.searchRequest
    @Published var results: [Recommendation] = []
    @Published var selectedId = ""
    @Published var isSearching = false
    @Published var status = "点击「开始比较」进行查询。"

    var selected: Recommendation? {
        results.first { $0.id == selectedId } ?? results.first
    }

    func runSearch() async {
        isSearching = true
        results = []
        selectedId = ""
        status = "正在使用 Mock 数据计算租车价格、打车成本和公共交通成本..."

        defer {
            isSearching = false
        }

        let recommendations = await searchRentalOptions(
            request: request,
            rentalAdapters: [EhiMockAdapter(), CarIncMockAdapter()],
            mapService: MockMapService()
        )

        results = recommendations
        selectedId = recommendations.first?.id ?? ""
        status = formatSearchCompletionStatus(request: request, resultCount: recommendations.count)
    }

    func selectResult(_ id: String) {
        selectedId = id
    }

    func togglePlatform(_ platform: PlatformId) {
        if request.platforms.contains(platform) {
            if request.platforms.count > 1 {
                request.platforms.removeAll { $0 == platform }
            }
        } else {
            request.platforms.append(platform)
        }

        if !results.isEmpty {
            status = "搜索条件已变更，点击「开始比较」重新计算总成本。"
        }
    }

    func applyDates(pickup: Date, returnDate: Date) {
        request.pickupAt = formatDateTime(pickup)
        request.returnAt = formatDateTime(returnDate)
    }

    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return formatter.string(from: date)
    }
}
