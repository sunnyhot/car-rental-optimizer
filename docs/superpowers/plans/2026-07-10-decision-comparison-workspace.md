# Decision Comparison Workspace Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users select 2–4 recommendations and compare price, route, vehicle information, and credibility in an in-place matrix without leaving the current search context.

**Architecture:** Add a dedicated comparison view model that owns selection and per-candidate vehicle-insight state, plus a pure presentation builder that creates matrix sections. Keep search ownership in `SearchViewModel`; connect the models through a monotonic search generation and render the matrix in the Route Blueprint shell.

**Tech Stack:** Swift 6, SwiftUI, Swift Concurrency, AppKit `NSWorkspace`, Swift Testing, existing `Recommendation`, `QuoteCredibility`, and `VehicleInsight` types.

## Global Constraints

- Execute after `2026-07-10-route-blueprint-shell.md`.
- Compare only candidates from one search generation; a valid new search clears the comparison.
- Support a minimum of 2 and maximum of 4 selected candidates.
- Filtering or sorting must not delete selected candidates.
- Default to all comparison rows and provide a “只看差异” toggle.
- Do not add a combined winner score; mark cost, distance, route, and completeness advantages independently.
- Treat missing configuration as “未确认”, never as “不支持”.
- Load vehicle insight only for selected candidates and isolate fallback state by column.
- Do not change platform APIs, ranking, price calculation, login cookies, monitor storage, or release behavior.
- Do not add third-party dependencies.
- Run `swift build` and `swift test` before completion.

---

## Scope Check

This is plan 2 of 4 and produces a complete, independently usable comparison feature. Plans 3 and 4 only restyle the surrounding search, monitor, and sheet surfaces.

## File Structure

- `Sources/CarRentalOptimizer/SearchViewModel.swift`: publishes a valid-search generation and accepts a shared vehicle-insight service in its live initializer.
- `Sources/CarRentalOptimizer/ComparisonWorkspaceViewModel.swift`: owns 0–4 selections, matrix mode, difference filtering, and insight tasks.
- `Sources/CarRentalOptimizer/ComparisonPresentation.swift`: pure matrix section/row/cell types and best-value/difference logic.
- `Sources/CarRentalOptimizer/ComparisonMatrixView.swift`: renders the in-place matrix and per-candidate actions.
- `Sources/CarRentalOptimizer/ComparisonSelectionBar.swift`: renders selected candidate summaries and the entry action.
- `Sources/CarRentalOptimizer/ContentView.swift`: creates one `VehicleInsightService` shared by search and comparison models.
- `Sources/CarRentalOptimizer/AppShellView.swift`: switches the middle/detail region into comparison mode and resets on a new search generation.
- `Sources/CarRentalOptimizer/ResultPanelView.swift`: exposes candidate checkboxes and the selection bar.
- `Tests/CarRentalOptimizerTests/ComparisonTestFixtures.swift`: shared comparison fixtures and insight stub.
- `Tests/CarRentalOptimizerTests/ComparisonWorkspaceViewModelTests.swift`: selection and async state behavior.
- `Tests/CarRentalOptimizerTests/ComparisonPresentationTests.swift`: matrix contents, advantage, and differences.
- `Tests/CarRentalOptimizerTests/SearchViewModelTests.swift`: valid-search generation behavior.
- `Tests/CarRentalOptimizerTests/UIEffectsSourceTests.swift`: comparison UI adoption contracts.

### Task 1: Search Generation and Injectable Insight Service

**Files:**
- Modify: `Sources/CarRentalOptimizer/SearchViewModel.swift`
- Modify: `Tests/CarRentalOptimizerTests/SearchViewModelTests.swift`

**Interfaces:**
- Consumes: `VehicleInsightProviding`, existing `performSearch(retryingFailedPlatformsOnly:)`.
- Produces:
  - `SearchViewModel.searchGeneration: Int`
  - `SearchViewModel.init(vehicleInsightService:)`
  - `SearchViewModel.isSelectedResultHidden: Bool`
  - A live initializer that remains source-compatible with `SearchViewModel()` and can share a service in Task 4.

- [ ] **Step 1: Add valid-search generation tests**

Append to `SearchViewModelTests.swift`:

```swift
@Test("A valid search advances the search generation")
func validSearchAdvancesGeneration() async {
    let viewModel = SearchViewModel(
        searchProvider: StubRentalSearchProvider(results: []),
        geocoder: CurrentRequestGeocoder(point: AppDefaults.searchRequest.origin),
        mapService: EstimatedMapService()
    )
    let initialGeneration = viewModel.searchGeneration

    await viewModel.runSearch()

    #expect(viewModel.searchGeneration == initialGeneration + 1)
}

@Test("A blocked search does not advance the search generation")
func blockedSearchDoesNotAdvanceGeneration() async {
    let viewModel = SearchViewModel(
        searchProvider: StubRentalSearchProvider(results: []),
        geocoder: CurrentRequestGeocoder(point: AppDefaults.searchRequest.origin),
        mapService: EstimatedMapService()
    )
    viewModel.request.platforms = []

    await viewModel.runSearch()

    #expect(viewModel.searchGeneration == 0)
}

@Test("A comparison choice can remain current while filters hide its card")
func hiddenComparisonChoiceRemainsCurrent() {
    let viewModel = SearchViewModel(
        searchProvider: StubRentalSearchProvider(results: []),
        geocoder: CurrentRequestGeocoder(point: AppDefaults.searchRequest.origin),
        mapService: EstimatedMapService()
    )
    let visible = makeTestRecommendation(id: "visible", rentalTotal: 900, bestTotal: 930, distanceKm: 1, dataCompleteness: 0.98, platform: .ehi)
    let hidden = makeTestRecommendation(id: "hidden", rentalTotal: 950, bestTotal: 980, distanceKm: 2, dataCompleteness: 0.98, platform: .carInc)
    viewModel.results = [visible, hidden]
    viewModel.recommendationFilter.platform = .ehi

    viewModel.selectResult(hidden.id)

    #expect(viewModel.selected?.id == hidden.id)
    #expect(viewModel.isSelectedResultHidden)
}
```

- [ ] **Step 2: Run the focused tests and verify they fail**

Run:

```bash
swift test --filter SearchViewModelTests
```

Expected: compilation fails because `searchGeneration` is undefined.

- [ ] **Step 3: Publish the generation and make the live service injectable**

In `SearchViewModel`, add with the other published state:

```swift
@Published private(set) var searchGeneration = 0
```

Replace the zero-argument live initializer with:

