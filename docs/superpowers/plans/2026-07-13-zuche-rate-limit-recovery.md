# CAR Inc Rate-Limit Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent broad CAR Inc city searches from failing when the official gateway temporarily responds with “访问频繁，请稍后再试”.

**Architecture:** Add a small CAR Inc-specific actor that spaces high-fan-out city requests and shares a cooldown across all city tasks. Classify the gateway’s rate-limit response, retry it a bounded number of times with increasing cooldown, and lower only the city-query task-group concurrency while preserving the 60-city planning cap.

**Tech Stack:** Swift 5.9 package, Swift concurrency (`actor`, task groups, cancellation-aware `Task.sleep`), Foundation networking, Swift Testing.

## Global Constraints

- Keep `maxZucheVehicleSearchCityCount` at 60 so 500 km searches retain current coverage.
- Do not change eHi search, ranking, price calculation, login cookies, or CAR Inc confirmation-fee enrichment.
- Retry only gateway responses recognized as rate limiting; ordinary business, decoding, and non-retryable network errors must keep their current behavior.
- All waits must remain cancellation-aware so the existing platform-level timeout can stop the search.
- Do not add dependencies or change the macOS 14 minimum.

## File Structure

- Create `Sources/CarRentalOptimizer/ZucheRateLimit.swift`: rate-limit classification, shared request throttle, and bounded retry behavior.
- Modify `Sources/CarRentalOptimizer/LiveRentalSearchService.swift`: identify rate-limit envelopes and route only city `deptList`/`chooseCar` calls through one shared throttle.
- Modify `Tests/CarRentalOptimizerTests/LiveRentalSearchServiceTests.swift`: focused regression tests for classification, bounded retries, and city-search integration settings.

---

### Task 1: Rate-limit classification and bounded retry primitive

**Files:**
- Create: `Sources/CarRentalOptimizer/ZucheRateLimit.swift`
- Test: `Tests/CarRentalOptimizerTests/LiveRentalSearchServiceTests.swift`

**Interfaces:**
- Produces: `isZucheRateLimitMessage(_ message: String) -> Bool`
- Produces: `ZucheRateLimitError.init(message: String)` preserving the official error description.
- Produces: `ZucheRequestThrottle.init(minimumInterval: TimeInterval)` with `waitForPermit()` and `registerRateLimit(cooldown:)`.
- Produces: `withZucheRateLimitRetry(throttle:maxAttempts:baseCooldown:operation:) async throws -> T`.

- [ ] **Step 1: Write failing classifier and retry tests**

Add these tests after the existing CAR Inc transport retry test:

```swift
@Test("CAR Inc recognizes only gateway rate-limit messages")
func carIncRecognizesGatewayRateLimitMessages() {
    #expect(isZucheRateLimitMessage("访问频繁，请稍后再试"))
    #expect(isZucheRateLimitMessage("请求过于频繁"))
    #expect(!isZucheRateLimitMessage("当前条件没有可订车型"))
}

@Test("CAR Inc retries a temporary gateway rate limit")
func carIncRetriesTemporaryGatewayRateLimit() async throws {
    let throttle = ZucheRequestThrottle(minimumInterval: 0)
    var attempts = 0

    let value: String = try await withZucheRateLimitRetry(
        throttle: throttle,
        baseCooldown: 0
    ) {
        attempts += 1
        if attempts == 1 {
            throw ZucheRateLimitError(message: "访问频繁，请稍后再试")
        }
        return "success"
    }

    #expect(value == "success")
    #expect(attempts == 2)
}

@Test("CAR Inc stops retrying a persistent gateway rate limit")
func carIncStopsRetryingPersistentGatewayRateLimit() async {
    let throttle = ZucheRequestThrottle(minimumInterval: 0)
    var attempts = 0

    do {
        let _: String = try await withZucheRateLimitRetry(
            throttle: throttle,
            maxAttempts: 3,
            baseCooldown: 0
        ) {
            attempts += 1
            throw ZucheRateLimitError(message: "访问频繁，请稍后再试")
        }
        Issue.record("Expected the persistent rate limit to be returned")
    } catch let error as ZucheRateLimitError {
        #expect(error.localizedDescription == "访问频繁，请稍后再试")
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    #expect(attempts == 3)
}
```

- [ ] **Step 2: Run the focused suite and verify RED**

Run: `swift test --filter LiveRentalSearchServiceTests`

Expected: compilation fails because `isZucheRateLimitMessage`, `ZucheRateLimitError`, `ZucheRequestThrottle`, and `withZucheRateLimitRetry` do not exist.

- [ ] **Step 3: Implement the minimal rate-limit primitive**

Create `Sources/CarRentalOptimizer/ZucheRateLimit.swift`:

```swift
import Foundation

struct ZucheRateLimitError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

func isZucheRateLimitMessage(_ message: String) -> Bool {
    let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines)
    return normalized.contains("访问频繁") || normalized.contains("请求过于频繁")
}

actor ZucheRequestThrottle {
    private let minimumInterval: TimeInterval
    private var nextAllowedAt = Date.distantPast

    init(minimumInterval: TimeInterval) {
        self.minimumInterval = max(0, minimumInterval)
    }

    func waitForPermit() async throws {
        while true {
            try Task.checkCancellation()
            let now = Date()
            let wait = nextAllowedAt.timeIntervalSince(now)
            if wait <= 0 {
                nextAllowedAt = now.addingTimeInterval(minimumInterval)
                return
            }
            try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        }
    }

    func registerRateLimit(cooldown: TimeInterval) {
        let deadline = Date().addingTimeInterval(max(0, cooldown))
        if deadline > nextAllowedAt {
            nextAllowedAt = deadline
        }
    }
}

func withZucheRateLimitRetry<T>(
    throttle: ZucheRequestThrottle,
    maxAttempts: Int = 3,
    baseCooldown: TimeInterval = 0.75,
    operation: () async throws -> T
) async throws -> T {
    precondition(maxAttempts > 0)
    var attempt = 1

    while true {
        try await throttle.waitForPermit()
        do {
            return try await operation()
        } catch let error as ZucheRateLimitError {
            guard attempt < maxAttempts else { throw error }
            await throttle.registerRateLimit(cooldown: baseCooldown * Double(attempt))
            attempt += 1
        }
    }
}
```

