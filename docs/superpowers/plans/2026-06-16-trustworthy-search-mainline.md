# Trustworthy Search Mainline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the search flow more trustworthy by adding preflight validation, diagnostics, recovery suggestions, unified quote credibility, and retained last-successful results after transient failures.

**Architecture:** Keep official-data search and ranking behavior unchanged. Add deterministic app-layer presentation models in `CarRentalOptimizer`, then have `SearchViewModel` derive state from existing `PlatformEvidenceResult`, `Recommendation`, and `ResultWarning` values. SwiftUI views only render these models and trigger existing actions such as retry and Ehi login.

**Tech Stack:** Swift 5.9, SwiftUI, Swift Testing, Swift Package Manager.

---

## File Structure

- Create `Sources/CarRentalOptimizer/SearchTrustPresentation.swift`
  - Owns app-layer value types for preflight issues, diagnostic summaries, platform recovery suggestions, quote credibility, and retained stale-result notices.
  - Imports `CarRentalDomain` and `Foundation`.
- Modify `Sources/CarRentalOptimizer/SearchViewModel.swift`
  - Publishes preflight issues, diagnostic summary, stale-result state, and last successful search time.
  - Runs preflight validation before platform calls.
  - Retains the latest successful recommendations after address or platform failures.
- Modify `Sources/CarRentalOptimizer/SearchPanelView.swift`
  - Shows preflight warnings and disables compare only for blocking preflight issues.
- Modify `Sources/CarRentalOptimizer/ResultPanelView.swift`
  - Shows stale-result and diagnostic banners.
  - Shows platform recovery suggestions in empty/error states.
  - Uses unified quote credibility in result rows.
- Modify `Sources/CarRentalOptimizer/DetailPanelView.swift`
  - Uses unified quote credibility in recommendation detail and platform comparison rows.
- Create `Tests/CarRentalOptimizerTests/SearchTrustPresentationTests.swift`
  - Covers deterministic mapping behavior for new presentation models.
- Modify `Tests/CarRentalOptimizerTests/SearchViewModelTests.swift`
  - Covers preflight blocking, diagnostics, and retained last-successful results.

## Task 1: Add Search Trust Presentation Models

**Files:**
- Create: `Sources/CarRentalOptimizer/SearchTrustPresentation.swift`
- Create: `Tests/CarRentalOptimizerTests/SearchTrustPresentationTests.swift`

- [ ] **Step 1: Write the failing presentation tests**

Create `Tests/CarRentalOptimizerTests/SearchTrustPresentationTests.swift` with this content:

