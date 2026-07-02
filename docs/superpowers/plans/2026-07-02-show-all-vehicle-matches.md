# Show All Vehicle Matches Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a result-panel control that keeps concrete vehicle searches focused on the cheapest match by default while allowing users to expand all matching quotes.

**Architecture:** `CarRentalDomain` should return all exact matches for concrete vehicle queries instead of deduping them too early. `SearchViewModel` owns the cheapest-only display collapse and the `showsAllVehicleMatches` state. `ResultPanelView` exposes a compact button in the existing filter bar when multiple concrete matches are available.

**Tech Stack:** Swift 5.9 package, SwiftUI on macOS 14, Swift Testing for optimizer tests, XCTest for domain tests.

## Global Constraints

- Default concrete vehicle searches show only the cheapest matching recommendation.
- `显示全部匹配` shows only recommendations matching the requested concrete vehicle, not unrelated models.
- Blank and generic class queries keep existing behavior.
- A normal new search resets to cheapest-only; retrying failed platforms preserves the current expanded/collapsed state.
- No new dependencies or frameworks.

---

## File Structure

- Modify `Sources/CarRentalDomain/SearchOrchestrator.swift`: remove the concrete-query dedupe path so exact matches survive into the UI layer.
- Modify `Tests/CarRentalDomainTests/SearchOrchestratorTests.swift`: replace the current concrete-query single-result expectation with a test that exact matches are preserved and sorted cheapest first.
- Modify `Sources/CarRentalOptimizer/SearchViewModel.swift`: add expansion state, exact-match collapse helpers, and reset behavior.
- Modify `Tests/CarRentalOptimizerTests/SearchViewModelTests.swift`: add ViewModel tests for default collapse, expansion, blank/generic bypass, and retry preservation.
- Modify `Sources/CarRentalOptimizer/ResultPanelView.swift`: add the compact display toggle and subtitle copy.

---

### Task 1: Keep Exact Matches From Domain Ranking

**Files:**
- Modify: `Tests/CarRentalDomainTests/SearchOrchestratorTests.swift`
- Modify: `Sources/CarRentalDomain/SearchOrchestrator.swift`

**Interfaces:**
- Consumes: `rankRentalListings(request:listings:mapService:) async -> [Recommendation]`
- Produces: concrete vehicle queries return all exact matches sorted by existing ranking.

- [ ] **Step 1: Write the failing domain test**

Replace `testSpecificVehicleQueryKeepsBestExactVehicleOnly` in `Tests/CarRentalDomainTests/SearchOrchestratorTests.swift` with:

```swift
func testSpecificVehicleQueryKeepsAllExactMatchesSortedByCost() async {
    let expensiveLavida = RentalListing(
        id: "expensive-lavida",
        platform: .carInc,
        store: makeStore(
            id: "car-store-expensive",
            name: "通州站服务点",
            city: "北京",
            address: "北京市通州区",
            lat: 39.916,
            lng: 116.645,
            dist: 1.2,
            hours: "08:00-21:00"
        ),
        vehicleName: "大众朗逸",
        vehicleClass: "紧凑型轿车",
        basePrice: 880,
        platformFees: 0,
        insuranceFees: 0,
        oneWayFee: 0,
        sourceUrl: "https://m.zuche.com/",
        dataCompleteness: 0.9
    )
    let cheaperLavida = RentalListing(
        id: "cheaper-lavida",
        platform: .ehi,
        store: makeStore(
            id: "ehi-store-cheap",
            name: "通州北苑店",
            city: "北京",
            address: "北京市通州区",
            lat: 39.917,
            lng: 116.646,
            dist: 1.0,
            hours: "08:00-21:00"
        ),
        vehicleName: "大众 朗逸 自动",
        vehicleClass: "紧凑型轿车",
        basePrice: 620,
        platformFees: 0,
        insuranceFees: 0,
        oneWayFee: 0,
        sourceUrl: "https://booking.1hai.cn/",
        dataCompleteness: 0.9
    )

    let results = await rankRentalListings(
        request: makeBaseRequest(vehicleQuery: "大众朗逸"),
        listings: [expensiveLavida, cheaperLavida],
        mapService: mapService
    )

    XCTAssertEqual(results.map(\.listing.id), ["cheaper-lavida", "expensive-lavida"])
}
```

