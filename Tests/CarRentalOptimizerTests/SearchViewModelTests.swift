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

    @Test("CAR Inc partial confirmation fees request login prompt even when listings are available")
    func carIncPartialConfirmationFeesRequestLoginPromptEvenWhenListingsAreAvailable() async {
        let viewModel = SearchViewModel(
            searchProvider: StubRentalSearchProvider(results: [
                PlatformEvidenceResult(
                    platform: .carInc,
                    status: PlatformEvidenceStatus(
                        platform: .carInc,
                        kind: .ready,
                        message: "已从神州 API 读取 1 个真实候选车型；确认页费用接口提示登录已失效，当前仅含车辆租赁费。",
                        sourceUrl: "https://www.zuche.com/"
                    ),
                    listings: [
                        makeTestListing(
                            id: "carinc-partial",
                            platform: .carInc,
                            warnings: [.partialPrice, .loginRequired]
                        )
                    ]
                ),
            ]),
            geocoder: CurrentRequestGeocoder(point: AppDefaults.searchRequest.origin),
            mapService: EstimatedMapService()
        )

        await viewModel.runSearch()

        let carIncStatus = viewModel.platformStatus(for: .carInc)
        #expect(carIncStatus.kind == .loginRequired)
        #expect(carIncStatus.message.contains("登录神州"))
        #expect(carIncStatus.message.contains("基础服务费"))
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

    @Test("Displayed results can be sorted by total subtotal distance and completeness")
    func displayedResultsCanBeSortedByTotalSubtotalDistanceAndCompleteness() {
        let viewModel = SearchViewModel(
            searchProvider: StubRentalSearchProvider(results: []),
            geocoder: CurrentRequestGeocoder(point: AppDefaults.searchRequest.origin),
            mapService: EstimatedMapService()
        )
        viewModel.request.vehicleQuery = ""
        viewModel.results = [
            makeTestRecommendation(id: "lowest-rental", rentalTotal: 300, bestTotal: 800, distanceKm: 4.0, dataCompleteness: 0.80),
            makeTestRecommendation(id: "nearest", rentalTotal: 700, bestTotal: 820, distanceKm: 0.5, dataCompleteness: 0.78),
            makeTestRecommendation(id: "most-complete", rentalTotal: 650, bestTotal: 760, distanceKm: 3.0, dataCompleteness: 0.99),
            makeTestRecommendation(id: "lowest-total", rentalTotal: 600, bestTotal: 610, distanceKm: 5.0, dataCompleteness: 0.82),
        ]

        viewModel.recommendationSortMode = .bestTotal
        #expect(viewModel.displayedResults.map(\.id) == ["lowest-total", "most-complete", "lowest-rental", "nearest"])

        viewModel.recommendationSortMode = .rentalSubtotal
        #expect(viewModel.displayedResults.map(\.id) == ["lowest-rental", "lowest-total", "most-complete", "nearest"])

        viewModel.recommendationSortMode = .distance
        #expect(viewModel.displayedResults.map(\.id) == ["nearest", "most-complete", "lowest-rental", "lowest-total"])

        viewModel.recommendationSortMode = .dataCompleteness
        #expect(viewModel.displayedResults.map(\.id) == ["most-complete", "lowest-total", "lowest-rental", "nearest"])
    }

    @Test("Changing sort mode selects the first displayed result")
    func changingSortModeSelectsTheFirstDisplayedResult() {
        let viewModel = SearchViewModel(
            searchProvider: StubRentalSearchProvider(results: []),
            geocoder: CurrentRequestGeocoder(point: AppDefaults.searchRequest.origin),
            mapService: EstimatedMapService()
        )
        viewModel.request.vehicleQuery = ""
        viewModel.results = [
            makeTestRecommendation(id: "lowest-rental", rentalTotal: 300, bestTotal: 800, distanceKm: 4.0, dataCompleteness: 0.80),
            makeTestRecommendation(id: "nearest", rentalTotal: 700, bestTotal: 820, distanceKm: 0.5, dataCompleteness: 0.78),
            makeTestRecommendation(id: "most-complete", rentalTotal: 650, bestTotal: 760, distanceKm: 3.0, dataCompleteness: 0.99),
            makeTestRecommendation(id: "lowest-total", rentalTotal: 600, bestTotal: 610, distanceKm: 5.0, dataCompleteness: 0.82),
        ]

        viewModel.recommendationSortMode = .rentalSubtotal
        viewModel.selectResult("nearest")

        viewModel.recommendationSortMode = .bestTotal
        #expect(viewModel.selected?.id == "lowest-total")

        viewModel.recommendationSortMode = .distance
        #expect(viewModel.selected?.id == "nearest")

        viewModel.recommendationSortMode = .dataCompleteness
        #expect(viewModel.selected?.id == "most-complete")
    }

    @Test("Displayed results apply platform vehicle class budget distance and fee filters")
    func displayedResultsApplyPlatformVehicleClassBudgetDistanceAndFeeFilters() {
        let viewModel = SearchViewModel(
            searchProvider: StubRentalSearchProvider(results: []),
            geocoder: CurrentRequestGeocoder(point: AppDefaults.searchRequest.origin),
            mapService: EstimatedMapService()
        )
        viewModel.request.vehicleQuery = ""
        viewModel.results = [
            makeTestRecommendation(id: "ehi-suv", rentalTotal: 1_120, bestTotal: 1_140, distanceKm: 0.4, dataCompleteness: 0.98, platform: .ehi, vehicleName: "奇瑞 瑞虎8", vehicleClass: "中型SUV"),
            makeTestRecommendation(id: "ehi-suv-incomplete", rentalTotal: 1_080, bestTotal: 1_100, distanceKm: 0.3, dataCompleteness: 0.82, platform: .ehi, vehicleName: "哈弗 H6", vehicleClass: "SUV", warnings: [.partialPrice]),
            makeTestRecommendation(id: "ehi-suv-far", rentalTotal: 1_000, bestTotal: 1_020, distanceKm: 8.0, dataCompleteness: 0.98, platform: .ehi, vehicleName: "长安 CS75", vehicleClass: "SUV"),
            makeTestRecommendation(id: "car-sedan", rentalTotal: 1_030, bestTotal: 1_050, distanceKm: 0.6, dataCompleteness: 0.98, platform: .carInc, vehicleName: "雪佛兰科鲁泽", vehicleClass: "紧凑型车"),
            makeTestRecommendation(id: "ehi-suv-expensive", rentalTotal: 3_100, bestTotal: 3_120, distanceKm: 0.7, dataCompleteness: 0.98, platform: .ehi, vehicleName: "丰田 汉兰达", vehicleClass: "SUV"),
        ]
        viewModel.selectedId = "car-sedan"

        viewModel.recommendationFilter.platform = .ehi
        viewModel.recommendationFilter.vehicleClass = .suv
        viewModel.recommendationFilter.maxTotalCost = .upTo1500
        viewModel.recommendationFilter.maxDistance = .within3
        viewModel.recommendationFilter.hideIncompleteFees = true

        #expect(viewModel.displayedResults.map(\.id) == ["ehi-suv"])
        #expect(viewModel.selected?.id == "ehi-suv")
        #expect(viewModel.filteredResultCount == 1)
        #expect(viewModel.hasActiveRecommendationFilters)

        viewModel.clearRecommendationFilters()

        #expect(viewModel.displayedResults.count == 5)
        #expect(!viewModel.hasActiveRecommendationFilters)
    }

    @Test("Run search clears stale recommendation filters before displaying new results")
    func runSearchClearsStaleRecommendationFiltersBeforeDisplayingNewResults() async {
        let viewModel = SearchViewModel(
            searchProvider: StubRentalSearchProvider(results: [
                PlatformEvidenceResult(
                    platform: .carInc,
                    status: PlatformEvidenceStatus(platform: .carInc, kind: .ready, message: "神州已返回报价。", sourceUrl: "https://www.zuche.com/"),
                    listings: [
                        makeTestListing(
                            id: "carinc-mona",
                            platform: .carInc,
                            vehicleName: "小鹏 MONA",
                            vehicleClass: "纯电 51kWh | 三厢 5座",
                            warnings: []
                        )
                    ]
                ),
            ]),
            geocoder: CurrentRequestGeocoder(point: AppDefaults.searchRequest.origin),
            mapService: EstimatedMapService()
        )
        viewModel.request.vehicleQuery = "小鹏 mona"
        viewModel.recommendationFilter.vehicleClass = .suv
        viewModel.showsAllVehicleMatches = true

        await viewModel.runSearch()

        #expect(viewModel.results.map(\.id) == ["carinc-mona"])
        #expect(viewModel.displayedResults.map(\.id) == ["carinc-mona"])
        #expect(!viewModel.hasActiveRecommendationFilters)
        #expect(!viewModel.showsAllVehicleMatches)
    }

    @Test("Vehicle class filter recognizes sedan MPV EV and unspecified candidates")
    func vehicleClassFilterRecognizesSedanMPVEVAndUnspecifiedCandidates() {
        let viewModel = SearchViewModel(
            searchProvider: StubRentalSearchProvider(results: []),
            geocoder: CurrentRequestGeocoder(point: AppDefaults.searchRequest.origin),
            mapService: EstimatedMapService()
        )
        viewModel.request.vehicleQuery = ""
        viewModel.results = [
            makeTestRecommendation(id: "sedan", rentalTotal: 900, bestTotal: 920, distanceKm: 0.5, dataCompleteness: 0.98, vehicleName: "雪佛兰科鲁泽", vehicleClass: "紧凑型车"),
            makeTestRecommendation(id: "mpv", rentalTotal: 1_600, bestTotal: 1_620, distanceKm: 0.7, dataCompleteness: 0.98, vehicleName: "别克 GL8", vehicleClass: "MPV"),
            makeTestRecommendation(id: "ev", rentalTotal: 1_200, bestTotal: 1_220, distanceKm: 0.8, dataCompleteness: 0.98, vehicleName: "比亚迪 秦PLUS EV", vehicleClass: "新能源"),
            makeTestRecommendation(id: "unspecified", rentalTotal: 1_100, bestTotal: 1_120, distanceKm: 0.3, dataCompleteness: 0.88, vehicleName: "未指定车型", vehicleClass: "未指定车型", matchKind: .notSpecified),
        ]

        viewModel.recommendationFilter.vehicleClass = .sedan
        #expect(viewModel.displayedResults.map(\.id) == ["sedan"])

        viewModel.recommendationFilter.vehicleClass = .mpv
        #expect(viewModel.displayedResults.map(\.id) == ["mpv"])

        viewModel.recommendationFilter.vehicleClass = .newEnergy
        #expect(viewModel.displayedResults.map(\.id) == ["ev"])

        viewModel.recommendationFilter.vehicleClass = .unspecified
        #expect(viewModel.displayedResults.map(\.id) == ["unspecified"])
    }

    @Test("Vehicle class budget and distance filters keep real sedans when platform class is incomplete")
    func vehicleClassBudgetAndDistanceFiltersKeepRealSedansWhenPlatformClassIsIncomplete() {
        let viewModel = SearchViewModel(
            searchProvider: StubRentalSearchProvider(results: []),
            geocoder: CurrentRequestGeocoder(point: AppDefaults.searchRequest.origin),
            mapService: EstimatedMapService()
        )
        viewModel.results = [
            makeTestRecommendation(id: "cruze", rentalTotal: 2_848, bestTotal: 2_850, distanceKm: 0.3, dataCompleteness: 0.90, platform: .carInc, vehicleName: "雪佛兰科鲁泽", vehicleClass: "未指定车型", matchKind: .notSpecified),
            makeTestRecommendation(id: "lavida", rentalTotal: 2_944, bestTotal: 2_946, distanceKm: 0.4, dataCompleteness: 0.90, platform: .carInc, vehicleName: "大众朗逸", vehicleClass: "未指定车型", matchKind: .notSpecified),
            makeTestRecommendation(id: "generic-sedan", rentalTotal: 2_930, bestTotal: 2_932, distanceKm: 0.5, dataCompleteness: 0.90, platform: .carInc, vehicleName: "未指定车型", vehicleClass: "紧凑型车", matchKind: .notSpecified),
            makeTestRecommendation(id: "expensive-sedan", rentalTotal: 3_200, bestTotal: 3_202, distanceKm: 0.3, dataCompleteness: 0.90, platform: .carInc, vehicleName: "日产劲客", vehicleClass: "未指定车型", matchKind: .notSpecified),
            makeTestRecommendation(id: "far-sedan", rentalTotal: 2_860, bestTotal: 2_862, distanceKm: 4.2, dataCompleteness: 0.90, platform: .carInc, vehicleName: "丰田卡罗拉", vehicleClass: "未指定车型", matchKind: .notSpecified),
            makeTestRecommendation(id: "unknown", rentalTotal: 2_820, bestTotal: 2_822, distanceKm: 0.2, dataCompleteness: 0.88, platform: .carInc, vehicleName: "未指定车型", vehicleClass: "未指定车型", matchKind: .notSpecified),
        ]

        viewModel.recommendationFilter.vehicleClass = .sedan
        viewModel.recommendationFilter.maxTotalCost = .upTo3000
        viewModel.recommendationFilter.maxDistance = .within1
        #expect(viewModel.displayedResults.map(\.id) == ["cruze", "generic-sedan", "lavida"])

        viewModel.recommendationFilter.vehicleClass = .all
        #expect(viewModel.displayedResults.map(\.id) == ["unknown", "cruze", "generic-sedan", "lavida"])

        viewModel.recommendationFilter.vehicleClass = .unspecified
        #expect(viewModel.displayedResults.map(\.id) == ["unknown"])
    }

    @Test("Displayed results can deduplicate by store or vehicle using lowest total")
    func displayedResultsCanDeduplicateByStoreOrVehicleUsingLowestTotal() {
        let viewModel = SearchViewModel(
            searchProvider: StubRentalSearchProvider(results: []),
            geocoder: CurrentRequestGeocoder(point: AppDefaults.searchRequest.origin),
            mapService: EstimatedMapService()
        )
        viewModel.request.vehicleQuery = ""
        viewModel.results = [
            makeTestRecommendation(id: "store-a-high", rentalTotal: 1_400, bestTotal: 1_430, distanceKm: 0.5, dataCompleteness: 0.98, storeID: "store-a", vehicleName: "大众朗逸"),
            makeTestRecommendation(id: "store-a-low", rentalTotal: 1_100, bestTotal: 1_130, distanceKm: 0.5, dataCompleteness: 0.98, storeID: "store-a", vehicleName: "雪佛兰科鲁泽"),
            makeTestRecommendation(id: "vehicle-low-cross-platform", rentalTotal: 1_050, bestTotal: 1_080, distanceKm: 2.0, dataCompleteness: 0.98, platform: .carInc, storeID: "store-b", vehicleName: "大众 朗逸"),
            makeTestRecommendation(id: "vehicle-high", rentalTotal: 1_300, bestTotal: 1_330, distanceKm: 0.8, dataCompleteness: 0.98, storeID: "store-c", vehicleName: "大众朗逸"),
        ]

        viewModel.recommendationFilter.deduplicateByStore = true
        #expect(viewModel.displayedResults.map(\.id) == ["vehicle-low-cross-platform", "store-a-low", "vehicle-high"])

        viewModel.recommendationFilter.deduplicateByStore = false
        viewModel.recommendationFilter.deduplicateByVehicle = true
        #expect(viewModel.displayedResults.map(\.id) == ["vehicle-low-cross-platform", "store-a-low"])
    }

    @Test("Concrete vehicle query defaults to cheapest match and can expand all matches")
    func concreteVehicleQueryDefaultsToCheapestMatchAndCanExpandAllMatches() {
        let viewModel = SearchViewModel(
            searchProvider: StubRentalSearchProvider(results: []),
            geocoder: CurrentRequestGeocoder(point: AppDefaults.searchRequest.origin),
            mapService: EstimatedMapService()
        )
        viewModel.request.vehicleQuery = "小鹏 mona"
        viewModel.results = [
            makeTestRecommendation(id: "mona-expensive", rentalTotal: 1_200, bestTotal: 1_220, distanceKm: 0.3, dataCompleteness: 0.98, platform: .carInc, vehicleName: "小鹏 MONA", vehicleClass: "纯电 51kWh | 三厢 5座"),
            makeTestRecommendation(id: "mona-cheap", rentalTotal: 900, bestTotal: 920, distanceKm: 0.5, dataCompleteness: 0.98, platform: .ehi, vehicleName: "小鹏 MONA", vehicleClass: "纯电 51kWh | 三厢 5座"),
            makeTestRecommendation(id: "haval", rentalTotal: 700, bestTotal: 720, distanceKm: 0.4, dataCompleteness: 0.98, vehicleName: "哈弗 H6", vehicleClass: "SUV", matchKind: .lowConfidence),
        ]

        #expect(viewModel.hasExpandableVehicleMatches)
        #expect(viewModel.displayedResults.map(\.id) == ["mona-cheap"])
        #expect(viewModel.vehicleMatchDisplaySummary == "1/2 个匹配，显示最低价")

        viewModel.showsAllVehicleMatches = true

        #expect(viewModel.displayedResults.map(\.id) == ["mona-cheap", "mona-expensive"])
        #expect(viewModel.vehicleMatchDisplaySummary == "2 个匹配已展开")
    }

    @Test("Blank and generic vehicle queries do not collapse concrete matches")
    func blankAndGenericVehicleQueriesDoNotCollapseConcreteMatches() {
        let viewModel = SearchViewModel(
            searchProvider: StubRentalSearchProvider(results: []),
            geocoder: CurrentRequestGeocoder(point: AppDefaults.searchRequest.origin),
            mapService: EstimatedMapService()
        )
        viewModel.results = [
            makeTestRecommendation(id: "suv-a", rentalTotal: 1_000, bestTotal: 1_020, distanceKm: 0.3, dataCompleteness: 0.98, vehicleName: "哈弗 H6", vehicleClass: "SUV", matchKind: .similarClass),
            makeTestRecommendation(id: "suv-b", rentalTotal: 900, bestTotal: 920, distanceKm: 0.5, dataCompleteness: 0.98, vehicleName: "奇瑞 瑞虎8", vehicleClass: "SUV", matchKind: .similarClass),
        ]

        viewModel.request.vehicleQuery = ""
        #expect(!viewModel.hasExpandableVehicleMatches)
        #expect(viewModel.displayedResults.map(\.id) == ["suv-b", "suv-a"])

        viewModel.request.vehicleQuery = "SUV"
        #expect(!viewModel.hasExpandableVehicleMatches)
        #expect(viewModel.displayedResults.map(\.id) == ["suv-b", "suv-a"])
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

    @Test("Retry search requests failed platforms only and reuses successful evidence")
    func retrySearchRequestsFailedPlatformsOnlyAndReusesSuccessfulEvidence() async {
        let provider = SequencedRentalSearchProvider(responses: [
            [
                PlatformEvidenceResult(
                    platform: .ehi,
                    status: PlatformEvidenceStatus(platform: .ehi, kind: .parseFailed, message: "一嗨超时。", sourceUrl: "https://booking.1hai.cn/"),
                    listings: []
                ),
                PlatformEvidenceResult(
                    platform: .carInc,
                    status: PlatformEvidenceStatus(platform: .carInc, kind: .ready, message: "神州已返回报价。", sourceUrl: "https://www.zuche.com/"),
                    listings: [makeTestListing(id: "carinc-first", platform: .carInc, warnings: [])]
                ),
            ],
            [
                PlatformEvidenceResult(
                    platform: .ehi,
                    status: PlatformEvidenceStatus(platform: .ehi, kind: .ready, message: "一嗨已返回报价。", sourceUrl: "https://booking.1hai.cn/"),
                    listings: [makeTestListing(id: "ehi-retry", platform: .ehi, warnings: [])]
                ),
            ],
        ])
        let viewModel = SearchViewModel(
            searchProvider: provider,
            geocoder: CurrentRequestGeocoder(point: AppDefaults.searchRequest.origin),
            mapService: EstimatedMapService()
        )

        await viewModel.runSearch()
        viewModel.showsAllVehicleMatches = true
        await viewModel.retrySearch()

        #expect(provider.requestedPlatforms == [[.ehi, .carInc], [.ehi]])
        #expect(Set(viewModel.searchDiagnosticSummary.successfulPlatforms) == [.ehi, .carInc])
        #expect(viewModel.searchDiagnosticSummary.listingCount == 2)
        #expect(!viewModel.results.isEmpty)
        #expect(viewModel.showsAllVehicleMatches)
        #expect(viewModel.platformStatus(for: .ehi).kind == .ready)
        #expect(viewModel.platformStatus(for: .carInc).kind == .ready)
    }

    @Test("Vehicle suggestions refresh and selection update request")
    func vehicleSuggestionsRefreshAndSelectionUpdateRequest() {
        let store = VehicleSuggestionStore(
            learned: [
                VehicleSuggestion(name: "尚界 H5", source: .learned, aliases: ["h5"], learnedAt: vehicleSuggestionDate("2026-07-02 10:00"), count: 1)
            ],
            recent: [],
            builtIns: [],
            fileURL: temporaryVehicleSuggestionURL()
        )
        let viewModel = SearchViewModel(
            searchProvider: StubRentalSearchProvider(results: []),
            geocoder: CurrentRequestGeocoder(point: AppDefaults.searchRequest.origin),
            mapService: EstimatedMapService(),
            vehicleSuggestionStore: store
        )

        viewModel.refreshVehicleSuggestions(for: "h5")
        #expect(viewModel.vehicleSuggestions.map(\.name) == ["尚界 H5"])
        #expect(viewModel.isVehicleSuggestionPanelVisible)

        let suggestion = viewModel.vehicleSuggestions[0]
        viewModel.selectVehicleSuggestion(suggestion)

        #expect(viewModel.request.vehicleQuery == "尚界 H5")
        #expect(viewModel.vehicleSuggestions.isEmpty)
        #expect(!viewModel.isVehicleSuggestionPanelVisible)
    }

    @Test("Successful blank vehicle search records returned vehicle names")
    func successfulBlankVehicleSearchRecordsReturnedVehicleNames() async {
        let store = VehicleSuggestionStore(
            learned: [],
            recent: [],
            builtIns: [],
            fileURL: temporaryVehicleSuggestionURL()
        )
        let provider = StubRentalSearchProvider(results: [
            PlatformEvidenceResult(
                platform: .carInc,
                status: PlatformEvidenceStatus(platform: .carInc, kind: .ready, message: "ok", sourceUrl: "https://www.zuche.com/"),
                listings: [
                    makeVehicleSuggestionListing(vehicleName: "尚界 H5"),
                    makeVehicleSuggestionListing(vehicleName: "未指定车型")
                ]
            )
        ])
        let viewModel = SearchViewModel(
            searchProvider: provider,
            geocoder: CurrentRequestGeocoder(point: AppDefaults.searchRequest.origin),
            mapService: EstimatedMapService(),
            vehicleSuggestionStore: store
        )
        viewModel.request.vehicleQuery = ""

        await viewModel.runSearch()

        #expect(store.learnedSuggestions.map(\.name) == ["尚界 H5"])
    }

    @Test("Selection emits local vehicle insight immediately and network insight later")
    func selectionEmitsLocalVehicleInsightImmediatelyAndNetworkInsightLater() async {
        let listing = makeTestListing(vehicleName: "大众 朗逸", vehicleClass: "1.5L | 三厢 5座 | 蓝牙")
        let provider = StubRentalSearchProvider(results: [
            PlatformEvidenceResult(
                platform: .ehi,
                status: PlatformEvidenceStatus(platform: .ehi, kind: .ready, message: "一嗨已返回报价。", sourceUrl: "https://booking.1hai.cn/"),
                listings: [listing]
            )
        ])
        let vehicleInsightService = StubVehicleInsightService(networkDelayNanoseconds: 20_000_000)
        let viewModel = SearchViewModel(
            searchProvider: provider,
            geocoder: CurrentRequestGeocoder(point: AppDefaults.searchRequest.origin),
            mapService: EstimatedMapService(),
            vehicleInsightService: vehicleInsightService
        )
        viewModel.request.vehicleQuery = ""

        await viewModel.runSearch()

        #expect(viewModel.selectedVehicleInsight?.origin == .localInference)
        #expect(viewModel.isLoadingSelectedVehicleInsight)
        await waitForVehicleInsightCondition {
            viewModel.selectedVehicleInsight?.origin == .network
        }
        #expect(viewModel.selectedVehicleInsight?.origin == .network)
        #expect(viewModel.selectedVehicleInsight?.sourceName == "Wikipedia")
    }

    @Test("Displayed list rendering does not fetch network insights for every row")
    func displayedListRenderingDoesNotFetchNetworkInsightsForEveryRow() async {
        let recommendations = [
            makeTestListing(id: "vehicle-1", vehicleName: "大众 朗逸", vehicleClass: "1.5L | 三厢 5座"),
            makeTestListing(id: "vehicle-2", vehicleName: "小鹏 MONA", vehicleClass: "纯电 51kWh | 三厢 5座")
        ]
        let provider = StubRentalSearchProvider(results: [
            PlatformEvidenceResult(
                platform: .ehi,
                status: PlatformEvidenceStatus(platform: .ehi, kind: .ready, message: "一嗨已返回报价。", sourceUrl: "https://booking.1hai.cn/"),
                listings: recommendations
            )
        ])
        let vehicleInsightService = StubVehicleInsightService(networkDelayNanoseconds: 0)
        let viewModel = SearchViewModel(
            searchProvider: provider,
            geocoder: CurrentRequestGeocoder(point: AppDefaults.searchRequest.origin),
            mapService: EstimatedMapService(),
            vehicleInsightService: vehicleInsightService
        )
        viewModel.request.vehicleQuery = ""

        await viewModel.runSearch()
        _ = viewModel.displayedResults
        _ = viewModel.displayedResults
        await waitForVehicleInsightCondition {
            vehicleInsightService.networkRequestCount == 1
        }

        #expect(vehicleInsightService.networkRequestCount == 1)
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

private final class StubVehicleInsightService: VehicleInsightProviding {
    private(set) var networkRequestCount = 0
    let networkDelayNanoseconds: UInt64

    init(networkDelayNanoseconds: UInt64) {
        self.networkDelayNanoseconds = networkDelayNanoseconds
    }

    func localInsight(for listing: RentalListing) -> VehicleInsight {
        VehicleInsightLocalInferencer.localInsight(for: listing, now: vehicleInsightStubDate())
    }

    func insight(for listing: RentalListing) async -> VehicleInsight {
        networkRequestCount += 1
        if networkDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: networkDelayNanoseconds)
        }
        var insight = VehicleInsightLocalInferencer.localInsight(for: listing, now: vehicleInsightStubDate())
        insight.origin = .network
        insight.sourceName = "Wikipedia"
        insight.sourceURL = "https://example.com/\(listing.vehicleName)"
        insight.longSummary = "车系介绍：联网测试简介。当前租赁车辆配置以平台返回为准：\(insight.configurationSummary ?? "配置以平台返回为准")。"
        return insight
    }
}

@MainActor
private final class SequencedRentalSearchProvider: RentalSearchProviding {
    private var responses: [[PlatformEvidenceResult]]
    private(set) var requestedPlatforms: [[PlatformId]] = []

    init(responses: [[PlatformEvidenceResult]]) {
        self.responses = responses
    }

    func search(request: SearchRequest) async -> [PlatformEvidenceResult] {
        requestedPlatforms.append(request.platforms)
        guard !responses.isEmpty else { return [] }
        return responses.removeFirst()
    }
}

private struct FailingAddressGeocoder: AddressGeocoding {
    func geocode(_ address: String) async throws -> GeoPoint {
        throw AddressGeocodingError.notFound
    }
}

private func makeTestListing(
    id: String = "ehi-test",
    platform: PlatformId = .ehi,
    vehicleName: String = "奇瑞 瑞虎8",
    vehicleClass: String = "中型SUV",
    warnings: [ResultWarning] = [.partialPrice]
) -> RentalListing {
    RentalListing(
        id: id,
        platform: platform,
        store: Store(
            id: "\(id)-store",
            platform: platform,
            name: "\(platform.label)测试门店",
            city: "北京",
            address: "北京市通州区",
            location: GeoPoint(lat: 39.91, lng: 116.65),
            distanceKm: 3.2,
            hours: "08:00-22:00"
        ),
        vehicleName: vehicleName,
        vehicleClass: vehicleClass,
        basePrice: 320,
        platformFees: 0,
        insuranceFees: 0,
        oneWayFee: 0,
        sourceUrl: "https://booking.1hai.cn/",
        dataCompleteness: 0.88,
        warnings: warnings
    )
}

private func makeVehicleSuggestionListing(vehicleName: String) -> RentalListing {
    RentalListing(
        id: "listing-\(vehicleName)",
        platform: .carInc,
        store: Store(
            id: "store",
            platform: .carInc,
            name: "北京通州店",
            city: "北京",
            address: "北京通州",
            location: AppDefaults.searchRequest.origin,
            distanceKm: 0.5,
            hours: "08:00-21:00"
        ),
        vehicleName: vehicleName,
        vehicleClass: "",
        basePrice: 100,
        platformFees: 0,
        insuranceFees: 0,
        oneWayFee: 0,
        sourceUrl: "https://www.zuche.com/",
        dataCompleteness: 0.8
    )
}

private func temporaryVehicleSuggestionURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("vehicle-suggestions-\(UUID().uuidString).json")
}