```swift
import CarRentalDomain
import Foundation
import Testing
@testable import CarRentalOptimizer

@Suite("Search trust presentation")
struct SearchTrustPresentationTests {
    @Test("Preflight validation reports blocking platform issue")
    func preflightValidationReportsBlockingPlatformIssue() {
        var request = AppDefaults.searchRequest
        request.platforms = []

        let result = validateSearchPreflight(request)

        #expect(result.hasBlockingIssue)
        #expect(result.issues.map(\.id).contains("platforms-empty"))
        #expect(result.issues.first { $0.id == "platforms-empty" }?.severity == .blocking)
    }

    @Test("Preflight validation reports helpful warnings")
    func preflightValidationReportsHelpfulWarnings() {
        var request = AppDefaults.searchRequest
        request.originLabel = "   "
        request.radiusKm = 420
        request.vehicleQuery = "瑞虎8 Pro 四驱七座"

        let result = validateSearchPreflight(request)

        #expect(!result.hasBlockingIssue)
        #expect(result.issues.map(\.id).contains("origin-empty"))
        #expect(result.issues.map(\.id).contains("specific-vehicle-wide-radius"))
    }

    @Test("Platform recovery actions are deterministic")
    func platformRecoveryActionsAreDeterministic() {
        let login = PlatformEvidenceStatus(
            platform: .ehi,
            kind: .loginRequired,
            message: "一嗨需要登录。",
            sourceUrl: "https://booking.1hai.cn/"
        )
        let parseFailed = PlatformEvidenceStatus(
            platform: .carInc,
            kind: .parseFailed,
            message: "神州返回字段未识别。",
            sourceUrl: "https://m.zuche.com/"
        )

        #expect(SearchRecoveryAction.actions(for: login).map(\.id) == ["ehi-login", "retry-same-request"])
        #expect(SearchRecoveryAction.actions(for: parseFailed).map(\.id) == ["retry-later", "open-platform"])
    }

    @Test("Quote credibility prefers concrete warning labels")
    func quoteCredibilityPrefersConcreteWarningLabels() {
        let complete = QuoteCredibility.make(for: makeRecommendation(dataCompleteness: 0.96, warnings: []))
        let partial = QuoteCredibility.make(for: makeRecommendation(dataCompleteness: 0.88, warnings: [.partialPrice]))
        let routeMissing = QuoteCredibility.make(for: makeRecommendation(dataCompleteness: 0.96, warnings: [.mapCostMissing]))
        let crossCity = QuoteCredibility.make(for: makeRecommendation(dataCompleteness: 0.96, warnings: [.crossCityPickup]))

        #expect(complete.level == .complete)
        #expect(complete.title == "完整报价")
        #expect(partial.level == .reviewRecommended)
        #expect(partial.title == "部分费用待复核")
        #expect(routeMissing.title == "路线估算缺失")
        #expect(crossCity.title == "跨城/异店风险")
    }

    @Test("Diagnostic summary counts platform outcomes")
    func diagnosticSummaryCountsPlatformOutcomes() {
        let evidenceResults = [
            PlatformEvidenceResult(
                platform: .ehi,
                status: PlatformEvidenceStatus(platform: .ehi, kind: .ready, message: "一嗨已返回 2 个报价。", sourceUrl: "https://booking.1hai.cn/"),
                listings: [makeListing(id: "ehi-1"), makeListing(id: "ehi-2")]
            ),
            PlatformEvidenceResult(
                platform: .carInc,
                status: PlatformEvidenceStatus(platform: .carInc, kind: .captchaRequired, message: "神州需要验证。", sourceUrl: "https://m.zuche.com/"),
                listings: []
            ),
        ]

        let summary = SearchDiagnosticSummary.make(
            evidenceResults: evidenceResults,
            recommendations: [makeRecommendation(id: "ehi-1")]
        )

        #expect(summary.queriedPlatforms == [.ehi, .carInc])
        #expect(summary.successfulPlatforms == [.ehi])
        #expect(summary.failedStatuses.map(\.kind) == [.captchaRequired])
        #expect(summary.listingCount == 2)
        #expect(summary.visibleResultCount == 1)
        #expect(summary.routeEstimateStatus == "路线估算已参与排序")
    }
}

private func makeRecommendation(
    id: String = "rec-1",
    dataCompleteness: Double = 0.96,
    warnings: [ResultWarning] = []
) -> Recommendation {
    let listing = makeListing(id: id, dataCompleteness: dataCompleteness, warnings: warnings)
    let taxi = RouteEstimate(mode: .taxi, cost: 38, durationMinutes: 22, distanceKm: listing.store.distanceKm, summary: "打车约 22 分钟")
    let transit = RouteEstimate(mode: .transit, cost: 6, durationMinutes: 44, distanceKm: listing.store.distanceKm, summary: "公交约 44 分钟")
    return buildRecommendation(
        listing: listing,
        match: VehicleMatch(kind: .exact, score: 1, label: "精确匹配"),
        taxiRoute: taxi,
        transitRoute: transit
    )
}

private func makeListing(
    id: String,
    dataCompleteness: Double = 0.96,
    warnings: [ResultWarning] = []
) -> RentalListing {
    RentalListing(
        id: id,
        platform: .ehi,
        store: Store(
            id: "\(id)-store",
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
        platformFees: 20,
        insuranceFees: 50,
        oneWayFee: 0,
        sourceUrl: "https://booking.1hai.cn/",
        dataCompleteness: dataCompleteness,
        warnings: warnings
    )
}
```

- [ ] **Step 2: Run focused tests to verify they fail**

Run:

```bash
swift test --filter SearchTrustPresentation
```

Expected: compile failure because `validateSearchPreflight`, `SearchRecoveryAction`, `QuoteCredibility`, and `SearchDiagnosticSummary` do not exist.

- [ ] **Step 3: Implement the presentation models**

Create `Sources/CarRentalOptimizer/SearchTrustPresentation.swift` with this content:

