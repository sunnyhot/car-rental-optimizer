import CarRentalDomain
import Foundation
import SwiftUI

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var request = AppDefaults.searchRequest
    @Published var results: [Recommendation] = []
    @Published var platformStatuses: [PlatformEvidenceStatus] = AppDefaults.searchRequest.platforms.map {
        PlatformEvidenceStatus(
            platform: $0,
            kind: .waitingForEvidence,
            message: "等待在\($0.label)官方页面完成搜索。",
            sourceUrl: officialPlatformURL(for: $0)
        )
    }
    @Published var selectedId = ""
    @Published var isSearching = false
    @Published var status = "在官方页面完成搜索后，点击「开始比较」自动读取当前页面。"

    private let snapshotProvider: PlatformSnapshotProviding

    init() {
        self.snapshotProvider = EmptyPlatformSnapshotProvider()
    }

    init(snapshotProvider: PlatformSnapshotProviding) {
        self.snapshotProvider = snapshotProvider
    }

    var selected: Recommendation? {
        results.first { $0.id == selectedId } ?? results.first
    }

    func runSearch() async {
        isSearching = true
        results = []
        selectedId = ""
        status = "正在读取官方页面，并计算到店路线估算成本..."

        defer {
            isSearching = false
        }

        var evidenceResults: [PlatformEvidenceResult] = []
        for platform in request.platforms {
            do {
                let snapshot = try await snapshotProvider.snapshot(for: platform)
                evidenceResults.append(parsePlatformEvidence(
                    input: PlatformEvidenceInput(
                        platform: platform,
                        text: snapshot.text,
                        sourceUrl: snapshot.url
                    ),
                    request: request
                ))
            } catch {
                evidenceResults.append(snapshotFailureResult(platform: platform, error: error))
            }
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

    func platformStatus(for platform: PlatformId) -> PlatformEvidenceStatus {
        platformStatuses.first { $0.platform == platform } ?? PlatformEvidenceStatus(
            platform: platform,
            kind: .waitingForEvidence,
            message: "等待在\(platform.label)官方页面完成搜索。",
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
        return "等待官方页面搜索结果：请在内嵌官方页面完成搜索后再次比较。"
    }

    let messages = evidenceResults.map(\.status.message)
    return messages.joined(separator: "；")
}

private func snapshotFailureResult(platform: PlatformId, error: Error) -> PlatformEvidenceResult {
    PlatformEvidenceResult(
        platform: platform,
        status: PlatformEvidenceStatus(
            platform: platform,
            kind: .parseFailed,
            message: "\(platform.label)官方页面读取失败：\(error.localizedDescription)",
            sourceUrl: officialPlatformURL(for: platform)
        ),
        listings: []
    )
}
