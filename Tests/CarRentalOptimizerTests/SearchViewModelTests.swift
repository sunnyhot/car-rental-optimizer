import Foundation
import CarRentalDomain
import Testing
@testable import CarRentalOptimizer

@Suite("SearchViewModel")
@MainActor
struct SearchViewModelTests {
    @Test("Default search does not fabricate mock recommendations when platform pages are empty")
    func defaultSearchDoesNotFabricateMockRecommendationsWhenPlatformPagesAreEmpty() async {
        let viewModel = SearchViewModel(
            searchProvider: StubRentalSearchProvider(results: [
                PlatformEvidenceResult(
                    platform: .ehi,
                    status: PlatformEvidenceStatus(platform: .ehi, kind: .loginRequired, message: "一嗨需要登录。", sourceUrl: "https://booking.1hai.cn/"),
                    listings: []
                ),
                PlatformEvidenceResult(
                    platform: .carInc,
                    status: PlatformEvidenceStatus(platform: .carInc, kind: .unavailable, message: "神州暂无可租车型。", sourceUrl: "https://m.zuche.com/"),
                    listings: []
                ),
            ]),
            geocoder: CurrentRequestGeocoder(point: AppDefaults.searchRequest.origin),
            mapService: EstimatedMapService()
        )

        await viewModel.runSearch()

        #expect(viewModel.results.isEmpty)
        #expect(viewModel.selectedId.isEmpty)
        #expect(viewModel.status.contains("一嗨需要登录"))
        #expect(!viewModel.status.contains("粘贴"))
        #expect(viewModel.platformStatuses.contains { $0.kind == .loginRequired })
    }

    @Test("Search reads platform snapshots instead of waiting for pasted evidence")
    func searchReadsPlatformSnapshotsInsteadOfWaitingForPastedEvidence() async {
        let provider = StubPlatformSnapshotProvider(snapshots: [
            .ehi: PlatformPageSnapshot(
                platform: .ehi,
                title: "一嗨租车",
                url: "https://booking.1hai.cn/",
                text: """
                一嗨租车
                北京通州万达店
                奇瑞 瑞虎8 1.6T 自动
                租车基础价 ¥12880
                平台服务费 ¥42
                保险保障 ¥55
                """
            ),
            .carInc: PlatformPageSnapshot(
                platform: .carInc,
                title: "神州租车",
                url: "https://www.zuche.com/",
                text: "神州租车\n当前时间段暂未开放租车，请调整取还车日期"
            ),
        ])
        let viewModel = SearchViewModel(snapshotProvider: provider)

        await viewModel.runSearch()

        #expect(provider.requestedPlatforms == [.ehi, .carInc])
        #expect(viewModel.results.count == 1)
        #expect(viewModel.results[0].listing.platform == .ehi)
        #expect(viewModel.results[0].listing.store.name == "北京通州万达店")
        #expect(!viewModel.results.contains { $0.listing.platform == .carInc })
        #expect(viewModel.platformStatuses.contains { $0.platform == .carInc && $0.kind == .unavailable })
    }

    @Test("Date application stores day-only future dates")
    func applyDatesStoresDayOnlyFutureDates() {
        let viewModel = SearchViewModel()
        let calendar = Calendar(identifier: .gregorian)
        let pickup = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        let returnDate = calendar.date(from: DateComponents(year: 2026, month: 10, day: 11))!

        viewModel.applyDates(pickup: pickup, returnDate: returnDate)

        #expect(viewModel.request.pickupAt == "2026-09-01")
        #expect(viewModel.request.returnAt == "2026-10-11")
    }

    @Test("Search progress completes when listings are ranked")
    func searchProgressCompletesWhenListingsAreRanked() async {
        let viewModel = SearchViewModel(
            searchProvider: StubRentalSearchProvider(results: [
                PlatformEvidenceResult(
                    platform: .ehi,
                    status: PlatformEvidenceStatus(platform: .ehi, kind: .ready, message: "一嗨已返回报价。", sourceUrl: "https://booking.1hai.cn/"),
                    listings: [makeTestListing()]
                ),
            ]),
            geocoder: CurrentRequestGeocoder(point: AppDefaults.searchRequest.origin),
            mapService: EstimatedMapService()
        )

        await viewModel.runSearch()

        #expect(viewModel.searchProgressPhase == .completed)
        #expect(viewModel.results.count == 1)
    }