```swift
import CarRentalDomain
import Foundation

enum SearchPreflightSeverity: Equatable {
    case warning
    case blocking
}

struct SearchPreflightIssue: Equatable, Identifiable {
    let id: String
    let severity: SearchPreflightSeverity
    let title: String
    let message: String
}

struct SearchPreflightResult: Equatable {
    let issues: [SearchPreflightIssue]

    var hasBlockingIssue: Bool {
        issues.contains { $0.severity == .blocking }
    }
}

func validateSearchPreflight(_ request: SearchRequest) -> SearchPreflightResult {
    var issues: [SearchPreflightIssue] = []
    let origin = request.originLabel.trimmingCharacters(in: .whitespacesAndNewlines)
    let vehicleQuery = request.vehicleQuery.trimmingCharacters(in: .whitespacesAndNewlines)

    if request.platforms.isEmpty {
        issues.append(SearchPreflightIssue(
            id: "platforms-empty",
            severity: .blocking,
            title: "请选择平台",
            message: "至少选择一嗨或神州中的一个平台后才能开始比较。"
        ))
    }

    if origin.isEmpty {
        issues.append(SearchPreflightIssue(
            id: "origin-empty",
            severity: .warning,
            title: "当前位置为空",
            message: "地址为空时平台查询可能无法开始，请输入出发地或使用定位。"
        ))
    }

    if AppDateRules.parseRequestDate(request.pickupAt) == nil || AppDateRules.parseRequestDate(request.returnAt) == nil {
        issues.append(SearchPreflightIssue(
            id: "date-format-invalid",
            severity: .blocking,
            title: "日期格式异常",
            message: "取还车日期需要是 yyyy-MM-dd 格式。"
        ))
    }

    if vehicleQuery.isEmpty {
        issues.append(SearchPreflightIssue(
            id: "vehicle-empty",
            severity: .warning,
            title: "未指定车型",
            message: "车型为空时会比较半径内可识别车型，不会按具体车型去重。"
        ))
    }

    if request.radiusKm >= 300 && vehicleQuery.count >= 6 {
        issues.append(SearchPreflightIssue(
            id: "specific-vehicle-wide-radius",
            severity: .warning,
            title: "搜索范围较大",
            message: "具体车型配合大半径会查询更多门店，结果可能更慢，也更容易遇到平台风控。"
        ))
    }

    return SearchPreflightResult(issues: issues)
}

struct SearchDiagnosticSummary: Equatable {
    let queriedPlatforms: [PlatformId]
    let successfulPlatforms: [PlatformId]
    let failedStatuses: [PlatformEvidenceStatus]
    let listingCount: Int
    let visibleResultCount: Int
    let routeEstimateStatus: String
    let notes: [String]

    static let empty = SearchDiagnosticSummary(
        queriedPlatforms: [],
        successfulPlatforms: [],
        failedStatuses: [],
        listingCount: 0,
        visibleResultCount: 0,
        routeEstimateStatus: "尚未估算路线",
        notes: []
    )

    static func make(
        evidenceResults: [PlatformEvidenceResult],
        recommendations: [Recommendation]
    ) -> SearchDiagnosticSummary {
        let queriedPlatforms = evidenceResults.map(\.platform)
        let successfulPlatforms = evidenceResults
            .filter { $0.status.kind == .ready }
            .map(\.platform)
        let failedStatuses = evidenceResults
            .map(\.status)
            .filter { $0.kind != .ready }
        let listingCount = evidenceResults.reduce(0) { $0 + $1.listings.count }
        let routeEstimateStatus = recommendations.isEmpty ? "未生成路线估算" : "路线估算已参与排序"
        let notes = failedStatuses.map { "\($0.platform.label)：\($0.message)" }

        return SearchDiagnosticSummary(
            queriedPlatforms: queriedPlatforms,
            successfulPlatforms: successfulPlatforms,
            failedStatuses: failedStatuses,
            listingCount: listingCount,
            visibleResultCount: recommendations.count,
            routeEstimateStatus: routeEstimateStatus,
            notes: notes
        )
    }
}

struct SearchRecoveryAction: Equatable, Identifiable {
    let id: String
    let title: String
    let message: String
    let systemImage: String
    let opensEhiLogin: Bool
    let opensPlatform: Bool

    static func actions(for status: PlatformEvidenceStatus) -> [SearchRecoveryAction] {
        switch status.kind {
        case .loginRequired:
            if status.platform == .ehi {
                return [
                    SearchRecoveryAction(
                        id: "ehi-login",
                        title: "登录一嗨",
                        message: "登录后会复用本机保存的 1hai session，再重试同一查询。",
                        systemImage: "person.badge.key.fill",
                        opensEhiLogin: true,
                        opensPlatform: false
                    ),
                    retrySameRequest,
                ]
            }
            return [openPlatform, retrySameRequest]
        case .captchaRequired:
            return [
                SearchRecoveryAction(
                    id: "refresh-login",
                    title: "刷新验证页",
                    message: "平台要求验证码或安全验证，刷新登录页后再重试。",
                    systemImage: "shield.lefthalf.filled",
                    opensEhiLogin: status.platform == .ehi,
                    opensPlatform: status.platform != .ehi
                ),
                retrySameRequest,
            ]
        case .parseFailed:
            return [retryLater, openPlatform]
        case .unavailable:
            return [
                SearchRecoveryAction(
                    id: "adjust-conditions",
                    title: "调整条件",
                    message: "可放宽车型、扩大半径或更换取还车日期后重新比较。",
                    systemImage: "slider.horizontal.3",
                    opensEhiLogin: false,
                    opensPlatform: false
                ),
                retryLater,
            ]
        case .waitingForEvidence:
            return [retrySameRequest]
        case .ready:
            return []
        }
    }

    private static let retrySameRequest = SearchRecoveryAction(
        id: "retry-same-request",
        title: "重试本次查询",
        message: "保留当前条件并重新调用平台接口。",
        systemImage: "arrow.clockwise",
        opensEhiLogin: false,
        opensPlatform: false
    )

    private static let retryLater = SearchRecoveryAction(
        id: "retry-later",
        title: "稍后重试",
        message: "平台接口或字段可能临时变化，稍后重试可确认是否恢复。",
        systemImage: "clock.arrow.circlepath",
        opensEhiLogin: false,
        opensPlatform: false
    )

    private static let openPlatform = SearchRecoveryAction(
        id: "open-platform",
        title: "打开原始平台",
        message: "在官方页面复核实时可订价格和门店状态。",
        systemImage: "arrow.up.right.square",
        opensEhiLogin: false,
        opensPlatform: true
    )
}

enum QuoteCredibilityLevel: Equatable {
    case complete
    case reviewRecommended
    case blocked
}

struct QuoteCredibility: Equatable {
    let level: QuoteCredibilityLevel
    let title: String
    let message: String
    let systemImage: String

    static func make(for recommendation: Recommendation) -> QuoteCredibility {
        let warnings = recommendation.warnings

        if warnings.contains(.loginRequired) || warnings.contains(.captchaRequired) {
            return QuoteCredibility(
                level: .blocked,
                title: "平台验证受限",
                message: "平台要求登录或验证后才能确认完整报价。",
                systemImage: "person.crop.circle.badge.exclamationmark"
            )
        }

        if warnings.contains(.partialPrice) {
            return QuoteCredibility(
                level: .reviewRecommended,
                title: "部分费用待复核",
                message: "平台未完整返回服务费、保险或异店还车费，下单前请打开原始平台复核。",
                systemImage: "exclamationmark.circle.fill"
            )
        }

        if warnings.contains(.mapCostMissing) {
            return QuoteCredibility(
                level: .reviewRecommended,
                title: "路线估算缺失",
                message: "交通成本暂不可用，当前排序主要参考租车价格。",
                systemImage: "map.fill"
            )
        }

        if warnings.contains(.crossCityPickup) {
            return QuoteCredibility(
                level: .reviewRecommended,
                title: "跨城/异店风险",
                message: "跨城或异店方案需要额外复核门店营业时间、交通衔接和平台费用。",
                systemImage: "arrow.triangle.swap"
            )
        }

        if recommendation.listing.dataCompleteness < 0.9 {
            return QuoteCredibility(
                level: .reviewRecommended,
                title: "报价完整度偏低",
                message: "平台返回字段不够完整，下单前请复核总价。",
                systemImage: "doc.text.magnifyingglass"
            )
        }

        return QuoteCredibility(
            level: .complete,
            title: "完整报价",
            message: "平台返回的价格字段较完整，仍建议下单前复核实时可订价格。",
            systemImage: "checkmark.seal.fill"
        )
    }
}

struct RetainedResultsNotice: Equatable {
    let title: String
    let message: String
    let lastSuccessfulSearchAt: Date

    static func make(lastSuccessfulSearchAt: Date) -> RetainedResultsNotice {
        RetainedResultsNotice(
            title: "显示上次成功结果",
            message: "本次查询未完成，当前候选来自上次成功查询，请复核时间和平台实时价格。",
            lastSuccessfulSearchAt: lastSuccessfulSearchAt
        )
    }
}
```