- [ ] **Step 2: Run the failing domain test**

Run:

```bash
swift test --filter SearchOrchestratorTests/testSpecificVehicleQueryKeepsAllExactMatchesSortedByCost
```

Expected: FAIL because current code returns only `["cheaper-lavida"]`.

- [ ] **Step 3: Remove concrete-query dedupe from domain ranking**

In `Sources/CarRentalDomain/SearchOrchestrator.swift`, replace:

```swift
let ranked = rankRecommendations(filtered)
if !hasVehicleQuery {
    return mergeBlankVehicleRecommendations(ranked)
}
guard isSpecificVehicleQuery else {
    return ranked
}
return dedupeVehicleRecommendations(ranked, specificVehicleKey: vehicleQuery)
```

with:

```swift
let ranked = rankRecommendations(filtered)
if !hasVehicleQuery {
    return mergeBlankVehicleRecommendations(ranked)
}
return ranked
```

Then delete the now-unused `dedupeVehicleRecommendations(_:specificVehicleKey:)` helper and the private `normalizedVehicleKey(_:)` helper, because concrete-query dedupe no longer exists.

- [ ] **Step 4: Run domain verification**

Run:

```bash
swift test --filter SearchOrchestratorTests
```

Expected: PASS.

---

### Task 2: Add ViewModel Collapse And Expansion State

**Files:**
- Modify: `Tests/CarRentalOptimizerTests/SearchViewModelTests.swift`
- Modify: `Sources/CarRentalOptimizer/SearchViewModel.swift`

**Interfaces:**
- Produces: `@Published var showsAllVehicleMatches: Bool`
- Produces: `var hasExpandableVehicleMatches: Bool`
- Produces: `var vehicleMatchDisplaySummary: String?`
- Consumes: `request.vehicleQuery`, `results`, `match.kind`, `displayedResults`

- [ ] **Step 1: Write failing ViewModel tests**

Add these tests after `displayedResultsCanDeduplicateByStoreOrVehicleUsingLowestTotal` in `Tests/CarRentalOptimizerTests/SearchViewModelTests.swift`:

```swift
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
```

Add this assertion to `runSearchClearsStaleRecommendationFiltersBeforeDisplayingNewResults` before `await viewModel.runSearch()`:

```swift
viewModel.showsAllVehicleMatches = true
```

Add this assertion after `await viewModel.runSearch()`:

```swift
#expect(!viewModel.showsAllVehicleMatches)
```

Add this assertion to `retrySearchRequestsFailedPlatformsOnlyAndReusesSuccessfulEvidence` before `await viewModel.retrySearch()`:

```swift
viewModel.showsAllVehicleMatches = true
```

Add this assertion after `await viewModel.retrySearch()`:

```swift
#expect(viewModel.showsAllVehicleMatches)
```

- [ ] **Step 2: Run the failing ViewModel tests**

Run:

```bash
swift test --filter SearchViewModelTests
```

Expected: FAIL because `showsAllVehicleMatches`, `hasExpandableVehicleMatches`, and `vehicleMatchDisplaySummary` do not exist.

- [ ] **Step 3: Implement minimal ViewModel state and collapse**

In `Sources/CarRentalOptimizer/SearchViewModel.swift`, add near the other published display state:

```swift
@Published var showsAllVehicleMatches = false {
    didSet {
        guard showsAllVehicleMatches != oldValue else { return }
        selectFirstDisplayedResult()
    }
}
```

Change `displayedResults` to:

```swift
var displayedResults: [Recommendation] {
    let vehicleScoped = vehicleMatchScopedResults(results)
    let filtered = filteredRecommendations(vehicleScoped)
    return sortedRecommendations(filtered)
}
```

Add these computed properties and helpers near `filteredResultCount`:

```swift
var hasExpandableVehicleMatches: Bool {
    concreteVehicleMatches(in: results).count > 1
}

var vehicleMatchDisplaySummary: String? {
    let count = concreteVehicleMatches(in: results).count
    guard count > 1 else { return nil }
    if showsAllVehicleMatches {
        return "\(count) 个匹配已展开"
    }
    return "1/\(count) 个匹配，显示最低价"
}

private func vehicleMatchScopedResults(_ recommendations: [Recommendation]) -> [Recommendation] {
    let matches = concreteVehicleMatches(in: recommendations)
    guard matches.count > 1 else { return recommendations }
    guard !showsAllVehicleMatches else { return matches }
    return Array(rankRecommendations(matches).prefix(1))
}

private func concreteVehicleMatches(in recommendations: [Recommendation]) -> [Recommendation] {
    let query = request.vehicleQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    guard isSpecificVehicleModelQuery(query) else { return [] }
    return recommendations.filter { $0.match.kind == .exact }
}
```

In `performSearch(retryingFailedPlatformsOnly:)`, inside the existing `if !retryingFailedPlatformsOnly { ... }` block, add:

```swift
showsAllVehicleMatches = false
```

- [ ] **Step 4: Run ViewModel verification**

Run:

```bash
swift test --filter SearchViewModelTests
```

Expected: PASS.

---

### Task 3: Add Result Panel Toggle

**Files:**
- Modify: `Sources/CarRentalOptimizer/ResultPanelView.swift`
- Modify: `Tests/CarRentalOptimizerTests/UIEffectsSourceTests.swift`

**Interfaces:**
- Consumes: `viewModel.hasExpandableVehicleMatches`
- Consumes: `$viewModel.showsAllVehicleMatches`
- Consumes: `viewModel.vehicleMatchDisplaySummary`

- [ ] **Step 1: Add a source-contract test**

In `Tests/CarRentalOptimizerTests/UIEffectsSourceTests.swift`, add these expectations to `resultPanelUsesSignalCardsAndStagedLoading`:

```swift
#expect(source.contains("hasExpandableVehicleMatches"))
#expect(source.contains("showsAllVehicleMatches.toggle()"))
#expect(source.contains("显示全部匹配"))
#expect(source.contains("只看最低价"))
```

Run:

```bash
swift test --filter UIEffectsSourceTests
```

Expected: FAIL until the UI strings are added.

- [ ] **Step 2: Implement the button in the filter bar**

In `Sources/CarRentalOptimizer/ResultPanelView.swift`, inside `RecommendationFilterBar`'s top `HStack`, insert this before the clear-filter button:

```swift
if viewModel.hasExpandableVehicleMatches {
    Button {
        viewModel.showsAllVehicleMatches.toggle()
    } label: {
        Label(
            viewModel.showsAllVehicleMatches ? "只看最低价" : "显示全部匹配",
            systemImage: viewModel.showsAllVehicleMatches ? "line.3.horizontal.decrease.circle" : "list.bullet.rectangle"
        )
    }
    .buttonStyle(.borderless)
    .controlSize(.small)
}
```

Change `panelSubtitle` so the active-filter branch becomes:

```swift
if let vehicleSummary = viewModel.vehicleMatchDisplaySummary {
    return vehicleSummary
}
if viewModel.hasActiveRecommendationFilters {
    return "\(viewModel.filteredResultCount)/\(viewModel.results.count) 个候选已筛选"
}
```

- [ ] **Step 3: Run UI source tests**

Run:

```bash
swift test --filter UIEffectsSourceTests
```

Expected: PASS.

---

### Task 4: Final Verification

**Files:**
- Verify all modified files.

**Interfaces:**
- Consumes all changes from Tasks 1-3.

- [ ] **Step 1: Run focused test suites**

Run:

```bash
swift test --filter SearchOrchestratorTests
swift test --filter SearchViewModelTests
swift test --filter UIEffectsSourceTests
```

Expected: all PASS.

- [ ] **Step 2: Run full test suite**

Run:

```bash
swift test
```

Expected: PASS with all suites green.

- [ ] **Step 3: Inspect diff**

Run:

```bash
git diff -- Sources/CarRentalDomain/SearchOrchestrator.swift Tests/CarRentalDomainTests/SearchOrchestratorTests.swift Sources/CarRentalOptimizer/SearchViewModel.swift Tests/CarRentalOptimizerTests/SearchViewModelTests.swift Sources/CarRentalOptimizer/ResultPanelView.swift Tests/CarRentalOptimizerTests/UIEffectsSourceTests.swift
```

Expected: only the domain dedupe removal, ViewModel display state/collapse, filter-bar toggle, and tests are changed.