```swift
init(vehicleInsightService: VehicleInsightProviding = VehicleInsightService()) {
    self.searchProvider = LiveRentalSearchService()
    self.geocoder = AppleAddressGeocoder()
    self.mapService = AppleMapService()
    self.currentLocationProvider = AppleCurrentLocationProvider()
    self.addressSuggestionProvider = AppleAddressSuggestionProvider()
    self.railStationSuggestionProvider = AppleRailStationSuggestionProvider()
    self.vehicleSuggestionStore = VehicleSuggestionStore()
    self.vehicleInsightService = vehicleInsightService
    self.initialLocationRetryDelayNanoseconds = defaultInitialLocationRetryDelayNanoseconds
    self.resolvedOriginLabel = AppDefaults.searchRequest.originLabel
    self.now = Date.init
}
```

In `performSearch`, immediately after the blocking-preflight guard and before clearing filters, add:

```swift
searchGeneration += 1
```

This advances for full searches and retry searches only after validation succeeds.

Replace the `selected` computed property and add the hidden-selection flag:

```swift
var selected: Recommendation? {
    results.first { $0.id == selectedId } ?? displayedResults.first
}

var isSelectedResultHidden: Bool {
    guard !selectedId.isEmpty, results.contains(where: { $0.id == selectedId }) else { return false }
    return !displayedResults.contains { $0.id == selectedId }
}
```

- [ ] **Step 4: Run the search tests and commit**

Run:

```bash
swift test --filter SearchViewModelTests
```

Expected: SearchViewModel tests and target compilation pass.

```bash
git add Sources/CarRentalOptimizer/SearchViewModel.swift Tests/CarRentalOptimizerTests/SearchViewModelTests.swift
git commit -m "feat: publish valid search generation"
```

### Task 2: Comparison Selection and Insight State

**Files:**
- Create: `Sources/CarRentalOptimizer/ComparisonWorkspaceViewModel.swift`
- Create: `Tests/CarRentalOptimizerTests/ComparisonTestFixtures.swift`
- Create: `Tests/CarRentalOptimizerTests/ComparisonWorkspaceViewModelTests.swift`

**Interfaces:**
- Consumes: `Recommendation`, `VehicleInsightProviding`, `VehicleInsight.origin`.
- Produces:
  - `enum ComparisonInsightState: Equatable`
  - `ComparisonInsightState.insight: VehicleInsight`
  - `ComparisonWorkspaceViewModel.maximumSelectionCount == 4`
  - `selectedRecommendations`, `selectedIDs`, `isComparing`, `onlyShowsDifferences`, `insightStates`
  - `toggle(_:)`, `remove(id:)`, `beginComparison()`, `exitComparison()`, `resetForNewSearch()`, `reconcile(with:)`, `retryInsight(for:)`.

- [ ] **Step 1: Create shared comparison test fixtures**

Create `Tests/CarRentalOptimizerTests/ComparisonTestFixtures.swift`:

```swift
import CarRentalDomain
import Foundation
@testable import CarRentalOptimizer

func makeComparisonRecommendation(
    id: String,
    platform: PlatformId = .ehi,
    vehicleName: String,
    rentalTotal: Double,
    bestTotal: Double,
    distanceKm: Double,
    dataCompleteness: Double = 0.98,
    warnings: [ResultWarning] = []
) -> Recommendation {
    let store = Store(
        id: "store-\(id)",
        platform: platform,
        name: "\(vehicleName)门店",
        city: "北京",
        address: "北京市测试路\(id)号",
        location: GeoPoint(lat: 39.9, lng: 116.4),
        distanceKm: distanceKm,
        hours: "08:00-20:00"
    )
    let listing = RentalListing(
        id: id,
        platform: platform,
        store: store,
        vehicleName: vehicleName,
        vehicleClass: "SUV 5座",
        basePrice: rentalTotal,
        platformFees: 0,
        insuranceFees: 0,
        oneWayFee: 0,
        sourceUrl: "https://example.com/\(id)",
        dataCompleteness: dataCompleteness,
        warnings: warnings
    )
    let taxi = RouteEstimate(mode: .taxi, cost: bestTotal - rentalTotal, durationMinutes: 15, distanceKm: distanceKm, summary: "打车")
    let transit = RouteEstimate(mode: .transit, cost: 6, durationMinutes: 25, distanceKm: distanceKm, summary: "地铁")
    return Recommendation(
        listing: listing,
        match: VehicleMatch(kind: .exact, score: 1, label: "精确匹配"),
        taxiRoute: taxi,
        transitRoute: transit,
        rentalTotal: rentalTotal,
        taxiTotal: bestTotal,
        transitTotal: rentalTotal + 6,
        bestTotal: bestTotal,
        bestRouteMode: .taxi,
        warnings: warnings
    )
}

final class StubComparisonInsightService: VehicleInsightProviding {
    var returnedOrigin: VehicleInsightOrigin = .network
    var delayNanoseconds: UInt64 = 0

    func localInsight(for listing: RentalListing) -> VehicleInsight {
        VehicleInsightLocalInferencer.localInsight(for: listing)
    }

    func insight(for listing: RentalListing) async -> VehicleInsight {
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        var insight = localInsight(for: listing)
        insight.origin = returnedOrigin
        insight.sourceName = returnedOrigin == .network ? "测试车型库" : "本地推断"
        return insight
    }
}
```

- [ ] **Step 2: Write selection and async state tests**

Create `Tests/CarRentalOptimizerTests/ComparisonWorkspaceViewModelTests.swift`:

```swift
import Testing
@testable import CarRentalOptimizer

@MainActor
@Suite("Comparison workspace")
struct ComparisonWorkspaceViewModelTests {
    @Test("Comparison requires two candidates and caps selection at four")
    func selectionLimits() {
        let model = ComparisonWorkspaceViewModel(vehicleInsightService: StubComparisonInsightService())
        let candidates = (1...5).map {
            makeComparisonRecommendation(id: "r\($0)", vehicleName: "车型\($0)", rentalTotal: Double(900 + $0), bestTotal: Double(930 + $0), distanceKm: Double($0))
        }

        model.toggle(candidates[0])
        model.beginComparison()
        #expect(!model.isComparing)

        candidates.forEach(model.toggle)
        #expect(model.selectedRecommendations.count == 4)
        #expect(model.selectedIDs == ["r1", "r2", "r3", "r4"])

        model.beginComparison()
        #expect(model.isComparing)
    }

    @Test("Removing down to one candidate exits comparison")
    func removalExitsComparison() {
        let model = ComparisonWorkspaceViewModel(vehicleInsightService: StubComparisonInsightService())
        let first = makeComparisonRecommendation(id: "a", vehicleName: "A", rentalTotal: 900, bestTotal: 930, distanceKm: 1)
        let second = makeComparisonRecommendation(id: "b", vehicleName: "B", rentalTotal: 950, bestTotal: 980, distanceKm: 2)
        model.toggle(first)
        model.toggle(second)
        model.beginComparison()

        model.remove(id: second.id)

        #expect(!model.isComparing)
        #expect(model.selectedIDs == [first.id])
    }

    @Test("Reconcile refreshes values without dropping filter-hidden candidates")
    func reconcileUsesFullResults() {
        let model = ComparisonWorkspaceViewModel(vehicleInsightService: StubComparisonInsightService())
        let old = makeComparisonRecommendation(id: "same", vehicleName: "车型", rentalTotal: 900, bestTotal: 930, distanceKm: 1)
        let refreshed = makeComparisonRecommendation(id: "same", vehicleName: "车型", rentalTotal: 850, bestTotal: 880, distanceKm: 1)
        model.toggle(old)

        model.reconcile(with: [refreshed])

        #expect(model.selectedRecommendations.first?.bestTotal == 880)
    }

    @Test("Local fallback is isolated to the selected candidate")
    func localFallbackState() async {
        let service = StubComparisonInsightService()
        service.returnedOrigin = .localInference
        let model = ComparisonWorkspaceViewModel(vehicleInsightService: service)
        let candidate = makeComparisonRecommendation(id: "fallback", vehicleName: "车型", rentalTotal: 900, bestTotal: 930, distanceKm: 1)

        model.toggle(candidate)
        try? await Task.sleep(nanoseconds: 10_000_000)

        guard case .fallback(let insight) = model.insightStates[candidate.id] else {
            Issue.record("Expected a per-column fallback state")
            return
        }
        #expect(insight.origin == .localInference)
    }

    @Test("New search reset clears selection and cancels comparison")
    func newSearchReset() {
        let model = ComparisonWorkspaceViewModel(vehicleInsightService: StubComparisonInsightService())
        model.toggle(makeComparisonRecommendation(id: "a", vehicleName: "A", rentalTotal: 900, bestTotal: 930, distanceKm: 1))

        model.resetForNewSearch()

        #expect(model.selectedRecommendations.isEmpty)
        #expect(model.insightStates.isEmpty)
        #expect(!model.isComparing)
        #expect(!model.onlyShowsDifferences)
    }

    @Test("A delayed insight response cannot restore a removed column")
    func removedCandidateIgnoresDelayedInsight() async {
        let service = StubComparisonInsightService()
        service.delayNanoseconds = 50_000_000
        let model = ComparisonWorkspaceViewModel(vehicleInsightService: service)
        let candidate = makeComparisonRecommendation(id: "delayed", vehicleName: "延迟车型", rentalTotal: 900, bestTotal: 930, distanceKm: 1)

        model.toggle(candidate)
        model.remove(id: candidate.id)
        try? await Task.sleep(nanoseconds: 80_000_000)

        #expect(model.insightStates[candidate.id] == nil)
        #expect(model.selectedRecommendations.isEmpty)
    }
}
```

- [ ] **Step 3: Run the tests and verify they fail**

Run:

```bash
swift test --filter ComparisonWorkspace
```

Expected: compilation fails because the comparison types are undefined.

- [ ] **Step 4: Implement the comparison view model**

Create `Sources/CarRentalOptimizer/ComparisonWorkspaceViewModel.swift`:

```swift
import CarRentalDomain
import Foundation
import SwiftUI

enum ComparisonInsightState: Equatable {
    case loading(VehicleInsight)
    case loaded(VehicleInsight)
    case fallback(VehicleInsight)

    var insight: VehicleInsight {
        switch self {
        case .loading(let insight), .loaded(let insight), .fallback(let insight):
            return insight
        }
    }
}

@MainActor
final class ComparisonWorkspaceViewModel: ObservableObject {
    static let maximumSelectionCount = 4

    @Published private(set) var selectedRecommendations: [Recommendation] = []
    @Published private(set) var isComparing = false
    @Published var onlyShowsDifferences = false
    @Published private(set) var insightStates: [String: ComparisonInsightState] = [:]

    private let vehicleInsightService: VehicleInsightProviding
    private var insightTasks: [String: Task<Void, Never>] = [:]

    init(vehicleInsightService: VehicleInsightProviding = VehicleInsightService()) {
        self.vehicleInsightService = vehicleInsightService
    }

    var selectedIDs: [String] {
        selectedRecommendations.map(\.id)
    }

    var canBeginComparison: Bool {
        selectedRecommendations.count >= 2
    }

    var hasReachedMaximum: Bool {
        selectedRecommendations.count >= Self.maximumSelectionCount
    }

    func isSelected(_ id: String) -> Bool {
        selectedRecommendations.contains { $0.id == id }
    }

    func canSelect(_ id: String) -> Bool {
        isSelected(id) || !hasReachedMaximum
    }

    func toggle(_ recommendation: Recommendation) {
        if isSelected(recommendation.id) {
            remove(id: recommendation.id)
            return
        }
        guard !hasReachedMaximum else { return }
        selectedRecommendations.append(recommendation)
        loadInsight(for: recommendation)
    }

    func remove(id: String) {
        selectedRecommendations.removeAll { $0.id == id }
        insightTasks.removeValue(forKey: id)?.cancel()
        insightStates.removeValue(forKey: id)
        if selectedRecommendations.count < 2 {
            isComparing = false
        }
    }

    func beginComparison() {
        guard canBeginComparison else { return }
        isComparing = true
    }

    func exitComparison() {
        isComparing = false
    }

    func resetForNewSearch() {
        insightTasks.values.forEach { $0.cancel() }
        insightTasks.removeAll()
        selectedRecommendations.removeAll()
        insightStates.removeAll()
        isComparing = false
        onlyShowsDifferences = false
    }

    func reconcile(with results: [Recommendation]) {
        let byID = Dictionary(uniqueKeysWithValues: results.map { ($0.id, $0) })
        let retained = selectedRecommendations.compactMap { byID[$0.id] }
        let removedIDs = Set(selectedIDs).subtracting(retained.map(\.id))
        removedIDs.forEach { id in
            insightTasks.removeValue(forKey: id)?.cancel()
            insightStates.removeValue(forKey: id)
        }
        selectedRecommendations = retained
        if selectedRecommendations.count < 2 {
            isComparing = false
        }
    }

    func retryInsight(for recommendation: Recommendation) {
        guard isSelected(recommendation.id) else { return }
        insightTasks.removeValue(forKey: recommendation.id)?.cancel()
        loadInsight(for: recommendation)
    }

    private func loadInsight(for recommendation: Recommendation) {
        let local = vehicleInsightService.localInsight(for: recommendation.listing)
        insightStates[recommendation.id] = .loading(local)
        let service = vehicleInsightService
        insightTasks[recommendation.id] = Task { [weak self, recommendation, service] in
            let insight = await service.insight(for: recommendation.listing)
            guard !Task.isCancelled, let self, self.isSelected(recommendation.id) else { return }
            self.insightStates[recommendation.id] = insight.origin == .network
                ? .loaded(insight)
                : .fallback(insight)
            self.insightTasks.removeValue(forKey: recommendation.id)
        }
    }
}
```