- [ ] **Step 4: Run focused presentation tests**

Run:

```bash
swift test --filter SearchTrustPresentation
```

Expected: all `SearchTrustPresentation` tests pass.

- [ ] **Step 5: Commit**

Run:

```bash
git add Sources/CarRentalOptimizer/SearchTrustPresentation.swift Tests/CarRentalOptimizerTests/SearchTrustPresentationTests.swift
git commit -m "Add search trust presentation models"
```

## Task 2: Integrate Preflight and Retained Results in SearchViewModel

**Files:**
- Modify: `Sources/CarRentalOptimizer/SearchViewModel.swift`
- Modify: `Tests/CarRentalOptimizerTests/SearchViewModelTests.swift`

- [ ] **Step 1: Add failing ViewModel tests**

Append these tests inside `SearchViewModelTests` before the closing brace:

```swift
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
```

- [ ] **Step 2: Run focused tests to verify they fail**

Run:

```bash
swift test --filter SearchViewModel
```

Expected: compile failure because `preflightIssues`, `isShowingStaleResults`, `retainedResultsNotice`, and the `now` initializer argument do not exist.

- [ ] **Step 3: Add ViewModel state and initializer injection**

In `Sources/CarRentalOptimizer/SearchViewModel.swift`, add these published properties after `searchProgressPhase`:

```swift
    @Published var preflightIssues: [SearchPreflightIssue] = []
    @Published var searchDiagnosticSummary: SearchDiagnosticSummary = .empty
    @Published var isShowingStaleResults = false
    @Published var retainedResultsNotice: RetainedResultsNotice?
    @Published var lastSuccessfulSearchAt: Date?
```

Add these private properties after `resolvedOriginLabel`:

```swift
    private let now: () -> Date
    private var latestSuccessfulResults: [Recommendation] = []
    private var latestSuccessfulSelectedId = ""
```

Update each initializer so it assigns `now`:

```swift
    init() {
        self.searchProvider = LiveRentalSearchService()
        self.geocoder = AppleAddressGeocoder()
        self.mapService = AppleMapService()
        self.currentLocationProvider = AppleCurrentLocationProvider()
        self.addressSuggestionProvider = AppleAddressSuggestionProvider()
        self.resolvedOriginLabel = AppDefaults.searchRequest.originLabel
        self.now = Date.init
    }
```