- [ ] **Step 4: Run the focused suite and verify GREEN**

Run: `swift test --filter LiveRentalSearchServiceTests`

Expected: all `LiveRentalSearchServiceTests` tests pass.

- [ ] **Step 5: Commit the primitive**

```bash
git add Sources/CarRentalOptimizer/ZucheRateLimit.swift Tests/CarRentalOptimizerTests/LiveRentalSearchServiceTests.swift
git commit -m "fix: add CAR Inc rate-limit retry primitive"
```

---

### Task 2: Apply shared throttling to cross-city CAR Inc requests

**Files:**
- Modify: `Sources/CarRentalOptimizer/LiveRentalSearchService.swift:191-194, 425-492, 544-650`
- Test: `Tests/CarRentalOptimizerTests/LiveRentalSearchServiceTests.swift:229-246`

**Interfaces:**
- Consumes: `ZucheRequestThrottle` and `withZucheRateLimitRetry` from Task 1.
- Produces: internal `maxConcurrentZucheCityQueries == 3` for regression verification.
- Produces: `postCityGateway(uri:payload:throttle:)` as the only throttled path for city `deptList` and `chooseCar` requests.

- [ ] **Step 1: Write the failing city-integration test**

Add this test after the Task 1 tests:

```swift
@Test("CAR Inc city scans share conservative throttling without shrinking coverage")
func carIncCityScansShareConservativeThrottlingWithoutShrinkingCoverage() throws {
    let source = try liveRentalSearchServiceSource()

    #expect(maxConcurrentZucheCityQueries == 3)
    #expect(maxZucheVehicleSearchCityCount == 60)
    #expect(source.contains("ZucheRequestThrottle(minimumInterval: 0.12)"))
    #expect(source.contains("postCityGateway("))
    #expect(source.contains("throttle: requestThrottle"))
}
```

- [ ] **Step 2: Run the focused suite and verify RED**

Run: `swift test --filter LiveRentalSearchServiceTests`

Expected: compilation fails because `maxConcurrentZucheCityQueries` is private, and the source does not yet construct or pass a shared throttle.

- [ ] **Step 3: Recognize rate-limit envelopes**

In `postGateway(uri:payload:)`, replace the failed-envelope branch with:

```swift
guard envelope.code == 1 || envelope.status == "SUCCESS", let content = envelope.content else {
    let message = envelope.msg ?? "神州接口返回异常"
    if isZucheRateLimitMessage(message) {
        throw ZucheRateLimitError(message: message)
    }
    throw PlatformAPIError.message(message)
}
```

- [ ] **Step 4: Add one shared throttle to each search and lower bounded concurrency**

Change the constant to internal visibility and value 3:

```swift
let maxConcurrentZucheCityQueries = 3
```

After `plannedCities` is computed, construct one controller for the entire search:

```swift
let requestThrottle = ZucheRequestThrottle(minimumInterval: 0.12)
```

Pass `throttle: requestThrottle` into every `zucheCityQueryResult` task. Add the parameter to that method:

```swift
private func zucheCityQueryResult(
    city: ZucheCity,
    candidate: ZucheCandidateCity,
    request: SearchRequest,
    timeRange: PlatformQueryTimeRange,
    hasVehicleQuery: Bool,
    throttle: ZucheRequestThrottle
) async -> ZucheCityQueryResult
```

- [ ] **Step 5: Route only city fan-out calls through bounded retry**

Replace both `postGateway` calls inside `zucheCityQueryResult` with `postCityGateway`, passing the shared throttle. Add this method immediately before `postGateway`:

```swift
private func postCityGateway<Response: Decodable>(
    uri: String,
    payload: [String: Any],
    throttle: ZucheRequestThrottle
) async throws -> Response {
    try await withZucheRateLimitRetry(throttle: throttle) { [weak self] in
        guard let self else { throw CancellationError() }
        return try await self.postGateway(uri: uri, payload: payload)
    }
}
```

- [ ] **Step 6: Run focused tests and verify GREEN**

Run: `swift test --filter LiveRentalSearchServiceTests`

Expected: all focused tests pass, including the 60-city/Dezhou coverage regressions.

- [ ] **Step 7: Run broad verification**

Run: `swift test`

Expected: all test suites pass with no unexpected failures.

Run: `swift build`

Expected: build completes successfully.

Run: `git diff --check`

Expected: no whitespace errors.

- [ ] **Step 8: Commit the integration**

```bash
git add Sources/CarRentalOptimizer/LiveRentalSearchService.swift Tests/CarRentalOptimizerTests/LiveRentalSearchServiceTests.swift docs/superpowers/plans/2026-07-13-zuche-rate-limit-recovery.md
git commit -m "fix: throttle CAR Inc cross-city searches"
```