- [ ] **Step 5: Run focused tests and commit comparison state**

Run:

```bash
swift test --filter ComparisonWorkspace
swift test --filter SearchViewModelTests
```

Expected: both suites pass.

```bash
git add Sources/CarRentalOptimizer/ComparisonWorkspaceViewModel.swift Tests/CarRentalOptimizerTests/ComparisonTestFixtures.swift Tests/CarRentalOptimizerTests/ComparisonWorkspaceViewModelTests.swift
git commit -m "feat: add comparison selection state"
```

### Task 3: Pure Comparison Presentation

**Files:**
- Create: `Sources/CarRentalOptimizer/ComparisonPresentation.swift`
- Modify: `Sources/CarRentalOptimizer/VehicleInsights.swift`
- Create: `Tests/CarRentalOptimizerTests/ComparisonPresentationTests.swift`

**Interfaces:**
- Consumes: ordered `[Recommendation]` and `[String: ComparisonInsightState]`.
- Produces:
  - `ComparisonSectionID`, `ComparisonCellTone`, `ComparisonCell`, `ComparisonRow`, `ComparisonSection`
  - `ComparisonPresentation.sections(candidates:insightStates:onlyDifferences:)`
  - Stable section order: summary, cost, route, vehicle, trust.

- [ ] **Step 1: Write presentation behavior tests**

Create `Tests/CarRentalOptimizerTests/ComparisonPresentationTests.swift`:

```swift
import Testing
@testable import CarRentalOptimizer

@Suite("Comparison presentation")
struct ComparisonPresentationTests {
    @Test("Matrix uses the approved section order and preserves the core total row")
    func approvedSectionOrder() {
        let candidates = [
            makeComparisonRecommendation(id: "a", vehicleName: "宋 Pro", rentalTotal: 1200, bestTotal: 1286, distanceKm: 1.2),
            makeComparisonRecommendation(id: "b", vehicleName: "途观 L", rentalTotal: 1350, bestTotal: 1438, distanceKm: 0.8),
        ]

        let sections = ComparisonPresentation.sections(candidates: candidates, insightStates: [:], onlyDifferences: false)

        #expect(sections.map(\.id) == [.summary, .cost, .route, .vehicle, .trust])
        #expect(sections.flatMap(\.rows).contains { $0.id == "best-total" && $0.isCore })
    }

    @Test("Cost distance and completeness advantages are independent")
    func independentAdvantages() {
        let candidates = [
            makeComparisonRecommendation(id: "cheap", vehicleName: "便宜车", rentalTotal: 900, bestTotal: 930, distanceKm: 3, dataCompleteness: 0.80),
            makeComparisonRecommendation(id: "near", vehicleName: "近门店", rentalTotal: 950, bestTotal: 980, distanceKm: 1, dataCompleteness: 0.99),
        ]

        let rows = ComparisonPresentation.sections(candidates: candidates, insightStates: [:], onlyDifferences: false).flatMap(\.rows)

        #expect(rows.first { $0.id == "best-total" }?.cells.first { $0.candidateID == "cheap" }?.tone == .advantage)
        #expect(rows.first { $0.id == "store-distance" }?.cells.first { $0.candidateID == "near" }?.tone == .advantage)
        #expect(rows.first { $0.id == "completeness" }?.cells.first { $0.candidateID == "near" }?.tone == .advantage)
    }

    @Test("Difference mode removes equal non-core rows and keeps total")
    func differenceMode() {
        let candidates = [
            makeComparisonRecommendation(id: "a", vehicleName: "A", rentalTotal: 900, bestTotal: 930, distanceKm: 1),
            makeComparisonRecommendation(id: "b", vehicleName: "B", rentalTotal: 900, bestTotal: 980, distanceKm: 1),
        ]

        let rows = ComparisonPresentation.sections(candidates: candidates, insightStates: [:], onlyDifferences: true).flatMap(\.rows)

        #expect(rows.contains { $0.id == "best-total" })
        #expect(!rows.contains { $0.id == "store-distance" })
    }

    @Test("Missing configuration is presented as unconfirmed")
    func missingConfigurationIsUnconfirmed() {
        let candidate = makeComparisonRecommendation(id: "a", vehicleName: "A", rentalTotal: 900, bestTotal: 930, distanceKm: 1)

        let rows = ComparisonPresentation.sections(candidates: [candidate], insightStates: [:], onlyDifferences: false).flatMap(\.rows)

        #expect(rows.first { $0.id == "vehicle-insight" }?.cells.first?.text == "未确认")
        #expect(rows.first { $0.id == "vehicle-insight" }?.cells.first?.tone == .unavailable)
    }
}
```

- [ ] **Step 2: Run the presentation tests and verify they fail**

Run:

```bash
swift test --filter ComparisonPresentation
```

Expected: compilation fails because the presentation types are undefined.

- [ ] **Step 3: Implement matrix types and fixed rows**

Create `Sources/CarRentalOptimizer/ComparisonPresentation.swift` with this public-to-target API and helpers:

```swift
import CarRentalDomain
import Foundation

enum ComparisonSectionID: String, CaseIterable, Identifiable {
    case summary, cost, route, vehicle, trust
    var id: String { rawValue }

    var title: String {
        switch self {
        case .summary: return "决策摘要"
        case .cost: return "费用"
        case .route: return "门店与路线"
        case .vehicle: return "车型"
        case .trust: return "可信度与风险"
        }
    }
}

enum ComparisonCellTone: Equatable {
    case standard, advantage, warning, unavailable
}

struct ComparisonCell: Equatable, Identifiable {
    let candidateID: String
    let text: String
    let comparisonKey: String
    var tone: ComparisonCellTone = .standard
    var id: String { candidateID }
}

struct ComparisonRow: Equatable, Identifiable {
    let id: String
    let label: String
    let cells: [ComparisonCell]
    var isCore = false

    var hasDifferences: Bool {
        Set(cells.map(\.comparisonKey)).count > 1
    }
}

struct ComparisonSection: Equatable, Identifiable {
    let id: ComparisonSectionID
    let rows: [ComparisonRow]
    var title: String { id.title }
}

enum ComparisonPresentation {
    static func sections(
        candidates: [Recommendation],
        insightStates: [String: ComparisonInsightState],
        onlyDifferences: Bool
    ) -> [ComparisonSection] {
        let sections = [
            ComparisonSection(id: .summary, rows: summaryRows(candidates)),
            ComparisonSection(id: .cost, rows: costRows(candidates)),
            ComparisonSection(id: .route, rows: routeRows(candidates)),
            ComparisonSection(id: .vehicle, rows: vehicleRows(candidates, insightStates: insightStates)),
            ComparisonSection(id: .trust, rows: trustRows(candidates)),
        ]
        guard onlyDifferences else { return sections }
        return sections.map { section in
            ComparisonSection(id: section.id, rows: section.rows.filter { $0.isCore || $0.hasDifferences })
        }
    }

    private static func summaryRows(_ values: [Recommendation]) -> [ComparisonRow] {
        [
            textRow(id: "platform", label: "平台", values: values) { $0.listing.platform.label },
            textRow(id: "vehicle-name", label: "车型", values: values) { $0.listing.vehicleName },
            minimumRow(id: "best-total", label: "总成本", values: values, value: \.bestTotal, format: formatMoney, isCore: true),
            textRow(id: "store", label: "门店", values: values) { $0.listing.store.name },
        ]
    }

    private static func costRows(_ values: [Recommendation]) -> [ComparisonRow] {
        [
            minimumRow(id: "rental-total", label: "租车小计", values: values, value: \.rentalTotal, format: formatMoney),
            minimumRow(id: "base-price", label: "车辆租金", values: values, value: \.listing.basePrice, format: formatMoney),
            minimumRow(id: "platform-fees", label: "平台费", values: values, value: \.listing.platformFees, format: formatMoney),
            minimumRow(id: "insurance-fees", label: "保险费", values: values, value: \.listing.insuranceFees, format: formatMoney),
            minimumRow(id: "one-way-fee", label: "异店费", values: values, value: \.listing.oneWayFee, format: formatMoney),
            minimumRow(id: "arrival-cost", label: "最优到店成本", values: values, value: bestRouteCost, format: formatMoney),
        ]
    }

    private static func routeRows(_ values: [Recommendation]) -> [ComparisonRow] {
        [
            minimumRow(id: "store-distance", label: "门店距离", values: values, value: \.listing.store.distanceKm, format: { String(format: "%.1f km", $0) }),
            textRow(id: "store-address", label: "门店地址", values: values) { $0.listing.store.address },
            textRow(id: "store-hours", label: "营业时间", values: values) { $0.listing.store.hours },
            minimumRow(id: "taxi-cost", label: "打车成本", values: values, value: \.taxiRoute.cost, format: formatMoney),
            minimumRow(id: "taxi-duration", label: "打车时间", values: values, value: \.taxiRoute.durationMinutes, format: { "\(Int($0.rounded())) 分" }),
            minimumRow(id: "transit-cost", label: "公交成本", values: values, value: \.transitRoute.cost, format: formatMoney),
            minimumRow(id: "transit-duration", label: "公交时间", values: values, value: \.transitRoute.durationMinutes, format: { "\(Int($0.rounded())) 分" }),
        ]
    }

    private static func vehicleRows(
        _ values: [Recommendation],
        insightStates: [String: ComparisonInsightState]
    ) -> [ComparisonRow] {
        let insightCells = values.map { candidate in
            guard let state = insightStates[candidate.id] else {
                return ComparisonCell(candidateID: candidate.id, text: "未确认", comparisonKey: "unknown", tone: .unavailable)
            }
            let insight = state.insight
            let tone: ComparisonCellTone = {
                if case .fallback = state { return .warning }
                return .standard
            }()
            return ComparisonCell(candidateID: candidate.id, text: insight.shortSummary, comparisonKey: insight.shortSummary, tone: tone)
        }
        return [
            textRow(id: "vehicle-class", label: "车型类别", values: values) { $0.listing.vehicleClass },
            textRow(id: "vehicle-match", label: "匹配程度", values: values) { $0.match.displayLabel ?? "未指定" },
            ComparisonRow(id: "vehicle-insight", label: "车型资料", cells: insightCells),
        ]
    }

    private static func trustRows(_ values: [Recommendation]) -> [ComparisonRow] {
        let maxCompleteness = values.map(\.listing.dataCompleteness).max()
        return [
            ComparisonRow(
                id: "completeness",
                label: "费用完整度",
                cells: values.map { value in
                    let percent = Int((value.listing.dataCompleteness * 100).rounded())
                    return ComparisonCell(
                        candidateID: value.id,
                        text: "\(percent)%",
                        comparisonKey: "\(percent)",
                        tone: value.listing.dataCompleteness == maxCompleteness ? .advantage : .standard
                    )
                }
            ),
            textRow(id: "credibility", label: "报价可信度", values: values) { QuoteCredibility.make(for: $0).title },
            textRow(id: "warnings", label: "风险", values: values) { recommendation in
                recommendation.warnings.isEmpty
                    ? "无已知风险"
                    : renderWarnings(recommendation.warnings)
            },
        ]
    }

    private static func textRow(
        id: String,
        label: String,
        values: [Recommendation],
        text: (Recommendation) -> String
    ) -> ComparisonRow {
        ComparisonRow(
            id: id,
            label: label,
            cells: values.map {
                let rendered = text($0)
                return ComparisonCell(candidateID: $0.id, text: rendered, comparisonKey: rendered)
            }
        )
    }

    private static func minimumRow(
        id: String,
        label: String,
        values: [Recommendation],
        value: (Recommendation) -> Double,
        format: (Double) -> String,
        isCore: Bool = false
    ) -> ComparisonRow {
        let minimum = values.map(value).min()
        return ComparisonRow(
            id: id,
            label: label,
            cells: values.map { recommendation in
                let raw = value(recommendation)
                return ComparisonCell(
                    candidateID: recommendation.id,
                    text: format(raw),
                    comparisonKey: String(format: "%.4f", raw),
                    tone: minimum.map { raw == $0 } == true ? .advantage : .standard
                )
            },
            isCore: isCore
        )
    }

    private static func bestRouteCost(_ value: Recommendation) -> Double {
        value.bestRouteMode == .taxi ? value.taxiRoute.cost : value.transitRoute.cost
    }
}
```