```swift
    init(snapshotProvider: PlatformSnapshotProviding) {
        self.searchProvider = SnapshotRentalSearchService(snapshotProvider: snapshotProvider)
        self.geocoder = CurrentRequestGeocoder(point: AppDefaults.searchRequest.origin)
        self.mapService = EstimatedMapService()
        self.currentLocationProvider = UnavailableCurrentLocationProvider()
        self.addressSuggestionProvider = EmptyAddressSuggestionProvider()
        self.resolvedOriginLabel = AppDefaults.searchRequest.originLabel
        self.now = Date.init
    }
```

Replace the third initializer signature and body header with:

```swift
    init(
        searchProvider: RentalSearchProviding,
        geocoder: AddressGeocoding,
        mapService: MapService,
        currentLocationProvider: CurrentLocationProviding = UnavailableCurrentLocationProvider(),
        addressSuggestionProvider: AddressSuggestionProviding = EmptyAddressSuggestionProvider(),
        now: @escaping () -> Date = Date.init
    ) {
        self.searchProvider = searchProvider
        self.geocoder = geocoder
        self.mapService = mapService
        self.currentLocationProvider = currentLocationProvider
        self.addressSuggestionProvider = addressSuggestionProvider
        self.resolvedOriginLabel = AppDefaults.searchRequest.originLabel
        self.now = now
    }
```

Add these computed properties and helpers near `displayedResults`:

```swift
    var hasBlockingPreflightIssues: Bool {
        preflightIssues.contains { $0.severity == .blocking }
    }

    func refreshPreflightIssues() {
        preflightIssues = validateSearchPreflight(request).issues
    }

    private func recordSuccessfulResults(_ recommendations: [Recommendation]) {
        latestSuccessfulResults = recommendations
        latestSuccessfulSelectedId = recommendations.first?.id ?? ""
        lastSuccessfulSearchAt = now()
        isShowingStaleResults = false
        retainedResultsNotice = nil
    }

    private func restoreLatestSuccessfulResultsIfAvailable() {
        guard !latestSuccessfulResults.isEmpty, let lastSuccessfulSearchAt else {
            results = []
            selectedId = ""
            isShowingStaleResults = false
            retainedResultsNotice = nil
            return
        }

        results = latestSuccessfulResults
        selectedId = latestSuccessfulSelectedId
        isShowingStaleResults = true
        retainedResultsNotice = RetainedResultsNotice.make(lastSuccessfulSearchAt: lastSuccessfulSearchAt)
    }
```

- [ ] **Step 4: Wire preflight and stale restore into `runSearch()`**

In `runSearch()`, replace the opening state setup:

```swift
        dismissOriginSuggestions()
        isSearching = true
        results = []
        selectedId = ""
        searchProgressPhase = .resolvingLocation
        status = "正在解析当前位置，并静默调用平台 API..."
```

with:

```swift
        dismissOriginSuggestions()
        refreshPreflightIssues()
        if hasBlockingPreflightIssues {
            searchProgressPhase = .failed
            status = preflightIssues.first(where: { $0.severity == .blocking })?.message ?? "搜索条件不完整。"
            searchDiagnosticSummary = .empty
            return
        }

        isSearching = true
        isShowingStaleResults = false
        retainedResultsNotice = nil
        results = []
        selectedId = ""
        searchProgressPhase = .resolvingLocation
        status = "正在解析当前位置，并静默调用平台 API..."
```

In the address failure `catch`, replace:

```swift
            status = "当前位置解析失败：\(error.localizedDescription)"
            searchProgressPhase = .failed
            platformStatuses = request.platforms.map {
                PlatformEvidenceStatus(platform: $0, kind: .parseFailed, message: "地址解析失败，暂未调用\($0.label)。", sourceUrl: officialPlatformURL(for: $0))
            }
            return
```

with:

```swift
            status = "当前位置解析失败：\(error.localizedDescription)"
            searchProgressPhase = .failed
            platformStatuses = request.platforms.map {
                PlatformEvidenceStatus(platform: $0, kind: .parseFailed, message: "地址解析失败，暂未调用\($0.label)。", sourceUrl: officialPlatformURL(for: $0))
            }
            searchDiagnosticSummary = SearchDiagnosticSummary.make(
                evidenceResults: platformStatuses.map {
                    PlatformEvidenceResult(platform: $0.platform, status: $0, listings: [])
                },
                recommendations: []
            )
            restoreLatestSuccessfulResultsIfAvailable()
            return
```

After `let evidenceResults = await searchProvider.search(request: liveRequest)`, keep `platformStatuses = evidenceResults.map(\.status)` and add no new logic there.

In the no-listings guard, replace:

```swift
            status = formatNoAPIListingsStatus(evidenceResults)
            searchProgressPhase = .completed
            return
```

with:

```swift
            status = formatNoAPIListingsStatus(evidenceResults)
            searchDiagnosticSummary = SearchDiagnosticSummary.make(evidenceResults: evidenceResults, recommendations: [])
            searchProgressPhase = .completed
            restoreLatestSuccessfulResultsIfAvailable()
            return
```

After recommendations are computed, replace the final success block:

```swift
        results = recommendations
        selectedId = recommendations.first?.id ?? ""
        status = formatSearchCompletionStatus(request: liveRequest, resultCount: recommendations.count)
        searchProgressPhase = .completed
```

with:

```swift
        results = recommendations
        selectedId = recommendations.first?.id ?? ""
        recordSuccessfulResults(recommendations)
        searchDiagnosticSummary = SearchDiagnosticSummary.make(evidenceResults: evidenceResults, recommendations: recommendations)
        status = formatSearchCompletionStatus(request: liveRequest, resultCount: recommendations.count)
        searchProgressPhase = .completed
```

At the end of `togglePlatform(_:)`, `applyDates(pickup:returnDate:)`, `updateOriginInput(_:)`, `selectOriginSuggestion(_:)`, and `refreshCurrentLocation()` after request mutations, call:

```swift
        refreshPreflightIssues()
```

- [ ] **Step 5: Run focused ViewModel tests**

Run:

```bash
swift test --filter SearchViewModel
```

Expected: all `SearchViewModel` tests pass.

- [ ] **Step 6: Commit**

Run:

```bash
git add Sources/CarRentalOptimizer/SearchViewModel.swift Tests/CarRentalOptimizerTests/SearchViewModelTests.swift
git commit -m "Retain trusted search results after failures"
```

## Task 3: Add Search Diagnostics and Recovery UI

**Files:**
- Modify: `Sources/CarRentalOptimizer/ResultPanelView.swift`
- Modify: `Sources/CarRentalOptimizer/SearchPanelView.swift`

- [ ] **Step 1: Add preflight issue rendering in the search panel**

In `SearchPanelView.searchControls`, after the `QuerySection(icon: "link", title: "平台") { ... }` block, insert:

```swift
            if !viewModel.preflightIssues.isEmpty {
                PreflightIssueList(issues: viewModel.preflightIssues)
            }
```

In `compareButton`, replace:

```swift
        .disabled(viewModel.isSearching)
```

with:

```swift
        .disabled(viewModel.isSearching || viewModel.hasBlockingPreflightIssues)
```

In the top-level `VStack` modifiers, add:

```swift
            .onChange(of: viewModel.request) { _, _ in
                viewModel.refreshPreflightIssues()
            }
```

Add this private view above `PlatformToggleButton`:

```swift
private struct PreflightIssueList: View {
    let issues: [SearchPreflightIssue]

    var body: some View {
        SurfaceBox(fill: WorkbenchStyle.surface, padding: 10) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(issues) { issue in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: issue.severity == .blocking ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(issue.severity == .blocking ? WorkbenchStyle.red : WorkbenchStyle.orange)
                            .frame(width: 16)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(issue.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(WorkbenchStyle.ink)
                            Text(issue.message)
                                .font(.caption2)
                                .foregroundStyle(WorkbenchStyle.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 2: Add diagnostic and stale banners to result panel**

In `ResultPanelView`, replace the non-empty results branch:

```swift
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(Array(viewModel.displayedResults.enumerated()), id: \.element.id) { index, result in
                                ResultRowView(
                                    rank: index + 1,
                                    recommendation: result,
                                    isSelected: viewModel.selectedId == result.id
                                ) {
                                    viewModel.selectResult(result.id)
                                    pendingMonitorRecommendation = result
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    viewModel.selectResult(result.id)
                                }
                            }
                        }
                        .padding(16)
                    }
                }
```

with:

```swift
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if let notice = viewModel.retainedResultsNotice {
                                RetainedResultsNoticeView(notice: notice)
                            }

                            SearchDiagnosticSummaryView(summary: viewModel.searchDiagnosticSummary)

                            LazyVStack(spacing: 10) {
                                ForEach(Array(viewModel.displayedResults.enumerated()), id: \.element.id) { index, result in
                                    ResultRowView(
                                        rank: index + 1,
                                        recommendation: result,
                                        isSelected: viewModel.selectedId == result.id
                                    ) {
                                        viewModel.selectResult(result.id)
                                        pendingMonitorRecommendation = result
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        viewModel.selectResult(result.id)
                                    }
                                }
                            }
                        }
                        .padding(16)
                    }
                }
```

Add these private views near `LoadingResultsView`:

```swift
private struct RetainedResultsNoticeView: View {
    let notice: RetainedResultsNotice