private func vehicleSuggestionDate(_ value: String) -> Date {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
    return formatter.date(from: value)!
}

private func vehicleInsightStubDate() -> Date {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
    return formatter.date(from: "2026-07-02 17:14")!
}

@MainActor
private func waitForVehicleInsightCondition(_ condition: @escaping () -> Bool) async {
    for _ in 0..<20 {
        if condition() { return }
        try? await Task.sleep(nanoseconds: 25_000_000)
    }
}

private func makeTestRecommendation(
    id: String,
    rentalTotal: Double,
    bestTotal: Double,
    distanceKm: Double,
    dataCompleteness: Double,
    platform: PlatformId = .ehi,
    storeID: String? = nil,
    vehicleName: String = "奇瑞 瑞虎8",
    vehicleClass: String = "中型SUV",
    matchKind: MatchKind = .exact,
    warnings: [ResultWarning] = []
) -> Recommendation {
    let listing = RentalListing(
        id: id,
        platform: platform,
        store: Store(
            id: storeID ?? "\(id)-store",
            platform: platform,
            name: "\(id)门店",
            city: "北京",
            address: "北京市通州区",
            location: GeoPoint(lat: 39.91, lng: 116.65),
            distanceKm: distanceKm,
            hours: "08:00-22:00"
        ),
        vehicleName: vehicleName,
        vehicleClass: vehicleClass,
        basePrice: rentalTotal,
        platformFees: 0,
        insuranceFees: 0,
        oneWayFee: 0,
        sourceUrl: "https://booking.1hai.cn/",
        dataCompleteness: dataCompleteness,
        warnings: warnings
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
        match: VehicleMatch(kind: matchKind, score: matchKind == .exact ? 1 : 0.7, label: testMatchLabel(for: matchKind)),
        taxiRoute: taxiRoute,
        transitRoute: transitRoute,
        rentalTotal: rentalTotal,
        taxiTotal: bestTotal,
        transitTotal: bestTotal + 20,
        bestTotal: bestTotal,
        bestRouteMode: .taxi,
        warnings: warnings
    )
}

private func testMatchLabel(for kind: MatchKind) -> String {
    switch kind {
    case .exact:
        return "精确匹配"
    case .similarClass:
        return "同级车型"
    case .lowConfidence:
        return "低置信匹配"
    case .notSpecified:
        return "未指定车型"
    }
}