- [ ] **Step 4: Add dynamic vehicle specification and configuration rows**

Inside `vehicleRows`, after the initial `insightCells`, build rows for the union of `formattedBasicSpecs` and `formattedConfigurationFacts` labels:

```swift
let insightsByID = insightStates.mapValues(\.insight)
let basicLabels = orderedUnique(values.flatMap { candidate in
    insightsByID[candidate.id]?.formattedBasicSpecs.map(\.label) ?? []
})
let configurationLabels = VehicleInsight.commonConfigurationFeatureNames

let basicRows = basicLabels.map { label in
    insightFactRow(
        id: "spec-\(label)",
        label: label,
        candidates: values,
        insightsByID: insightsByID,
        facts: { $0.formattedBasicSpecs }
    )
}
let configurationRows = configurationLabels.map { label in
    insightFactRow(
        id: "feature-\(label)",
        label: label,
        candidates: values,
        insightsByID: insightsByID,
        facts: { $0.formattedConfigurationFacts }
    )
}

return [
    textRow(id: "vehicle-class", label: "车型类别", values: values) { $0.listing.vehicleClass },
    textRow(id: "vehicle-match", label: "匹配程度", values: values) { $0.match.displayLabel ?? "未指定" },
    ComparisonRow(id: "vehicle-insight", label: "车型资料", cells: insightCells),
] + basicRows + configurationRows
```

Change `VehicleInsight.commonConfigurationFeatureNames` from `private static let` to `static let` in `VehicleInsights.swift`, then add these helpers inside `ComparisonPresentation`:

```swift
private static func orderedUnique(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.filter { seen.insert($0).inserted }
}

private static func insightFactRow(
    id: String,
    label: String,
    candidates: [Recommendation],
    insightsByID: [String: VehicleInsight],
    facts: (VehicleInsight) -> [VehicleInsightFact]
) -> ComparisonRow {
    ComparisonRow(
        id: id,
        label: label,
        cells: candidates.map { candidate in
            let fact = insightsByID[candidate.id].flatMap { insight in
                facts(insight).first { $0.label == label }
            }
            guard let fact else {
                return ComparisonCell(candidateID: candidate.id, text: "未确认", comparisonKey: "unknown", tone: .unavailable)
            }
            return ComparisonCell(candidateID: candidate.id, text: fact.value, comparisonKey: fact.value)
        }
    )
}
```

- [ ] **Step 5: Run tests and commit presentation**

Run:

```bash
swift test --filter ComparisonPresentation
```

Expected: PASS with 4 tests.

```bash
git add Sources/CarRentalOptimizer/ComparisonPresentation.swift Sources/CarRentalOptimizer/VehicleInsights.swift Tests/CarRentalOptimizerTests/ComparisonPresentationTests.swift
git commit -m "feat: build decision comparison presentation"
```

### Task 4: Selection Bar and In-Place Matrix UI

**Files:**
- Create: `Sources/CarRentalOptimizer/ComparisonSelectionBar.swift`
- Create: `Sources/CarRentalOptimizer/ComparisonMatrixView.swift`
- Modify: `Sources/CarRentalOptimizer/ContentView.swift`
- Modify: `Sources/CarRentalOptimizer/AppShellView.swift`
- Modify: `Sources/CarRentalOptimizer/ResultPanelView.swift`
- Modify: `Tests/CarRentalOptimizerTests/UIEffectsSourceTests.swift`

**Interfaces:**
- Consumes: plan-2 comparison model/presentation and plan-1 shell.
- Produces:
  - Candidate checkboxes visible on every result card.
  - `ComparisonSelectionBar` after at least one candidate is selected.
  - `ComparisonMatrixView` replacing result/detail panels while `isComparing == true`.
  - Per-column remove, current-selection, monitor, official-page, and insight-retry actions.

- [ ] **Step 1: Add source-contract tests for comparison adoption**

Append to `UIEffectsSourceTests.swift`:

```swift
@Test("Search workspace exposes multi-select and the in-place comparison matrix")
func searchWorkspaceExposesComparison() throws {
    let result = try String(contentsOfFile: "Sources/CarRentalOptimizer/ResultPanelView.swift", encoding: .utf8)
    let shell = try String(contentsOfFile: "Sources/CarRentalOptimizer/AppShellView.swift", encoding: .utf8)
    let matrix = try String(contentsOfFile: "Sources/CarRentalOptimizer/ComparisonMatrixView.swift", encoding: .utf8)

    #expect(result.contains("comparisonViewModel.toggle(result)"))
    #expect(result.contains("ComparisonSelectionBar("))
    #expect(shell.contains("comparisonViewModel.isComparing"))
    #expect(shell.contains("ComparisonMatrixView()"))
    #expect(matrix.contains("只看差异"))
    #expect(matrix.contains("设为当前方案"))
    #expect(matrix.contains("打开官方页面"))
}
```

- [ ] **Step 2: Run the source-contract test and verify it fails**

Run:

```bash
swift test --filter UIEffectsSourceTests
```

Expected: FAIL because the comparison views do not exist.

- [ ] **Step 3: Create the selection bar**

Create `ComparisonSelectionBar.swift`:

```swift
import SwiftUI

struct ComparisonSelectionBar: View {
    @EnvironmentObject private var comparisonViewModel: ComparisonWorkspaceViewModel

    var body: some View {
        HStack(spacing: 8) {
            ForEach(comparisonViewModel.selectedRecommendations) { recommendation in
                HStack(spacing: 5) {
                    Text(recommendation.listing.vehicleName)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                    Button {
                        comparisonViewModel.remove(id: recommendation.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("移除\(recommendation.listing.vehicleName)")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Capsule().fill(WorkbenchStyle.decisionBlue.opacity(0.10)))
            }

            Spacer(minLength: 8)

            Text("已选 \(comparisonViewModel.selectedRecommendations.count)/4")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WorkbenchStyle.muted)

            Button("开始对比") {
                comparisonViewModel.beginComparison()
            }
            .buttonStyle(.borderedProminent)
            .tint(WorkbenchStyle.decisionBlue)
            .disabled(!comparisonViewModel.canBeginComparison)
            .help(comparisonViewModel.canBeginComparison ? "打开原位对比矩阵" : "至少选择两个候选")
        }
        .padding(10)
        .background(WorkbenchStyle.panelSurface)
        .overlay(alignment: .top) {
            Rectangle().fill(WorkbenchStyle.hairline).frame(height: 1)
        }
    }
}
```

