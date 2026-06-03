import CarRentalDomain
import Foundation
import SwiftUI

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var request = AppDefaults.searchRequest
    @Published var results: [Recommendation] = []
    @Published var platformEvidenceText: [PlatformId: String] = [:]
    @Published var platformStatuses: [PlatformEvidenceStatus] = AppDefaults.searchRequest.platforms.map {
        PlatformEvidenceStatus(
            platform: $0,
            kind: .waitingForEvidence,
            message: "等待粘贴\($0.label)官方搜索页面内容。",
            sourceUrl: officialPlatformURL(for: $0)
        )
    }
    @Published var selectedId = ""
    @Published var isSearching = false
    @Published var status = "粘贴官方页面数据后，点击「开始比较」进行查询。"

    var selected: Recommendation? {
        results.first { $0.id == selectedId } ?? results.first
    }

    func runSearch() async {
        isSearching = true
        results = []
        selectedId = ""
        status = "正在读取官方页面证据，并计算到店路线估算成本..."

        defer {
            isSearching = false
        }

        let evidenceResults = request.platforms.map { platform in
            parsePlatformEvidence(
                input: PlatformEvidenceInput(
                    platform: platform,
                    text: platformEvidenceText[platform] ?? "",
                    sourceUrl: officialPlatformURL(for: platform)
                ),
                request: request
            )
        }
        platformStatuses = evidenceResults.map(\.status)

        let listings = evidenceResults.flatMap(\.listings)
        guard !listings.isEmpty else {
            status = formatNoOfficialListingsStatus(evidenceResults)
            return
        }

        let recommendations = await rankRentalListings(
            request: request,
            listings: listings,
            mapService: EstimatedMapService()
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

    func updateEvidenceText(_ text: String, for platform: PlatformId) {
        platformEvidenceText[platform] = text
        if !results.isEmpty {
            status = "官方页面数据已变更，点击「开始比较」重新计算总成本。"
        }
    }

    func evidenceText(for platform: PlatformId) -> String {
        platformEvidenceText[platform] ?? ""
    }

    func platformStatus(for platform: PlatformId) -> PlatformEvidenceStatus {
        platformStatuses.first { $0.platform == platform } ?? PlatformEvidenceStatus(
            platform: platform,
            kind: .waitingForEvidence,
            message: "等待粘贴\(platform.label)官方搜索页面内容。",
            sourceUrl: officialPlatformURL(for: platform)
        )
    }

    func applyDates(pickup: Date, returnDate: Date) {
        let normalized = AppDateRules.normalizedRange(pickup: pickup, returnDate: returnDate)
        request.pickupAt = AppDateRules.formatRequestDate(normalized.pickup)
        request.returnAt = AppDateRules.formatRequestDate(normalized.returnDate)
    }
}

func officialPlatformURL(for platform: PlatformId) -> String {
    switch platform {
    case .ehi:
        return "https://www.1hai.cn/"
    case .carInc:
        return "https://www.zuche.com/"
    }
}

private func formatNoOfficialListingsStatus(_ evidenceResults: [PlatformEvidenceResult]) -> String {
    if evidenceResults.allSatisfy({ $0.status.kind == .waitingForEvidence }) {
        return "等待官方页面数据：请打开平台完成搜索后，把页面文本粘贴进来。"
    }

    let messages = evidenceResults.map(\.status.message)
    return messages.joined(separator: "；")
}
