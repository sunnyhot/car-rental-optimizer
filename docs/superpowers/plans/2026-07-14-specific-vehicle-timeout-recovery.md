# Specific Vehicle Timeout Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent failed searches from showing candidates produced by different conditions, and let 500 km CAR Inc searches finish with dynamically scaled concurrency and a 60-second platform timeout.

**Architecture:** Bind the last successful recommendations to the exact resolved `SearchRequest` and restore them only for an identical failed request. Replace the fixed CAR Inc city worker count with a pure tier function (3/4/6/8 workers), retain the shared 120ms throttle and bounded rate-limit retry, and give only CAR Inc a 60-second outer timeout while eHi keeps the existing 35-second default.

**Tech Stack:** Swift 5.9 package, Swift concurrency task groups and actors, Swift Testing, existing `CarRentalDomain.SearchRequest` equality.

## Global Constraints

- A changed origin, dates, return mode, radius, vehicle query, or platform list must never restore candidates from a previous request.
- An identical failed request may restore the last successful candidates and the existing retained-results notice.
- CAR Inc city concurrency tiers are exactly: 1–12 → 3, 13–30 → 4, 31–48 → 6, 49–60 → 8, bounded by the actual city count.
- Keep `maxZucheVehicleSearchCityCount` at 60, the shared throttle interval at 120ms, and the existing maximum of 3 attempts for rate-limited gateway calls.
- CAR Inc uses a 60-second outer timeout; eHi retains the existing 35-second default.
- Do not change exact vehicle matching, ranking, price calculation, confirmation-fee enrichment, or persistence formats.
- Do not add dependencies or change the macOS 14 minimum.

## File Structure

- Modify `Sources/CarRentalOptimizer/SearchViewModel.swift`: store the request associated with successful results and require exact equality before restoring them.
- Modify `Tests/CarRentalOptimizerTests/SearchViewModelTests.swift`: cover changed-vehicle isolation and identical-request retention.
- Modify `Sources/CarRentalOptimizer/LiveRentalSearchService.swift`: add the pure concurrency tier function, use it in the city task group, and set the CAR Inc timeout to 60 seconds.
- Modify `Tests/CarRentalOptimizerTests/LiveRentalSearchServiceTests.swift`: cover tier boundaries, timeout separation, and continued shared throttling.

---

### Task 1: Bind retained results to the exact search request

**Files:**
- Modify: `Sources/CarRentalOptimizer/SearchViewModel.swift:285-288, 649-695, 1015-1037`
- Test: `Tests/CarRentalOptimizerTests/SearchViewModelTests.swift:424-453`

**Interfaces:**
- Produces: private `latestSuccessfulRequest: SearchRequest?` stored with successful recommendations.
- Produces: `recordSuccessfulResults(_:request:)` recording recommendations and their resolved request atomically.
- Produces: `restoreLatestSuccessfulResultsIfAvailable(for:)` restoring only when the complete request equals `latestSuccessfulRequest`.

- [ ] **Step 1: Write the failing changed-vehicle regression test**

Add after the existing retained-results test:

```swift
@Test("Failed search with a changed vehicle does not restore previous candidates")
func failedSearchWithChangedVehicleDoesNotRestorePreviousCandidates() async {
    let provider = SequencedRentalSearchProvider(responses: [
        [
            PlatformEvidenceResult(
                platform: .ehi,
                status: PlatformEvidenceStatus(platform: .ehi, kind: .ready, message: "一嗨已返回报价。", sourceUrl: "https://booking.1hai.cn/"),
                listings: [makeTestListing()]
            ),
        ],
        [
            PlatformEvidenceResult(
                platform: .ehi,
                status: PlatformEvidenceStatus(platform: .ehi, kind: .parseFailed, message: "一嗨查询超时。", sourceUrl: "https://booking.1hai.cn/"),
                listings: []
            ),
        ],
    ])
    let viewModel = SearchViewModel(
        searchProvider: provider,
        geocoder: CurrentRequestGeocoder(point: AppDefaults.searchRequest.origin),
        mapService: EstimatedMapService()
    )
    viewModel.request.platforms = [.ehi]

    await viewModel.runSearch()
    #expect(!viewModel.results.isEmpty)

    viewModel.request.vehicleQuery = "尚界 H5"
    await viewModel.runSearch()

    #expect(viewModel.results.isEmpty)
    #expect(!viewModel.isShowingStaleResults)
    #expect(viewModel.retainedResultsNotice == nil)
}
```

- [ ] **Step 2: Rewrite the existing retention test to use an identical failed request**

Replace `failedSearchKeepsLastSuccessfulRecommendationsAsStaleResults` with:

```swift
@Test("Failed identical search keeps last successful recommendations as stale results")
func failedIdenticalSearchKeepsLastSuccessfulRecommendationsAsStaleResults() async {
    let provider = SequencedRentalSearchProvider(responses: [
        [
            PlatformEvidenceResult(
                platform: .ehi,
                status: PlatformEvidenceStatus(platform: .ehi, kind: .ready, message: "一嗨已返回报价。", sourceUrl: "https://booking.1hai.cn/"),
                listings: [makeTestListing()]
            ),
        ],
        [
            PlatformEvidenceResult(
                platform: .ehi,
                status: PlatformEvidenceStatus(platform: .ehi, kind: .parseFailed, message: "一嗨查询超时。", sourceUrl: "https://booking.1hai.cn/"),
                listings: []
            ),
        ],
    ])
    let viewModel = SearchViewModel(
        searchProvider: provider,
        geocoder: CurrentRequestGeocoder(point: AppDefaults.searchRequest.origin),
        mapService: EstimatedMapService(),
        now: { Date(timeIntervalSince1970: 1_800_000_000) }
    )
    viewModel.request.platforms = [.ehi]

    await viewModel.runSearch()
    let successfulResultIDs = viewModel.results.map(\.id)
    await viewModel.runSearch()

    #expect(!successfulResultIDs.isEmpty)
    #expect(viewModel.results.map(\.id) == successfulResultIDs)
    #expect(viewModel.isShowingStaleResults)
    #expect(viewModel.retainedResultsNotice?.title == "显示上次成功结果")
}
```

- [ ] **Step 3: Run the focused suite and verify RED**

Run: `swift test --filter SearchViewModelTests`

Expected: the changed-vehicle test fails because the old implementation restores the previous recommendation despite the changed `vehicleQuery`.

- [ ] **Step 4: Store the successful request and gate restoration by equality**

Add beside `latestSuccessfulResults`:

```swift
private var latestSuccessfulRequest: SearchRequest?
```

Change the successful path to:

```swift
recordSuccessfulResults(recommendations, request: liveRequest)
```

Pass the current request at both failure sites:

```swift
restoreLatestSuccessfulResultsIfAvailable(for: liveRequest)
```

Replace the two private methods with:

```swift
private func recordSuccessfulResults(_ recommendations: [Recommendation], request: SearchRequest) {
    latestSuccessfulResults = recommendations
    latestSuccessfulSelectedId = selectedId
    latestSuccessfulRequest = request
    lastSuccessfulSearchAt = now()
    isShowingStaleResults = false
    retainedResultsNotice = nil
}

private func restoreLatestSuccessfulResultsIfAvailable(for request: SearchRequest) {
    guard !latestSuccessfulResults.isEmpty,
          let lastSuccessfulSearchAt,
          latestSuccessfulRequest == request
    else {
        results = []
        selectedId = ""
        isShowingStaleResults = false
        retainedResultsNotice = nil
        return
    }

    results = latestSuccessfulResults
    selectedId = latestSuccessfulSelectedId
    selectFirstDisplayedResult()
    isShowingStaleResults = true
    retainedResultsNotice = RetainedResultsNotice.make(lastSuccessfulSearchAt: lastSuccessfulSearchAt)
}
```

- [ ] **Step 5: Run the focused suite and verify GREEN**

Run: `swift test --filter SearchViewModelTests`

Expected: all `SearchViewModelTests` pass; changed vehicles leave results empty, while identical requests retain their own historical candidates.

- [ ] **Step 6: Commit result isolation**

```bash
git add Sources/CarRentalOptimizer/SearchViewModel.swift Tests/CarRentalOptimizerTests/SearchViewModelTests.swift
git commit -m "fix: isolate retained results by search request"
```

---

### Task 2: Scale CAR Inc city concurrency and extend only its timeout

**Files:**
- Modify: `Sources/CarRentalOptimizer/LiveRentalSearchService.swift:9-15, 80-87, 191-194, 430-469`
- Test: `Tests/CarRentalOptimizerTests/LiveRentalSearchServiceTests.swift:90-110, 294-310`

**Interfaces:**
- Produces: `liveZucheQueryTimeoutSeconds: TimeInterval == 60` while `livePlatformQueryTimeoutSeconds` remains 35 for eHi/default callers.
- Produces: `zucheCityQueryConcurrency(for cityCount: Int) -> Int` with exact tier boundaries and actual-count bounding.
- Consumes: existing `ZucheRequestThrottle(minimumInterval: 0.12)` and `withZucheRateLimitRetry` without modifying their retry behavior.

- [ ] **Step 1: Write failing tier and timeout tests**

Add after the platform timeout test:

```swift
@Test("CAR Inc uses a longer outer timeout without changing the default platform timeout")
func carIncUsesLongerOuterTimeoutWithoutChangingDefaultTimeout() {
    #expect(livePlatformQueryTimeoutSeconds == 35)
    #expect(liveZucheQueryTimeoutSeconds == 60)
}

@Test("CAR Inc city query concurrency scales with the planned city count")
func carIncCityQueryConcurrencyScalesWithPlannedCityCount() {
    #expect(zucheCityQueryConcurrency(for: 0) == 0)
    #expect(zucheCityQueryConcurrency(for: 1) == 1)
    #expect(zucheCityQueryConcurrency(for: 12) == 3)
    #expect(zucheCityQueryConcurrency(for: 13) == 4)
    #expect(zucheCityQueryConcurrency(for: 30) == 4)
    #expect(zucheCityQueryConcurrency(for: 31) == 6)
    #expect(zucheCityQueryConcurrency(for: 48) == 6)
    #expect(zucheCityQueryConcurrency(for: 49) == 8)
    #expect(zucheCityQueryConcurrency(for: 60) == 8)
}
```

Update the existing city-scan integration test to:

```swift
@Test("CAR Inc city scans use dynamic concurrency and shared throttling without shrinking coverage")
func carIncCityScansUseDynamicConcurrencyAndSharedThrottlingWithoutShrinkingCoverage() throws {
    let source = try liveRentalSearchServiceSource()

    #expect(maxZucheVehicleSearchCityCount == 60)
    #expect(source.contains("zucheCityQueryConcurrency(for: plannedCities.count)"))
    #expect(source.contains("ZucheRequestThrottle(minimumInterval: 0.12)"))
    #expect(source.contains("postCityGateway("))
    #expect(source.contains("throttle: requestThrottle"))
    #expect(source.contains("timeoutSeconds: liveZucheQueryTimeoutSeconds"))
}
```

- [ ] **Step 2: Run the focused suite and verify RED**

Run: `swift test --filter LiveRentalSearchServiceTests`

Expected: compilation fails because `liveZucheQueryTimeoutSeconds` and `zucheCityQueryConcurrency(for:)` do not exist, and the old integration test still relies on fixed concurrency 3.

- [ ] **Step 3: Add the CAR Inc timeout and dynamic tier function**

Keep the existing default and add the CAR Inc-specific timeout:

```swift
let livePlatformQueryTimeoutSeconds: TimeInterval = 35
let liveZucheQueryTimeoutSeconds: TimeInterval = 60
```

Replace `maxConcurrentZucheCityQueries` with:

```swift
func zucheCityQueryConcurrency(for cityCount: Int) -> Int {
    guard cityCount > 0 else { return 0 }
    let limit: Int
    switch cityCount {
    case ...12:
        limit = 3
    case ...30:
        limit = 4
    case ...48:
        limit = 6
    default:
        limit = 8
    }
    return min(cityCount, limit)
}
```

- [ ] **Step 4: Apply the longer timeout only to CAR Inc**

Change the CAR Inc call in `LiveRentalSearchService.search` to:

```swift
results.append(await platformResultWithTimeout(
    platform: .carInc,
    timeoutSeconds: liveZucheQueryTimeoutSeconds
) {
    await self.zucheClient.search(request: request)
})
```

Leave `EhiBridgeClient.search` unchanged so it continues using `livePlatformQueryTimeoutSeconds == 35` through the default parameter.

- [ ] **Step 5: Use dynamic concurrency in the city task group**

After planning cities, compute:

```swift
let cityQueryConcurrency = zucheCityQueryConcurrency(for: plannedCities.count)
```

Replace the initial task loop with:

```swift
for _ in 0..<cityQueryConcurrency {
    addNextCity(at: nextIndex)
    nextIndex += 1
}
```

Update the nearby comment to say the task group is capped by dynamic city-count tiers while request dispatch remains controlled by the shared throttle.

- [ ] **Step 6: Run focused tests and verify GREEN**

Run: `swift test --filter LiveRentalSearchServiceTests`

Expected: all focused tests pass, including tier boundaries, timeout separation, rate-limit retry, 60-city planning, Dezhou coverage, and exact vehicle filtering.

- [ ] **Step 7: Run broad verification**

Run: `swift test`

Expected: all test suites pass with no unexpected failures.

Run: `swift build`

Expected: build completes successfully.

Run: `git diff --check`

Expected: no whitespace errors.

- [ ] **Step 8: Commit dynamic CAR Inc scheduling**

```bash
git add Sources/CarRentalOptimizer/LiveRentalSearchService.swift Tests/CarRentalOptimizerTests/LiveRentalSearchServiceTests.swift docs/superpowers/plans/2026-07-14-specific-vehicle-timeout-recovery.md
git commit -m "fix: scale CAR Inc search scheduling"
```