- [ ] **Step 4: Create the matrix view**

Create `ComparisonMatrixView.swift` with a horizontally scrollable sticky-label matrix. Use this structure and keep the row rendering exhaustive over `ComparisonCellTone`:

```swift
import AppKit
import CarRentalDomain
import SwiftUI

struct ComparisonMatrixView: View {
    @EnvironmentObject private var searchViewModel: SearchViewModel
    @EnvironmentObject private var monitorViewModel: MonitorCenterViewModel
    @EnvironmentObject private var comparisonViewModel: ComparisonWorkspaceViewModel
    @State private var pendingMonitorRecommendation: Recommendation?

    private var sections: [ComparisonSection] {
        ComparisonPresentation.sections(
            candidates: comparisonViewModel.selectedRecommendations,
            insightStates: comparisonViewModel.insightStates,
            onlyDifferences: comparisonViewModel.onlyShowsDifferences
        )
    }

    var body: some View {
        WorkbenchPanel(title: "方案对比", subtitle: "\(comparisonViewModel.selectedRecommendations.count) 个真实候选") {
            VStack(spacing: 0) {
                HStack {
                    Button {
                        comparisonViewModel.exitComparison()
                    } label: {
                        Label("返回候选", systemImage: "chevron.left")
                    }
                    .buttonStyle(.bordered)

                    Toggle("只看差异", isOn: $comparisonViewModel.onlyShowsDifferences)
                        .toggleStyle(.checkbox)

                    Spacer()
                    Text("未确认表示平台或车型库未提供，不能解释为不支持")
                        .font(.caption2)
                        .foregroundStyle(WorkbenchStyle.muted)
                }
                .padding(12)

                ScrollView([.horizontal, .vertical]) {
                    Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                        GridRow {
                            matrixHeaderCell("比较项", width: 150)
                            ForEach(comparisonViewModel.selectedRecommendations) { recommendation in
                                candidateHeader(recommendation)
                                    .frame(width: 220)
                            }
                        }

                        ForEach(sections) { section in
                            GridRow {
                                Text(section.title)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(WorkbenchStyle.routeInk)
                                    .frame(width: 150, alignment: .leading)
                                    .padding(9)
                                ForEach(comparisonViewModel.selectedRecommendations) { _ in
                                    Color.clear.frame(width: 220, height: 1)
                                }
                            }
                            .background(WorkbenchStyle.decisionBlue.opacity(0.07))

                            ForEach(section.rows) { row in
                                GridRow {
                                    matrixHeaderCell(row.label, width: 150)
                                    ForEach(row.cells) { cell in
                                        Text(cell.text)
                                            .font(.caption)
                                            .foregroundStyle(cellColor(cell.tone))
                                            .frame(width: 220, alignment: .leading)
                                            .frame(minHeight: 36)
                                            .padding(.horizontal, 9)
                                            .background(cellBackground(cell.tone))
                                    }
                                }
                                Divider()
                            }
                        }
                    }
                    .padding(12)
                }
            }
        }
        .sheet(item: $pendingMonitorRecommendation) { recommendation in
            CreateMonitorSheet(
                recommendation: recommendation,
                request: searchViewModel.request,
                onSaveFromRecommendation: { frequency, rule, notifications in
                    try await monitorViewModel.createMonitor(
                        from: recommendation,
                        request: searchViewModel.request,
                        frequency: frequency,
                        alertRule: rule,
                        systemNotificationsEnabled: notifications
                    )
                },
                onSaveManual: { _, _, _, _, _, _ in }
            )
        }
    }

    private func candidateHeader(_ recommendation: Recommendation) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(recommendation.listing.vehicleName)
                    .font(.callout.weight(.bold))
                    .lineLimit(2)
                Spacer()
                Button {
                    comparisonViewModel.remove(id: recommendation.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("移除此候选")
            }
            Text(formatMoney(recommendation.bestTotal))
                .font(.title3.weight(.bold))
                .monospacedDigit()
            HStack(spacing: 6) {
                Button("设为当前方案") {
                    searchViewModel.selectResult(recommendation.id)
                    comparisonViewModel.exitComparison()
                }
                Button("监控") {
                    pendingMonitorRecommendation = recommendation
                }
                Button("打开官方页面") {
                    guard let url = URL(string: recommendation.listing.sourceUrl) else { return }
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.borderless)
            .controlSize(.small)

            insightStatus(for: recommendation)
        }
        .frame(width: 220, alignment: .topLeading)
        .frame(minHeight: 112, alignment: .top)
        .padding(9)
        .background(WorkbenchStyle.elevatedSurface)
    }

    private func matrixHeaderCell(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(WorkbenchStyle.muted)
            .frame(width: width, alignment: .leading)
            .frame(minHeight: 36)
            .padding(.horizontal, 9)
    }

    @ViewBuilder
    private func insightStatus(for recommendation: Recommendation) -> some View {
        if let state = comparisonViewModel.insightStates[recommendation.id] {
            switch state {
            case .loading:
                Label("正在读取车型资料", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption2)
                    .foregroundStyle(WorkbenchStyle.decisionBlue)
            case .loaded:
                Label("车型资料已加载", systemImage: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(WorkbenchStyle.signalTeal)
            case .fallback:
                Button("联网资料不可用，重试车型资料") {
                    comparisonViewModel.retryInsight(for: recommendation)
                }
                .buttonStyle(.link)
                .font(.caption2)
            }
        }
    }

    private func cellColor(_ tone: ComparisonCellTone) -> Color {
        switch tone {
        case .standard: return WorkbenchStyle.ink
        case .advantage: return WorkbenchStyle.signalTeal
        case .warning: return WorkbenchStyle.riskAmber
        case .unavailable: return WorkbenchStyle.muted
        }
    }

    private func cellBackground(_ tone: ComparisonCellTone) -> Color {
        tone == .advantage ? WorkbenchStyle.signalTeal.opacity(0.08) : Color.clear
    }
}
```

- [ ] **Step 5: Share the insight service, inject comparison state, and switch in place**

In `ContentView`, add the stored state object:

```swift
@StateObject private var comparisonViewModel: ComparisonWorkspaceViewModel
```

In `ContentView.init()`, replace the first `_viewModel` assignment with:

```swift
let vehicleInsightService = VehicleInsightService()
_viewModel = StateObject(
    wrappedValue: SearchViewModel(vehicleInsightService: vehicleInsightService)
)
_comparisonViewModel = StateObject(
    wrappedValue: ComparisonWorkspaceViewModel(vehicleInsightService: vehicleInsightService)
)
```