    @Test("Search progress fails when address cannot be resolved")
    func searchProgressFailsWhenAddressCannotBeResolved() async {
        let viewModel = SearchViewModel(
            searchProvider: StubRentalSearchProvider(results: []),
            geocoder: FailingAddressGeocoder(),
            mapService: EstimatedMapService()
        )
        viewModel.request.originLabel = "无法识别的位置"

        await viewModel.runSearch()

        #expect(viewModel.searchProgressPhase == .failed)
        #expect(viewModel.results.isEmpty)
    }

    @Test("Displayed results can be sorted by subtotal distance and completeness")
    func displayedResultsCanBeSortedBySubtotalDistanceAndCompleteness() {
        let viewModel = SearchViewModel(
            searchProvider: StubRentalSearchProvider(results: []),
            geocoder: CurrentRequestGeocoder(point: AppDefaults.searchRequest.origin),
            mapService: EstimatedMapService()
        )
        viewModel.results = [
            makeTestRecommendation(id: "near-complete", rentalTotal: 520, bestTotal: 550, distanceKm: 1.2, dataCompleteness: 0.98),
            makeTestRecommendation(id: "cheap-far", rentalTotal: 280, bestTotal: 640, distanceKm: 21.0, dataCompleteness: 0.72),
            makeTestRecommendation(id: "balanced", rentalTotal: 420, bestTotal: 500, distanceKm: 6.4, dataCompleteness: 0.84),
        ]

        viewModel.recommendationSortMode = .bestTotal
        #expect(viewModel.displayedResults.map(\.id) == ["near-complete", "cheap-far", "balanced"])

        viewModel.recommendationSortMode = .rentalSubtotal
        #expect(viewModel.displayedResults.map(\.id) == ["cheap-far", "balanced", "near-complete"])

        viewModel.recommendationSortMode = .distance
        #expect(viewModel.displayedResults.map(\.id) == ["near-complete", "balanced", "cheap-far"])

        viewModel.recommendationSortMode = .dataCompleteness
        #expect(viewModel.displayedResults.map(\.id) == ["near-complete", "balanced", "cheap-far"])
    }

    @Test("Preflight blocks searches without selected platforms")
    func preflightBlocksSearchesWithoutSelectedPlatforms() async {
        let viewModel = SearchViewModel(
            searchProvider: StubRentalSearchProvider(results: [
                PlatformEvidenceResult(
                    platform: .ehi,
                    status: PlatformEvidenceStatus(platform: .ehi, kind: .ready, message: "不应调用。", sourceUrl: "https://booking.1hai.cn/"),
                    listings: [makeTestListing()]
                ),
            ]),
            geocoder: CurrentRequestGeocoder(point: AppDefaults.searchRequest.origin),
            mapService: EstimatedMapService()
        )
        viewModel.request.platforms = []

        await viewModel.runSearch()

        #expect(viewModel.results.isEmpty)
        #expect(viewModel.searchProgressPhase == .failed)
        #expect(viewModel.preflightIssues.contains { $0.id == "platforms-empty" && $0.severity == .blocking })
        #expect(viewModel.status.contains("请选择平台"))
    }

    @Test("Failed search keeps last successful recommendations as stale results")
    func failedSearchKeepsLastSuccessfulRecommendationsAsStaleResults() async {
        let viewModel = SearchViewModel(
            searchProvider: StubRentalSearchProvider(results: [
                PlatformEvidenceResult(
                    platform: .ehi,
                    status: PlatformEvidenceStatus(platform: .ehi, kind: .ready, message: "一嗨已返回报价。", sourceUrl: "https://booking.1hai.cn/"),
                    listings: [makeTestListing()]
                ),
            ]),
            geocoder: FailingAddressGeocoder(),
            mapService: EstimatedMapService(),
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )

        await viewModel.runSearch()
        let successfulResultIDs = viewModel.results.map(\.id)

        viewModel.request.originLabel = "无法识别的位置"
        await viewModel.runSearch()

        #expect(!successfulResultIDs.isEmpty)
        #expect(viewModel.results.map(\.id) == successfulResultIDs)
        #expect(viewModel.isShowingStaleResults)
        #expect(viewModel.retainedResultsNotice?.title == "显示上次成功结果")
        #expect(viewModel.searchProgressPhase == .failed)
    }
}