    var body: some View {
        SurfaceBox(fill: WorkbenchStyle.orange.opacity(0.08), stroke: WorkbenchStyle.orange.opacity(0.22), padding: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "clock.badge.exclamationmark")
                    .foregroundStyle(WorkbenchStyle.orange)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 3) {
                    Text(notice.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WorkbenchStyle.ink)
                    Text("\(notice.message) 上次成功：\(DateFormatter.localizedString(from: notice.lastSuccessfulSearchAt, dateStyle: .short, timeStyle: .short))")
                        .font(.caption2)
                        .foregroundStyle(WorkbenchStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct SearchDiagnosticSummaryView: View {
    let summary: SearchDiagnosticSummary

    var body: some View {
        SurfaceBox(fill: WorkbenchStyle.surface, padding: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    InlineMetric(title: "已查平台", value: "\(summary.queriedPlatforms.count)")
                    InlineMetric(title: "成功平台", value: "\(summary.successfulPlatforms.count)")
                    InlineMetric(title: "原始报价", value: "\(summary.listingCount)")
                    InlineMetric(title: "可见结果", value: "\(summary.visibleResultCount)")
                }
                Text(summary.routeEstimateStatus)
                    .font(.caption2)
                    .foregroundStyle(WorkbenchStyle.muted)
            }
        }
    }
}
```

- [ ] **Step 3: Show recovery suggestions in empty/error state**

Update `EmptyResultsView` to accept recovery statuses:

```swift
private struct EmptyResultsView: View {
    let statuses: [PlatformEvidenceStatus]
    let phase: SearchProgressPhase
    let onRetry: () -> Void
```

No signature change is needed because `statuses` already exists. Inside the view, after the platform summary `SurfaceBox`, insert:

```swift
            RecoverySuggestionList(statuses: statuses)
                .frame(maxWidth: 460)
```

Add this private view near `PlatformSummaryRow`:

```swift
private struct RecoverySuggestionList: View {
    let statuses: [PlatformEvidenceStatus]

    private var actions: [SearchRecoveryAction] {
        var seen = Set<String>()
        return statuses.flatMap(SearchRecoveryAction.actions).filter { seen.insert($0.id).inserted }
    }