In `ContentView.body`, add:

```swift
.environmentObject(comparisonViewModel)
```

In `AppShellView`, add:

```swift
@EnvironmentObject private var comparisonViewModel: ComparisonWorkspaceViewModel
```

Replace `searchWorkspace` with:

```swift
private var searchWorkspace: some View {
    HSplitView {
        SearchPanelView()
            .frame(
                minWidth: AppWindowLayout.searchPanelMinimumWidth,
                idealWidth: AppWindowLayout.searchPanelIdealWidth,
                maxWidth: AppWindowLayout.searchPanelMaximumWidth
            )

        if comparisonViewModel.isComparing {
            ComparisonMatrixView()
                .frame(
                    minWidth: AppWindowLayout.resultsPanelMinimumWidth + AppWindowLayout.detailPanelMinimumWidth,
                    idealWidth: AppWindowLayout.resultsPanelIdealWidth + AppWindowLayout.detailPanelIdealWidth
                )
        } else {
            ResultPanelView()
                .frame(minWidth: AppWindowLayout.resultsPanelMinimumWidth, idealWidth: AppWindowLayout.resultsPanelIdealWidth)
            DetailPanelView()
                .frame(
                    minWidth: AppWindowLayout.detailPanelMinimumWidth,
                    idealWidth: AppWindowLayout.detailPanelIdealWidth,
                    maxWidth: AppWindowLayout.detailPanelMaximumWidth
                )
        }
    }
    .onChange(of: searchViewModel.searchGeneration) { _, _ in
        comparisonViewModel.resetForNewSearch()
    }
    .onChange(of: searchViewModel.results) { _, results in
        comparisonViewModel.reconcile(with: results)
    }
}
```

- [ ] **Step 6: Add candidate checkboxes and the selection bar**

In `ResultPanelView`, add:

```swift
@EnvironmentObject var comparisonViewModel: ComparisonWorkspaceViewModel
```

Wrap the existing content group in a `VStack(spacing: 0)`, then append:

```swift
if !comparisonViewModel.selectedRecommendations.isEmpty {
    ComparisonSelectionBar()
}
```

Inside the result scroll stack, immediately above `SearchDiagnosticSummaryView`, add a recoverable hidden-selection notice:

```swift
if viewModel.isSelectedResultHidden {
    WorkbenchCard(fill: WorkbenchStyle.riskAmber.opacity(0.08), stroke: WorkbenchStyle.riskAmber.opacity(0.24), padding: 10) {
        HStack(spacing: 8) {
            ActionStatusRow(
                icon: "line.3.horizontal.decrease.circle.fill",
                title: "当前方案被筛选隐藏",
                message: "右侧仍显示刚刚设为当前的方案；清空筛选后可在候选列表中定位。",
                tone: .warning
            )
            Button("清空筛选") {
                viewModel.clearRecommendationFilters()
                viewModel.showsAllVehicleMatches = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}
```

Place these properties before the two action closures in `ResultSignalCard`:

```swift
let isComparisonSelected: Bool
let isComparisonSelectionEnabled: Bool
let onToggleComparison: () -> Void
let onMonitor: () -> Void
```

Remove the earlier `let onMonitor: () -> Void` declaration so it appears exactly once.

At the start of `cardHeader`, before the rank badge, add:

```swift
Button(action: onToggleComparison) {
    Image(systemName: isComparisonSelected ? "checkmark.square.fill" : "square")
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(isComparisonSelected ? WorkbenchStyle.decisionBlue : WorkbenchStyle.muted)
}
.buttonStyle(.plain)
.disabled(!isComparisonSelectionEnabled)
.accessibilityLabel(isComparisonSelected ? "从对比中移除" : "加入对比")
.help(isComparisonSelectionEnabled ? "选择此方案进行对比" : "最多选择 4 个方案")
```

Replace the `ResultSignalCard` initializer with this fully labeled call:

```swift
ResultSignalCard(
    rank: index + 1,
    recommendation: result,
    isSelected: viewModel.selected?.id == result.id,
    isComparisonSelected: comparisonViewModel.isSelected(result.id),
    isComparisonSelectionEnabled: comparisonViewModel.canSelect(result.id),
    onToggleComparison: { comparisonViewModel.toggle(result) },
    onMonitor: {
        viewModel.selectResult(result.id)
        pendingMonitorRecommendation = result
    }
)
```

Keep the existing `.contentShape`, transition, and `.onTapGesture { viewModel.selectResult(result.id) }` modifiers after the initializer.

- [ ] **Step 7: Run focused and full verification**

Run:

```bash
swift test --filter ComparisonWorkspace
swift test --filter ComparisonPresentation
swift test --filter UIEffectsSourceTests
swift build
swift test
```

Expected: all commands exit 0.

- [ ] **Step 8: Commit the comparison UI**

```bash
git add Sources/CarRentalOptimizer/ComparisonSelectionBar.swift Sources/CarRentalOptimizer/ComparisonMatrixView.swift Sources/CarRentalOptimizer/ContentView.swift Sources/CarRentalOptimizer/AppShellView.swift Sources/CarRentalOptimizer/ResultPanelView.swift Tests/CarRentalOptimizerTests/UIEffectsSourceTests.swift
git commit -m "feat: add in-place recommendation comparison"
```

### Task 5: Comparison App Verification

**Files:**
- No source changes expected.

**Interfaces:**
- Consumes: complete comparison feature.
- Produces: automated and manual evidence for plan 3.

- [ ] **Step 1: Build, test, bundle, and launch**

```bash
swift build
swift test
scripts/build-app.sh
scripts/verify-launch.sh build/租车比价助手.app
```

Expected: all commands exit 0.

- [ ] **Step 2: Verify the approved interaction matrix manually**

Verify:

- One selected candidate cannot enter matrix mode; two can.
- A fifth candidate cannot be selected and explains the four-item limit.
- Sorting and filtering do not remove already selected candidates.
- A valid new search clears selection; a blocked search does not.
- Matrix mode keeps the left search panel visible and merges the middle/right space.
- “只看差异” removes identical non-core rows while total cost remains.
- Cheapest total, shortest distance, and highest completeness can highlight different candidates.
- Unknown vehicle configuration reads “未确认”.
- A local fallback affects only its candidate column and exposes retry.
- Removing down to one candidate exits matrix mode and preserves the remaining selection.
- “设为当前方案”, “监控”, and “打开官方页面” perform their named actions.

- [ ] **Step 3: Confirm a clean handoff**

```bash
git status --short
```

Expected: clean working tree with no version, tag, appcast, or release artifact changes.