@MainActor
private final class StubPlatformSnapshotProvider: PlatformSnapshotProviding {
    private let snapshots: [PlatformId: PlatformPageSnapshot]
    private(set) var requestedPlatforms: [PlatformId] = []

    init(snapshots: [PlatformId: PlatformPageSnapshot] = [:]) {
        self.snapshots = snapshots
    }

    func snapshot(for platform: PlatformId) async throws -> PlatformPageSnapshot {
        requestedPlatforms.append(platform)
        return snapshots[platform] ?? PlatformPageSnapshot(
            platform: platform,
            title: platform.label,
            url: officialPlatformURL(for: platform),
            text: ""
        )
    }
}

private struct StubRentalSearchProvider: RentalSearchProviding {
    let results: [PlatformEvidenceResult]

    func search(request: SearchRequest) async -> [PlatformEvidenceResult] {
        results
    }
}

private struct FailingAddressGeocoder: AddressGeocoding {
    func geocode(_ address: String) async throws -> GeoPoint {
        throw AddressGeocodingError.notFound
    }
}

private func makeTestListing() -> RentalListing {
    RentalListing(
        id: "ehi-test",
        platform: .ehi,
        store: Store(
            id: "ehi-store",
            platform: .ehi,
            name: "一嗨测试门店",
            city: "北京",
            address: "北京市通州区",
            location: GeoPoint(lat: 39.91, lng: 116.65),
            distanceKm: 3.2,
            hours: "08:00-22:00"
        ),
        vehicleName: "奇瑞 瑞虎8",
        vehicleClass: "中型SUV",
        basePrice: 320,
        platformFees: 0,
        insuranceFees: 0,
        oneWayFee: 0,
        sourceUrl: "https://booking.1hai.cn/",
        dataCompleteness: 0.88,
        warnings: [.partialPrice]
    )
}

private func makeTestRecommendation(
    id: String,
    rentalTotal: Double,
    bestTotal: Double,
    distanceKm: Double,
    dataCompleteness: Double
) -> Recommendation {
    let listing = RentalListing(
        id: id,
        platform: .ehi,
        store: Store(
            id: "\(id)-store",
            platform: .ehi,
            name: "\(id)门店",
            city: "北京",
            address: "北京市通州区",
            location: GeoPoint(lat: 39.91, lng: 116.65),
            distanceKm: distanceKm,
            hours: "08:00-22:00"
        ),
        vehicleName: "奇瑞 瑞虎8",
        vehicleClass: "中型SUV",
        basePrice: rentalTotal,
        platformFees: 0,
        insuranceFees: 0,
        oneWayFee: 0,
        sourceUrl: "https://booking.1hai.cn/",
        dataCompleteness: dataCompleteness,
        warnings: []
    )
    let taxiRoute = RouteEstimate(
        mode: .taxi,
        cost: bestTotal - rentalTotal,
        durationMinutes: 18,
        distanceKm: distanceKm,
        summary: "测试路线"
    )
    let transitRoute = RouteEstimate(
        mode: .transit,
        cost: bestTotal - rentalTotal + 20,
        durationMinutes: 36,
        distanceKm: distanceKm,
        summary: "测试公交"
    )
    return Recommendation(
        listing: listing,
        match: VehicleMatch(kind: .exact, score: 1, label: "精确匹配"),
        taxiRoute: taxiRoute,
        transitRoute: transitRoute,
        rentalTotal: rentalTotal,
        taxiTotal: bestTotal,
        transitTotal: bestTotal + 20,
        bestTotal: bestTotal,
        bestRouteMode: .taxi,
        warnings: []
    )
}