    var body: some View {
        if !actions.isEmpty {
            SurfaceBox(fill: WorkbenchStyle.surface, padding: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    MonitorSectionLikeTitle(icon: "wrench.and.screwdriver.fill", title: "建议操作")
                    ForEach(actions) { action in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: action.systemImage)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(WorkbenchStyle.accent)
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(action.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(WorkbenchStyle.ink)
                                Text(action.message)
                                    .font(.caption2)
                                    .foregroundStyle(WorkbenchStyle.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct MonitorSectionLikeTitle: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(WorkbenchStyle.accent)
                .frame(width: 18)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WorkbenchStyle.ink)
            Spacer()
        }
    }
}
```

- [ ] **Step 4: Run build-focused verification**

Run:

```bash
swift test --filter SearchViewModel
swift build
```

Expected: `SearchViewModel` tests pass and the SwiftUI app target builds.

- [ ] **Step 5: Commit**

Run:

```bash
git add Sources/CarRentalOptimizer/SearchPanelView.swift Sources/CarRentalOptimizer/ResultPanelView.swift
git commit -m "Show trusted search diagnostics"
```

## Task 4: Use Unified Quote Credibility in Results and Details

**Files:**
- Modify: `Sources/CarRentalOptimizer/ResultPanelView.swift`
- Modify: `Sources/CarRentalOptimizer/DetailPanelView.swift`
- Modify: `Tests/CarRentalOptimizerTests/SearchTrustPresentationTests.swift`

- [ ] **Step 1: Extend credibility test for low completeness**

Add this test to `SearchTrustPresentationTests`:

```swift
    @Test("Quote credibility flags low completeness without warnings")
    func quoteCredibilityFlagsLowCompletenessWithoutWarnings() {
        let credibility = QuoteCredibility.make(for: makeRecommendation(dataCompleteness: 0.72, warnings: []))

        #expect(credibility.level == .reviewRecommended)
        #expect(credibility.title == "报价完整度偏低")
        #expect(credibility.message.contains("平台返回字段不够完整"))
    }
```

- [ ] **Step 2: Run focused presentation tests**

Run:

```bash
swift test --filter SearchTrustPresentation
```

Expected: tests pass because Task 1 already includes low-completeness handling.

- [ ] **Step 3: Replace ad hoc partial price UI in result rows**

In `ResultRowView`, replace:

```swift
                if recommendation.warnings.contains(.partialPrice) {
                    Label("部分价格需打开平台复核", systemImage: "exclamationmark.circle.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(WorkbenchStyle.orange)
                }
```

with:

```swift
                QuoteCredibilityBadge(credibility: QuoteCredibility.make(for: recommendation))
```

Add this private view near `InlineMetric`:

```swift
private struct QuoteCredibilityBadge: View {
    let credibility: QuoteCredibility

    var body: some View {
        Label(credibility.title, systemImage: credibility.systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .help(credibility.message)
    }

    private var color: Color {
        switch credibility.level {
        case .complete:
            return WorkbenchStyle.green
        case .reviewRecommended:
            return WorkbenchStyle.orange
        case .blocked:
            return WorkbenchStyle.red
        }
    }
}
```

- [ ] **Step 4: Replace ad hoc partial price UI in details**

In `RecommendationDetailView`, replace the partial price `Label` inside the cost breakdown:

```swift
                            if recommendation.warnings.contains(.partialPrice) {
                                Label("平台未完整返回服务费、保险或异店还车费，建议下单前复核。", systemImage: "exclamationmark.circle.fill")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(WorkbenchStyle.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.top, 6)
                            }
```

with:

```swift
                            QuoteCredibilityDetail(credibility: QuoteCredibility.make(for: recommendation))
                                .padding(.top, 6)
```

Add this private view near `PlatformQuoteComparisonView`:

```swift
private struct QuoteCredibilityDetail: View {
    let credibility: QuoteCredibility

    var body: some View {
        Label(credibility.message, systemImage: credibility.systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var color: Color {
        switch credibility.level {
        case .complete:
            return WorkbenchStyle.green
        case .reviewRecommended:
            return WorkbenchStyle.orange
        case .blocked:
            return WorkbenchStyle.red
        }
    }
}
```

In `PlatformQuoteRowView`, add this line under `Text(quote.listing.vehicleName)`:

```swift
                Text(QuoteCredibility.make(for: quote).title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WorkbenchStyle.orange)
                    .lineLimit(1)
```

If the title is `"完整报价"`, keep it visible for consistency across comparison rows.

- [ ] **Step 5: Run verification**

Run:

```bash
swift test --filter SearchTrustPresentation
swift build
```

Expected: presentation tests pass and UI builds.

- [ ] **Step 6: Commit**

Run:

```bash
git add Sources/CarRentalOptimizer/ResultPanelView.swift Sources/CarRentalOptimizer/DetailPanelView.swift Tests/CarRentalOptimizerTests/SearchTrustPresentationTests.swift
git commit -m "Unify quote credibility labels"
```

## Task 5: Polish Status Text and Documentation

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`
- Modify: `Sources/CarRentalOptimizer/ResultPanelView.swift`

- [ ] **Step 1: Tighten result panel subtitle for stale state**

In `ResultPanelView.panelSubtitle`, replace:

```swift
        if viewModel.results.isEmpty {
            return "等待真实报价"
        }
        return "\(viewModel.results.count) 个真实候选，同车型取优后按总成本升序"
```

with:

```swift
        if viewModel.results.isEmpty {
            return "等待真实报价"
        }
        if viewModel.isShowingStaleResults {
            return "\(viewModel.results.count) 个上次成功候选，等待本次查询恢复"
        }
        return "\(viewModel.results.count) 个真实候选，同车型取优后按总成本升序"
```

- [ ] **Step 2: Update README capability list**

In `README.md`, under `### 当前能力`, add these bullets after the existing candidate/result bullets:

```markdown
- 查询结果会显示本次搜索诊断摘要：已查平台、成功平台、原始报价数、可见结果数和路线估算状态。
- 平台失败、登录失效、验证码或解析失败时，会给出可执行的恢复建议；如果上次搜索成功，界面会保留上次候选并明确标记为历史结果。
- 候选方案和详情页使用统一的报价可信度标签，说明完整报价、部分费用待复核、路线估算缺失或跨城/异店风险。
```

- [ ] **Step 3: Update changelog**

Add this section at the top of `CHANGELOG.md`, below the main title:

```markdown
## Unreleased

- 搜索主流程新增查询前条件提示、搜索诊断摘要和平台失败恢复建议。
- 新搜索失败时会保留上次成功候选，并明确标记为历史结果，避免平台临时异常时清空上下文。
- 候选列表、推荐明细和平台对比统一展示报价可信度标签。
```

- [ ] **Step 4: Run documentation and build checks**

Run:

```bash
rg -n "上次成功|搜索诊断|报价可信度|恢复建议" README.md CHANGELOG.md Sources/CarRentalOptimizer
swift build
```

Expected: `rg` finds the new wording in docs and app source, and `swift build` succeeds.

- [ ] **Step 5: Commit**

Run:

```bash
git add README.md CHANGELOG.md Sources/CarRentalOptimizer/ResultPanelView.swift
git commit -m "Document trusted search workflow"
```

## Task 6: Full Verification

**Files:**
- All changed files

- [ ] **Step 1: Run focused tests**

Run:

```bash
swift test --filter SearchTrustPresentation
swift test --filter SearchViewModel
```

Expected: both focused test suites pass.

- [ ] **Step 2: Run the full Swift test suite**

Run:

```bash
swift test
```

Expected: all tests pass.

- [ ] **Step 3: Build the app**

Run:

```bash
swift build
```

Expected: the executable target builds successfully.

- [ ] **Step 4: Inspect source diff**

Run:

```bash
git status --short
git diff --stat
```

Expected: only Phase 1 files are modified, and no generated or unrelated files are present.

- [ ] **Step 5: Manual app smoke check**

Run:

```bash
swift run CarRentalOptimizer
```

Expected: app launches. In the UI, verify:

- Search panel shows preflight warnings after request edits.
- Successful search shows diagnostic summary.
- Failed search after a success keeps previous results with a stale-result banner.
- Empty/error state shows recovery suggestions.
- Result and detail panels show quote credibility labels.

- [ ] **Step 6: Commit any final fixes**

If the smoke check requires source or documentation changes, run:

```bash
git add Sources Tests README.md CHANGELOG.md
git commit -m "Finish trusted search verification fixes"
```

Expected: no commit is created when there are no fixes.
