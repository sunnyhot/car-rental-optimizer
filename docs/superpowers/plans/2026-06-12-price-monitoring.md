# Price Monitoring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build local price monitoring for selected rental plans, including scheduled official-price rechecks, price-drop alerts, and historical trend display.

**Architecture:** Add pure monitoring models and comparison rules to `CarRentalDomain`, then layer local JSON persistence, a foreground scheduler, optional notifications, and SwiftUI monitor-center views in `CarRentalOptimizer`. The scheduler reuses the existing official platform search provider and ranking flow, then stores snapshots and events locally.

**Tech Stack:** Swift 5.9 package, SwiftUI on macOS 14, Foundation JSON persistence, Swift Charts, UserNotifications, XCTest and Swift Testing.

---

## File Structure

- Create `Sources/CarRentalDomain/PriceMonitoring.swift`: monitor domain types, frequency calculation, drop-rule evaluation, trend summaries, historical labels.
- Create `Sources/CarRentalDomain/PriceMonitorMatching.swift`: listing signatures and monitor-to-recommendation matching.
- Create `Tests/CarRentalDomainTests/PriceMonitoringTests.swift`: unit tests for frequency, drop rules, trend summaries, pause behavior.
- Create `Tests/CarRentalDomainTests/PriceMonitorMatchingTests.swift`: unit tests for exact and fallback recommendation matching.
- Create `Sources/CarRentalOptimizer/MonitorStore.swift`: app-layer store protocol, JSON payload containers, file-location helpers.
- Create `Sources/CarRentalOptimizer/JSONMonitorStore.swift`: versioned local JSON implementation.
- Create `Tests/CarRentalOptimizerTests/MonitorStoreTests.swift`: JSON round-trip, append behavior, corrupt-file handling.
- Create `Sources/CarRentalOptimizer/MonitorScheduler.swift`: due-check orchestration, snapshot creation, event creation, next-check updates.
- Create `Tests/CarRentalOptimizerTests/MonitorSchedulerTests.swift`: fake-provider scheduler tests.
- Create `Sources/CarRentalOptimizer/MonitorNotificationService.swift`: in-app notification abstraction plus macOS notification sender.
- Create `Sources/CarRentalOptimizer/MonitorCenterViewModel.swift`: monitor-center state and commands.
- Create `Tests/CarRentalOptimizerTests/MonitorCenterViewModelTests.swift`: create, edit, pause, resume, trend view-state tests.
- Create `Sources/CarRentalOptimizer/CreateMonitorSheet.swift`: create/edit monitor form shared by result actions and monitor center.
- Create `Sources/CarRentalOptimizer/MonitorCenterView.swift`: monitor list, detail, trend chart, snapshots, events.
- Modify `Sources/CarRentalOptimizer/ContentView.swift`: construct and inject monitor view model.
- Modify `Sources/CarRentalOptimizer/MainView.swift`: add monitor-center entry in header and sheet presentation.
- Modify `Sources/CarRentalOptimizer/ResultPanelView.swift`: add row-level monitor action.
- Modify `Sources/CarRentalOptimizer/DetailPanelView.swift`: add detail-level monitor action.
- Modify `Sources/CarRentalOptimizer/App.swift`: add monitor-center menu command and notification permission command.
- Modify `Sources/CarRentalOptimizer/AppPresentation.swift`: add monitor-related display helpers.
- Modify `README.md` and `CHANGELOG.md` after implementation.

---

### Task 1: Domain Monitoring Rules

**Files:**
- Create: `Sources/CarRentalDomain/PriceMonitoring.swift`
- Test: `Tests/CarRentalDomainTests/PriceMonitoringTests.swift`

- [ ] **Step 1: Write failing domain tests**

Add `Tests/CarRentalDomainTests/PriceMonitoringTests.swift`:

```swift
import XCTest
@testable import CarRentalDomain

final class PriceMonitoringTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testSmartFrequencyUsesDailyWhenPickupIsMoreThanSevenDaysAway() {
        let now = date(2026, 6, 12, 10, 0)
        let pickup = date(2026, 6, 25, 10, 0)

        let next = MonitoringFrequency.smart.nextCheck(after: now, pickupAt: pickup, calendar: calendar)

        XCTAssertEqual(next, date(2026, 6, 13, 10, 0))
    }

    func testSmartFrequencyGetsMoreFrequentNearPickup() {
        let now = date(2026, 6, 12, 10, 0)

        XCTAssertEqual(
            MonitoringFrequency.smart.nextCheck(after: now, pickupAt: date(2026, 6, 18, 10, 0), calendar: calendar),
            date(2026, 6, 12, 13, 0)
        )
        XCTAssertEqual(
            MonitoringFrequency.smart.nextCheck(after: now, pickupAt: date(2026, 6, 14, 9, 0), calendar: calendar),
            date(2026, 6, 12, 11, 0)
        )
        XCTAssertEqual(
            MonitoringFrequency.smart.nextCheck(after: now, pickupAt: date(2026, 6, 12, 21, 0), calendar: calendar),
            date(2026, 6, 12, 10, 30)
        )
    }

    func testFixedFrequencyIntervals() {
        let now = date(2026, 6, 12, 10, 0)
        let pickup = date(2026, 6, 20, 10, 0)

        XCTAssertEqual(MonitoringFrequency.fixed30Minutes.nextCheck(after: now, pickupAt: pickup, calendar: calendar), date(2026, 6, 12, 10, 30))
        XCTAssertEqual(MonitoringFrequency.fixed1Hour.nextCheck(after: now, pickupAt: pickup, calendar: calendar), date(2026, 6, 12, 11, 0))
        XCTAssertEqual(MonitoringFrequency.fixed3Hours.nextCheck(after: now, pickupAt: pickup, calendar: calendar), date(2026, 6, 12, 13, 0))
        XCTAssertEqual(MonitoringFrequency.fixed1Day.nextCheck(after: now, pickupAt: pickup, calendar: calendar), date(2026, 6, 13, 10, 0))
    }

    func testFrequencyReturnsNilAfterPickupTime() {
        let now = date(2026, 6, 12, 10, 0)
        let pickup = date(2026, 6, 12, 9, 0)

        XCTAssertNil(MonitoringFrequency.smart.nextCheck(after: now, pickupAt: pickup, calendar: calendar))
        XCTAssertTrue(PriceMonitorStatus.active.shouldPauseAfterPickup(now: now, pickupAt: pickup))
    }

    func testDropRuleSupportsAnyAmountAndPercentThresholds() {
        XCTAssertTrue(PriceDropRule(notifyOnAnyDecrease: true).isSatisfied(previous: 500, current: 499))
        XCTAssertFalse(PriceDropRule(notifyOnAnyDecrease: true).isSatisfied(previous: 500, current: 500))
        XCTAssertTrue(PriceDropRule(minimumDropAmount: 20).isSatisfied(previous: 500, current: 480))
        XCTAssertFalse(PriceDropRule(minimumDropAmount: 20).isSatisfied(previous: 500, current: 481))
        XCTAssertTrue(PriceDropRule(minimumDropPercent: 0.05).isSatisfied(previous: 500, current: 475))
        XCTAssertFalse(PriceDropRule(minimumDropPercent: 0.05).isSatisfied(previous: 500, current: 476))
        XCTAssertTrue(PriceDropRule(notifyOnAnyDecrease: false, minimumDropAmount: 30, minimumDropPercent: 0.10).isSatisfied(previous: 500, current: 450))
    }

    func testTrendSummaryUsesSuccessfulSnapshotsOnly() {
        let monitorID = "monitor-1"
        let snapshots = [
            PriceSnapshot(id: "1", monitorID: monitorID, checkedAt: date(2026, 6, 12, 10, 0), status: .successful, platformRentalPrice: 500, recommendationTotalCost: 560, platform: .ehi, storeName: "通州店", vehicleName: "瑞虎8", message: "success"),
            PriceSnapshot(id: "2", monitorID: monitorID, checkedAt: date(2026, 6, 12, 11, 0), status: .networkFailed, message: "network failed"),
            PriceSnapshot(id: "3", monitorID: monitorID, checkedAt: date(2026, 6, 12, 12, 0), status: .successful, platformRentalPrice: 460, recommendationTotalCost: 530, platform: .ehi, storeName: "通州店", vehicleName: "瑞虎8", message: "success"),
        ]

        let summary = PriceTrendSummary(snapshots: snapshots)

        XCTAssertEqual(summary.validPoints.count, 2)
        XCTAssertEqual(summary.latestPlatformRentalPrice, 460)
        XCTAssertEqual(summary.previousPlatformRentalPrice, 500)
        XCTAssertEqual(summary.platformRentalDelta, -40)
        XCTAssertTrue(snapshots[0].isHistoricalSnapshot(comparedToLatestID: "3"))
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
swift test --filter PriceMonitoringTests
```

Expected: build fails with errors such as `cannot find 'MonitoringFrequency' in scope`.

- [ ] **Step 3: Add domain model implementation**

Create `Sources/CarRentalDomain/PriceMonitoring.swift`:

```swift
import Foundation

public enum PriceMonitorStatus: String, Codable, Equatable, CaseIterable {
    case active
    case paused
    case checking
    case needsAttention = "needs-attention"
    case expired

    public func shouldPauseAfterPickup(now: Date, pickupAt: Date) -> Bool {
        switch self {
        case .active, .checking, .needsAttention:
            return now >= pickupAt
        case .paused, .expired:
            return false
        }
    }
}

public enum MonitoringFrequency: String, Codable, Equatable, CaseIterable {
    case smart
    case fixed30Minutes = "fixed-30-minutes"
    case fixed1Hour = "fixed-1-hour"
    case fixed3Hours = "fixed-3-hours"
    case fixed1Day = "fixed-1-day"

    public func nextCheck(after checkedAt: Date, pickupAt: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> Date? {
        guard checkedAt < pickupAt else { return nil }
        let secondsUntilPickup = pickupAt.timeIntervalSince(checkedAt)
        let interval: TimeInterval

        switch self {
        case .smart:
            if secondsUntilPickup <= 12 * 60 * 60 {
                interval = 30 * 60
            } else if secondsUntilPickup <= 2 * 24 * 60 * 60 {
                interval = 60 * 60
            } else if secondsUntilPickup <= 7 * 24 * 60 * 60 {
                interval = 3 * 60 * 60
            } else {
                interval = 24 * 60 * 60
            }
        case .fixed30Minutes:
            interval = 30 * 60
        case .fixed1Hour:
            interval = 60 * 60
        case .fixed3Hours:
            interval = 3 * 60 * 60
        case .fixed1Day:
            interval = 24 * 60 * 60
        }

        return checkedAt.addingTimeInterval(interval)
    }
}

public struct PriceDropRule: Codable, Equatable {
    public var notifyOnAnyDecrease: Bool
    public var minimumDropAmount: Double?
    public var minimumDropPercent: Double?

    public init(
        notifyOnAnyDecrease: Bool = false,
        minimumDropAmount: Double? = nil,
        minimumDropPercent: Double? = nil
    ) {
        self.notifyOnAnyDecrease = notifyOnAnyDecrease
        self.minimumDropAmount = minimumDropAmount
        self.minimumDropPercent = minimumDropPercent
    }

    public static let defaultRule = PriceDropRule(notifyOnAnyDecrease: true)

    public func isSatisfied(previous: Double, current: Double) -> Bool {
        guard previous > 0, current < previous else { return false }
        let amountDrop = previous - current
        let percentDrop = amountDrop / previous

        if notifyOnAnyDecrease { return true }
        if let minimumDropAmount, amountDrop >= minimumDropAmount { return true }
        if let minimumDropPercent, percentDrop >= minimumDropPercent { return true }
        return false
    }
}

public struct ListingSignature: Codable, Equatable {
    public let platform: PlatformId
    public let storeID: String
    public let normalizedStoreName: String
    public let normalizedVehicleName: String
    public let normalizedVehicleClass: String

    public init(
        platform: PlatformId,
        storeID: String,
        normalizedStoreName: String,
        normalizedVehicleName: String,
        normalizedVehicleClass: String
    ) {
        self.platform = platform
        self.storeID = storeID
        self.normalizedStoreName = normalizedStoreName
        self.normalizedVehicleName = normalizedVehicleName
        self.normalizedVehicleClass = normalizedVehicleClass
    }
}

public struct PriceMonitor: Codable, Equatable, Identifiable {
    public let id: String
    public var name: String
    public var request: SearchRequest
    public var targetVehicleQuery: String
    public var targetPlatform: PlatformId?
    public var targetListingSignature: ListingSignature?
    public var frequency: MonitoringFrequency
    public var alertRule: PriceDropRule
    public var systemNotificationsEnabled: Bool
    public var status: PriceMonitorStatus
    public var createdAt: Date
    public var updatedAt: Date
    public var lastCheckedAt: Date?
    public var nextCheckAt: Date?

    public init(
        id: String,
        name: String,
        request: SearchRequest,
        targetVehicleQuery: String,
        targetPlatform: PlatformId? = nil,
        targetListingSignature: ListingSignature? = nil,
        frequency: MonitoringFrequency = .smart,
        alertRule: PriceDropRule = .defaultRule,
        systemNotificationsEnabled: Bool = false,
        status: PriceMonitorStatus = .active,
        createdAt: Date,
        updatedAt: Date,
        lastCheckedAt: Date? = nil,
        nextCheckAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.request = request
        self.targetVehicleQuery = targetVehicleQuery
        self.targetPlatform = targetPlatform
        self.targetListingSignature = targetListingSignature
        self.frequency = frequency
        self.alertRule = alertRule
        self.systemNotificationsEnabled = systemNotificationsEnabled
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastCheckedAt = lastCheckedAt
        self.nextCheckAt = nextCheckAt
    }
}

public enum PriceSnapshotStatus: String, Codable, Equatable {
    case successful
    case waitingForFirstCheck = "waiting-for-first-check"
    case noMatch = "no-match"
    case loginRequired = "login-required"
    case captchaRequired = "captcha-required"
    case unavailable
    case noCar = "no-car"
    case parseFailed = "parse-failed"
    case networkFailed = "network-failed"

    public var isSuccessful: Bool { self == .successful }
}

public struct PriceSnapshot: Codable, Equatable, Identifiable {
    public let id: String
    public let monitorID: String
    public let checkedAt: Date
    public let status: PriceSnapshotStatus
    public let platformRentalPrice: Double?
    public let recommendationTotalCost: Double?
    public let platform: PlatformId?
    public let storeName: String?
    public let vehicleName: String?
    public let dataCompleteness: Double?
    public let warnings: [ResultWarning]
    public let sourceURL: String?
    public let message: String

    public init(
        id: String,
        monitorID: String,
        checkedAt: Date,
        status: PriceSnapshotStatus,
        platformRentalPrice: Double? = nil,
        recommendationTotalCost: Double? = nil,
        platform: PlatformId? = nil,
        storeName: String? = nil,
        vehicleName: String? = nil,
        dataCompleteness: Double? = nil,
        warnings: [ResultWarning] = [],
        sourceURL: String? = nil,
        message: String
    ) {
        self.id = id
        self.monitorID = monitorID
        self.checkedAt = checkedAt
        self.status = status
        self.platformRentalPrice = platformRentalPrice
        self.recommendationTotalCost = recommendationTotalCost
        self.platform = platform
        self.storeName = storeName
        self.vehicleName = vehicleName
        self.dataCompleteness = dataCompleteness
        self.warnings = warnings
        self.sourceURL = sourceURL
        self.message = message
    }

    public func isHistoricalSnapshot(comparedToLatestID latestID: String?) -> Bool {
        guard status == .successful, let latestID else { return false }
        return id != latestID
    }
}

public enum PriceMonitorEventKind: String, Codable, Equatable {
    case priceDrop = "price-drop"
    case repeatedFailure = "repeated-failure"
    case recovered
    case pausedAfterPickup = "paused-after-pickup"
}

public struct PriceMonitorEvent: Codable, Equatable, Identifiable {
    public let id: String
    public let monitorID: String
    public let occurredAt: Date
    public let kind: PriceMonitorEventKind
    public let previousSnapshotID: String?
    public let currentSnapshotID: String?
    public let platformRentalDelta: Double?
    public let totalCostDelta: Double?
    public let message: String

    public init(
        id: String,
        monitorID: String,
        occurredAt: Date,
        kind: PriceMonitorEventKind,
        previousSnapshotID: String? = nil,
        currentSnapshotID: String? = nil,
        platformRentalDelta: Double? = nil,
        totalCostDelta: Double? = nil,
        message: String
    ) {
        self.id = id
        self.monitorID = monitorID
        self.occurredAt = occurredAt
        self.kind = kind
        self.previousSnapshotID = previousSnapshotID
        self.currentSnapshotID = currentSnapshotID
        self.platformRentalDelta = platformRentalDelta
        self.totalCostDelta = totalCostDelta
        self.message = message
    }
}

public struct PriceTrendSummary: Equatable {
    public let validPoints: [PriceSnapshot]
    public let latestPlatformRentalPrice: Double?
    public let previousPlatformRentalPrice: Double?
    public let platformRentalDelta: Double?

    public init(snapshots: [PriceSnapshot]) {
        self.validPoints = snapshots
            .filter { $0.status == .successful && $0.platformRentalPrice != nil }
            .sorted { $0.checkedAt < $1.checkedAt }
        self.latestPlatformRentalPrice = validPoints.last?.platformRentalPrice
        self.previousPlatformRentalPrice = validPoints.dropLast().last?.platformRentalPrice
        if let latestPlatformRentalPrice, let previousPlatformRentalPrice {
            self.platformRentalDelta = latestPlatformRentalPrice - previousPlatformRentalPrice
        } else {
            self.platformRentalDelta = nil
        }
    }
}
```

- [ ] **Step 4: Run tests to verify Task 1 passes**

Run:

```bash
swift test --filter PriceMonitoringTests
```

Expected: `PriceMonitoringTests` passes.

- [ ] **Step 5: Commit Task 1**

```bash
git add Sources/CarRentalDomain/PriceMonitoring.swift Tests/CarRentalDomainTests/PriceMonitoringTests.swift
git commit -m "Add price monitor domain rules"
```

---

### Task 2: Recommendation Matching For Monitors

**Files:**
- Create: `Sources/CarRentalDomain/PriceMonitorMatching.swift`
- Modify: `Sources/CarRentalDomain/PriceMonitoring.swift`
- Test: `Tests/CarRentalDomainTests/PriceMonitorMatchingTests.swift`

- [ ] **Step 1: Write failing matching tests**

Add `Tests/CarRentalDomainTests/PriceMonitorMatchingTests.swift`:

```swift
import XCTest
@testable import CarRentalDomain

final class PriceMonitorMatchingTests: XCTestCase {
    func testExactSignatureMatchWins() {
        let original = recommendation(id: "original", platform: .ehi, storeID: "store-a", storeName: "一嗨通州万达店", vehicleName: "奇瑞 瑞虎8")
        let other = recommendation(id: "other", platform: .carInc, storeID: "store-b", storeName: "神州通州店", vehicleName: "奇瑞 瑞虎8")
        let signature = ListingSignature(recommendation: original)

        let selected = selectMonitoredRecommendation(from: [other, original], signature: signature, targetVehicleQuery: "瑞虎8", targetPlatform: .ehi)

        XCTAssertEqual(selected?.id, "original")
    }

    func testFallsBackToSamePlatformVehicleWhenStoreChanges() {
        let oldStore = recommendation(id: "old", platform: .ehi, storeID: "store-a", storeName: "一嗨通州万达店", vehicleName: "奇瑞 瑞虎8")
        let newStore = recommendation(id: "new", platform: .ehi, storeID: "store-c", storeName: "一嗨北苑店", vehicleName: "奇瑞瑞虎8")
        let crossPlatform = recommendation(id: "cross", platform: .carInc, storeID: "store-d", storeName: "神州门店", vehicleName: "奇瑞 瑞虎8")

        let selected = selectMonitoredRecommendation(from: [crossPlatform, newStore], signature: ListingSignature(recommendation: oldStore), targetVehicleQuery: "瑞虎8", targetPlatform: .ehi)

        XCTAssertEqual(selected?.id, "new")
    }

    func testFallsBackAcrossPlatformsForSameVehicle() {
        let original = recommendation(id: "original", platform: .ehi, storeID: "store-a", storeName: "一嗨通州万达店", vehicleName: "奇瑞 瑞虎8")
        let crossPlatform = recommendation(id: "cross", platform: .carInc, storeID: "store-d", storeName: "神州门店", vehicleName: "奇瑞 瑞虎8")

        let selected = selectMonitoredRecommendation(from: [crossPlatform], signature: ListingSignature(recommendation: original), targetVehicleQuery: "瑞虎8", targetPlatform: .ehi)

        XCTAssertEqual(selected?.id, "cross")
    }

    func testManualMonitorUsesRankedRecommendationForTargetQuery() {
        let tiger = recommendation(id: "tiger", platform: .ehi, storeID: "store-a", storeName: "一嗨店", vehicleName: "奇瑞 瑞虎8")
        let h6 = recommendation(id: "h6", platform: .ehi, storeID: "store-b", storeName: "一嗨店", vehicleName: "哈弗 H6")

        let selected = selectMonitoredRecommendation(from: [h6, tiger], signature: nil, targetVehicleQuery: "瑞虎8", targetPlatform: nil)

        XCTAssertEqual(selected?.id, "tiger")
    }

    private func recommendation(
        id: String,
        platform: PlatformId,
        storeID: String,
        storeName: String,
        vehicleName: String
    ) -> Recommendation {
        let store = Store(
            id: storeID,
            platform: platform,
            name: storeName,
            city: "北京",
            address: "北京市通州区",
            location: GeoPoint(lat: 39.91, lng: 116.65),
            distanceKm: 5,
            hours: "08:00-22:00"
        )
        let listing = RentalListing(
            id: id,
            platform: platform,
            store: store,
            vehicleName: vehicleName,
            vehicleClass: "SUV",
            basePrice: 300,
            platformFees: 0,
            insuranceFees: 0,
            oneWayFee: 0,
            sourceUrl: "https://example.com",
            dataCompleteness: 0.9
        )
        return buildRecommendation(
            listing: listing,
            match: VehicleMatch(kind: .exact, score: 1, label: "精确匹配"),
            taxiRoute: RouteEstimate(mode: .taxi, cost: 40, durationMinutes: 20, distanceKm: 5, summary: "打车"),
            transitRoute: RouteEstimate(mode: .transit, cost: 6, durationMinutes: 40, distanceKm: 5, summary: "公交")
        )
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
swift test --filter PriceMonitorMatchingTests
```

Expected: build fails with errors such as `cannot find 'ListingSignature' in scope`.

- [ ] **Step 3: Add matching implementation**

Create `Sources/CarRentalDomain/PriceMonitorMatching.swift`:

```swift
import Foundation

public extension ListingSignature {
    public init(recommendation: Recommendation) {
        self.init(
            platform: recommendation.listing.platform,
            storeID: recommendation.listing.store.id,
            normalizedStoreName: normalizeMonitorToken(recommendation.listing.store.name + recommendation.listing.store.address),
            normalizedVehicleName: normalizeMonitorToken(recommendation.listing.vehicleName),
            normalizedVehicleClass: normalizeMonitorToken(recommendation.listing.vehicleClass)
        )
    }

    public func exactMatch(_ recommendation: Recommendation) -> Bool {
        recommendation.listing.platform == platform
            && recommendation.listing.store.id == storeID
            && normalizeMonitorToken(recommendation.listing.vehicleName) == normalizedVehicleName
    }

    public func samePlatformVehicle(_ recommendation: Recommendation) -> Bool {
        recommendation.listing.platform == platform
            && normalizeMonitorToken(recommendation.listing.vehicleName) == normalizedVehicleName
    }

    public func sameVehicle(_ recommendation: Recommendation) -> Bool {
        normalizeMonitorToken(recommendation.listing.vehicleName) == normalizedVehicleName
    }
}

public func selectMonitoredRecommendation(
    from recommendations: [Recommendation],
    signature: ListingSignature?,
    targetVehicleQuery: String,
    targetPlatform: PlatformId?
) -> Recommendation? {
    let ranked = rankRecommendations(recommendations)

    if let signature {
        if let exact = ranked.first(where: { signature.exactMatch($0) }) {
            return exact
        }
        if let samePlatformVehicle = ranked.first(where: { signature.samePlatformVehicle($0) }) {
            return samePlatformVehicle
        }
        if let sameVehicle = ranked.first(where: { signature.sameVehicle($0) }) {
            return sameVehicle
        }
    }

    let normalizedQuery = normalizeMonitorToken(targetVehicleQuery)
    let platformFiltered = targetPlatform.map { platform in ranked.filter { $0.listing.platform == platform } } ?? ranked
    if let queryMatch = platformFiltered.first(where: { normalizeMonitorToken($0.listing.vehicleName).contains(normalizedQuery) || normalizedQuery.contains(normalizeMonitorToken($0.listing.vehicleName)) }) {
        return queryMatch
    }
    return platformFiltered.first
}

public func normalizeMonitorToken(_ value: String) -> String {
    value
        .lowercased()
        .replacingOccurrences(of: " ", with: "")
        .replacingOccurrences(of: "　", with: "")
        .replacingOccurrences(of: "·", with: "")
        .replacingOccurrences(of: "-", with: "")
        .replacingOccurrences(of: "_", with: "")
        .replacingOccurrences(of: "/", with: "")
        .replacingOccurrences(of: "（", with: "(")
        .replacingOccurrences(of: "）", with: ")")
}
```

- [ ] **Step 4: Run matching tests**

Run:

```bash
swift test --filter PriceMonitorMatchingTests
```

Expected: `PriceMonitorMatchingTests` passes.

- [ ] **Step 5: Run all domain tests**

Run:

```bash
swift test --filter CarRentalDomainTests
```

Expected: all domain tests pass.

- [ ] **Step 6: Commit Task 2**

```bash
git add Sources/CarRentalDomain/PriceMonitorMatching.swift Sources/CarRentalDomain/PriceMonitoring.swift Tests/CarRentalDomainTests/PriceMonitorMatchingTests.swift
git commit -m "Add monitor recommendation matching"
```

---

### Task 3: Local JSON Monitor Store

**Files:**
- Create: `Sources/CarRentalOptimizer/MonitorStore.swift`
- Create: `Sources/CarRentalOptimizer/JSONMonitorStore.swift`
- Test: `Tests/CarRentalOptimizerTests/MonitorStoreTests.swift`

- [ ] **Step 1: Write failing store tests**

Add `Tests/CarRentalOptimizerTests/MonitorStoreTests.swift`:

```swift
import CarRentalDomain
import Foundation
import SwiftUI
import Testing
@testable import CarRentalOptimizer

@Suite("JSONMonitorStore")
struct MonitorStoreTests {
    @Test("Store round trips monitors snapshots and events")
    func storeRoundTripsMonitorsSnapshotsAndEvents() async throws {
        let directory = temporaryDirectory()
        let store = JSONMonitorStore(directory: directory)
        let monitor = makeMonitor(id: "monitor-1")
        let snapshot = PriceSnapshot(id: "snapshot-1", monitorID: monitor.id, checkedAt: Date(timeIntervalSince1970: 100), status: .successful, platformRentalPrice: 400, recommendationTotalCost: 450, platform: .ehi, storeName: "通州店", vehicleName: "瑞虎8", message: "success")
        let event = PriceMonitorEvent(id: "event-1", monitorID: monitor.id, occurredAt: Date(timeIntervalSince1970: 200), kind: .priceDrop, previousSnapshotID: "snapshot-0", currentSnapshotID: snapshot.id, platformRentalDelta: -30, totalCostDelta: -20, message: "降价 ¥30")

        try await store.saveMonitor(monitor)
        try await store.appendSnapshot(snapshot)
        try await store.appendEvent(event)

        #expect(try await store.listMonitors() == [monitor])
        #expect(try await store.snapshots(for: monitor.id) == [snapshot])
        #expect(try await store.events(for: monitor.id) == [event])
    }

    @Test("Store updates monitor status without dropping snapshots")
    func storeUpdatesMonitorStatusWithoutDroppingSnapshots() async throws {
        let directory = temporaryDirectory()
        let store = JSONMonitorStore(directory: directory)
        let monitor = makeMonitor(id: "monitor-1")
        let snapshot = PriceSnapshot(id: "snapshot-1", monitorID: monitor.id, checkedAt: Date(timeIntervalSince1970: 100), status: .networkFailed, message: "network")

        try await store.saveMonitor(monitor)
        try await store.appendSnapshot(snapshot)
        try await store.markMonitorStatus(id: monitor.id, status: .needsAttention, updatedAt: Date(timeIntervalSince1970: 300))

        let updated = try await store.listMonitors().first
        #expect(updated?.status == .needsAttention)
        #expect(try await store.snapshots(for: monitor.id) == [snapshot])
    }

    @Test("Store surfaces corrupt JSON")
    func storeSurfacesCorruptJSON() async throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: directory.appendingPathComponent("monitors.json"))
        let store = JSONMonitorStore(directory: directory)

        do {
            _ = try await store.listMonitors()
            Issue.record("Expected corrupt JSON to throw")
        } catch MonitorStoreError.corruptFile(let url) {
            #expect(url.lastPathComponent == "monitors.json")
        }
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MonitorStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func makeMonitor(id: String) -> PriceMonitor {
        PriceMonitor(
            id: id,
            name: "瑞虎8 北京监控",
            request: AppDefaults.searchRequest,
            targetVehicleQuery: "瑞虎8",
            frequency: .smart,
            alertRule: .defaultRule,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
swift test --filter MonitorStoreTests
```

Expected: build fails with errors such as `cannot find 'JSONMonitorStore' in scope`.

- [ ] **Step 3: Add store protocol and errors**

Create `Sources/CarRentalOptimizer/MonitorStore.swift`:

```swift
import CarRentalDomain
import Foundation

protocol MonitorStoring {
    func listMonitors() async throws -> [PriceMonitor]
    func saveMonitor(_ monitor: PriceMonitor) async throws
    func deleteMonitor(id: String) async throws
    func appendSnapshot(_ snapshot: PriceSnapshot) async throws
    func snapshots(for monitorID: String) async throws -> [PriceSnapshot]
    func appendEvent(_ event: PriceMonitorEvent) async throws
    func events(for monitorID: String) async throws -> [PriceMonitorEvent]
    func markMonitorStatus(id: String, status: PriceMonitorStatus, updatedAt: Date) async throws
}

enum MonitorStoreError: Error, Equatable {
    case corruptFile(URL)
    case monitorNotFound(String)
}

struct MonitorStoreFiles {
    let directory: URL

    var monitorsURL: URL { directory.appendingPathComponent("monitors.json") }
    var snapshotsURL: URL { directory.appendingPathComponent("price-snapshots.json") }
    var eventsURL: URL { directory.appendingPathComponent("monitor-events.json") }

    static func applicationSupportDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appendingPathComponent("CarRentalOptimizer", isDirectory: true)
    }
}

struct VersionedMonitorPayload<Value: Codable>: Codable {
    var version: Int
    var values: [Value]

    init(version: Int = 1, values: [Value]) {
        self.version = version
        self.values = values
    }
}
```

- [ ] **Step 4: Add JSON implementation**

Create `Sources/CarRentalOptimizer/JSONMonitorStore.swift`:

```swift
import CarRentalDomain
import Foundation

actor JSONMonitorStore: MonitorStoring {
    private let files: MonitorStoreFiles
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(directory: URL) {
        self.files = MonitorStoreFiles(directory: directory)
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    static func live() throws -> JSONMonitorStore {
        try JSONMonitorStore(directory: MonitorStoreFiles.applicationSupportDirectory())
    }

    func listMonitors() async throws -> [PriceMonitor] {
        try readPayload(from: files.monitorsURL, as: PriceMonitor.self).sorted { $0.createdAt < $1.createdAt }
    }

    func saveMonitor(_ monitor: PriceMonitor) async throws {
        var monitors = try await listMonitors()
        if let index = monitors.firstIndex(where: { $0.id == monitor.id }) {
            monitors[index] = monitor
        } else {
            monitors.append(monitor)
        }
        try writePayload(monitors, to: files.monitorsURL)
    }

    func deleteMonitor(id: String) async throws {
        let monitors = try await listMonitors().filter { $0.id != id }
        let snapshots = try readPayload(from: files.snapshotsURL, as: PriceSnapshot.self).filter { $0.monitorID != id }
        let events = try readPayload(from: files.eventsURL, as: PriceMonitorEvent.self).filter { $0.monitorID != id }
        try writePayload(monitors, to: files.monitorsURL)
        try writePayload(snapshots, to: files.snapshotsURL)
        try writePayload(events, to: files.eventsURL)
    }

    func appendSnapshot(_ snapshot: PriceSnapshot) async throws {
        var snapshots = try readPayload(from: files.snapshotsURL, as: PriceSnapshot.self)
        snapshots.append(snapshot)
        try writePayload(snapshots, to: files.snapshotsURL)
    }

    func snapshots(for monitorID: String) async throws -> [PriceSnapshot] {
        try readPayload(from: files.snapshotsURL, as: PriceSnapshot.self)
            .filter { $0.monitorID == monitorID }
            .sorted { $0.checkedAt < $1.checkedAt }
    }

    func appendEvent(_ event: PriceMonitorEvent) async throws {
        var events = try readPayload(from: files.eventsURL, as: PriceMonitorEvent.self)
        events.append(event)
        try writePayload(events, to: files.eventsURL)
    }

    func events(for monitorID: String) async throws -> [PriceMonitorEvent] {
        try readPayload(from: files.eventsURL, as: PriceMonitorEvent.self)
            .filter { $0.monitorID == monitorID }
            .sorted { $0.occurredAt < $1.occurredAt }
    }

    func markMonitorStatus(id: String, status: PriceMonitorStatus, updatedAt: Date) async throws {
        var monitors = try await listMonitors()
        guard let index = monitors.firstIndex(where: { $0.id == id }) else {
            throw MonitorStoreError.monitorNotFound(id)
        }
        monitors[index].status = status
        monitors[index].updatedAt = updatedAt
        try writePayload(monitors, to: files.monitorsURL)
    }

    private func readPayload<Value: Codable>(from url: URL, as type: Value.Type) throws -> [Value] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(VersionedMonitorPayload<Value>.self, from: data).values
        } catch {
            throw MonitorStoreError.corruptFile(url)
        }
    }

    private func writePayload<Value: Codable>(_ values: [Value], to url: URL) throws {
        try FileManager.default.createDirectory(at: files.directory, withIntermediateDirectories: true)
        let data = try encoder.encode(VersionedMonitorPayload(values: values))
        let temporaryURL = url.appendingPathExtension("tmp-\(UUID().uuidString)")
        try data.write(to: temporaryURL, options: .atomic)
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporaryURL)
        } else {
            try FileManager.default.moveItem(at: temporaryURL, to: url)
        }
    }
}
```

- [ ] **Step 5: Run store tests**

Run:

```bash
swift test --filter MonitorStoreTests
```

Expected: `JSONMonitorStore` tests pass.

- [ ] **Step 6: Commit Task 3**

```bash
git add Sources/CarRentalOptimizer/MonitorStore.swift Sources/CarRentalOptimizer/JSONMonitorStore.swift Tests/CarRentalOptimizerTests/MonitorStoreTests.swift
git commit -m "Add local monitor JSON store"
```

---

### Task 4: Monitor Scheduler And Snapshot Creation

**Files:**
- Create: `Sources/CarRentalOptimizer/MonitorScheduler.swift`
- Create: `Sources/CarRentalOptimizer/MonitorNotificationService.swift`
- Test: `Tests/CarRentalOptimizerTests/MonitorSchedulerTests.swift`

- [ ] **Step 1: Write failing scheduler tests**

Add `Tests/CarRentalOptimizerTests/MonitorSchedulerTests.swift`:

```swift
import CarRentalDomain
import Foundation
import Testing
@testable import CarRentalOptimizer

@Suite("MonitorScheduler")
@MainActor
struct MonitorSchedulerTests {
    @Test("Due successful check appends snapshot and price drop event")
    func dueSuccessfulCheckAppendsSnapshotAndPriceDropEvent() async throws {
        let store = InMemoryMonitorStore()
        let monitor = makeMonitor(nextCheckAt: Date(timeIntervalSince1970: 100))
        try await store.saveMonitor(monitor)
        try await store.appendSnapshot(successSnapshot(id: "old", monitorID: monitor.id, price: 500, total: 560))
        let scheduler = MonitorScheduler(
            store: store,
            searchProvider: StubRentalSearchProvider(results: [readyResult(price: 450)]),
            mapService: EstimatedMapService(),
            notificationService: RecordingNotificationService(),
            now: { Date(timeIntervalSince1970: 200) },
            idGenerator: IncrementingIDGenerator()
        )

        try await scheduler.runDueChecks()

        let snapshots = try await store.snapshots(for: monitor.id)
        let events = try await store.events(for: monitor.id)
        #expect(snapshots.count == 2)
        #expect(snapshots.last?.platformRentalPrice == 450)
        #expect(events.count == 1)
        #expect(events.first?.kind == .priceDrop)
        #expect(events.first?.platformRentalDelta == -50)
    }

    @Test("Unchanged price does not create event")
    func unchangedPriceDoesNotCreateEvent() async throws {
        let store = InMemoryMonitorStore()
        let monitor = makeMonitor(nextCheckAt: Date(timeIntervalSince1970: 100))
        try await store.saveMonitor(monitor)
        try await store.appendSnapshot(successSnapshot(id: "old", monitorID: monitor.id, price: 500, total: 560))
        let scheduler = MonitorScheduler(
            store: store,
            searchProvider: StubRentalSearchProvider(results: [readyResult(price: 500)]),
            mapService: EstimatedMapService(),
            notificationService: RecordingNotificationService(),
            now: { Date(timeIntervalSince1970: 200) },
            idGenerator: IncrementingIDGenerator()
        )

        try await scheduler.runDueChecks()

        #expect(try await store.events(for: monitor.id).isEmpty)
    }

    @Test("Login required appends failure snapshot without event")
    func loginRequiredAppendsFailureSnapshotWithoutEvent() async throws {
        let store = InMemoryMonitorStore()
        let monitor = makeMonitor(nextCheckAt: Date(timeIntervalSince1970: 100))
        try await store.saveMonitor(monitor)
        let scheduler = MonitorScheduler(
            store: store,
            searchProvider: StubRentalSearchProvider(results: [
                PlatformEvidenceResult(
                    platform: .ehi,
                    status: PlatformEvidenceStatus(platform: .ehi, kind: .loginRequired, message: "一嗨需要登录。", sourceUrl: "https://booking.1hai.cn/"),
                    listings: []
                )
            ]),
            mapService: EstimatedMapService(),
            notificationService: RecordingNotificationService(),
            now: { Date(timeIntervalSince1970: 200) },
            idGenerator: IncrementingIDGenerator()
        )

        try await scheduler.runDueChecks()

        let snapshots = try await store.snapshots(for: monitor.id)
        #expect(snapshots.last?.status == .loginRequired)
        #expect(try await store.events(for: monitor.id).isEmpty)
    }

    private func makeMonitor(nextCheckAt: Date) -> PriceMonitor {
        PriceMonitor(
            id: "monitor-1",
            name: "瑞虎8",
            request: AppDefaults.searchRequest,
            targetVehicleQuery: "瑞虎8",
            frequency: .fixed1Hour,
            alertRule: .defaultRule,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            nextCheckAt: nextCheckAt
        )
    }

    private func readyResult(price: Double) -> PlatformEvidenceResult {
        PlatformEvidenceResult(
            platform: .ehi,
            status: PlatformEvidenceStatus(platform: .ehi, kind: .ready, message: "ready", sourceUrl: "https://booking.1hai.cn/"),
            listings: [RentalListing(
                id: "listing-\(Int(price))",
                platform: .ehi,
                store: Store(id: "store-1", platform: .ehi, name: "一嗨通州店", city: "北京", address: "通州", location: AppDefaults.searchRequest.origin, distanceKm: 2, hours: "08:00-22:00"),
                vehicleName: "奇瑞 瑞虎8",
                vehicleClass: "SUV",
                basePrice: price,
                platformFees: 0,
                insuranceFees: 0,
                oneWayFee: 0,
                sourceUrl: "https://booking.1hai.cn/",
                dataCompleteness: 0.9
            )]
        )
    }

    private func successSnapshot(id: String, monitorID: String, price: Double, total: Double) -> PriceSnapshot {
        PriceSnapshot(id: id, monitorID: monitorID, checkedAt: Date(timeIntervalSince1970: 50), status: .successful, platformRentalPrice: price, recommendationTotalCost: total, platform: .ehi, storeName: "一嗨通州店", vehicleName: "奇瑞 瑞虎8", message: "success")
    }
}
```

In the same test file, add fakes:

```swift
private actor InMemoryMonitorStore: MonitorStoring {
    private var monitors: [PriceMonitor] = []
    private var snapshotsByMonitor: [String: [PriceSnapshot]] = [:]
    private var eventsByMonitor: [String: [PriceMonitorEvent]] = [:]

    func listMonitors() async throws -> [PriceMonitor] { monitors }
    func saveMonitor(_ monitor: PriceMonitor) async throws {
        if let index = monitors.firstIndex(where: { $0.id == monitor.id }) {
            monitors[index] = monitor
        } else {
            monitors.append(monitor)
        }
    }
    func deleteMonitor(id: String) async throws { monitors.removeAll { $0.id == id } }
    func appendSnapshot(_ snapshot: PriceSnapshot) async throws { snapshotsByMonitor[snapshot.monitorID, default: []].append(snapshot) }
    func snapshots(for monitorID: String) async throws -> [PriceSnapshot] { snapshotsByMonitor[monitorID, default: []] }
    func appendEvent(_ event: PriceMonitorEvent) async throws { eventsByMonitor[event.monitorID, default: []].append(event) }
    func events(for monitorID: String) async throws -> [PriceMonitorEvent] { eventsByMonitor[monitorID, default: []] }
    func markMonitorStatus(id: String, status: PriceMonitorStatus, updatedAt: Date) async throws {
        guard let index = monitors.firstIndex(where: { $0.id == id }) else { return }
        monitors[index].status = status
        monitors[index].updatedAt = updatedAt
    }
}

private struct StubRentalSearchProvider: RentalSearchProviding {
    let results: [PlatformEvidenceResult]
    func search(request: SearchRequest) async -> [PlatformEvidenceResult] { results }
}

private final class RecordingNotificationService: MonitorNotificationSending {
    private(set) var sentEvents: [PriceMonitorEvent] = []
    func sendPriceDropNotification(monitor: PriceMonitor, event: PriceMonitorEvent) async {
        sentEvents.append(event)
    }
}

private struct IncrementingIDGenerator: MonitorIDGenerating {
    private final class Box { var value = 0 }
    private let box = Box()
    func nextID(prefix: String) -> String {
        box.value += 1
        return "\(prefix)-\(box.value)"
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
swift test --filter MonitorScheduler
```

Expected: build fails with missing `MonitorScheduler`, `MonitorNotificationSending`, and `MonitorIDGenerating`.

- [ ] **Step 3: Add notification abstraction**

Create `Sources/CarRentalOptimizer/MonitorNotificationService.swift`:

```swift
import CarRentalDomain
import Foundation
import UserNotifications

protocol MonitorNotificationSending: AnyObject {
    func sendPriceDropNotification(monitor: PriceMonitor, event: PriceMonitorEvent) async
}

final class NoopMonitorNotificationService: MonitorNotificationSending {
    func sendPriceDropNotification(monitor: PriceMonitor, event: PriceMonitorEvent) async {}
}

final class UserNotificationMonitorService: MonitorNotificationSending {
    func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    func sendPriceDropNotification(monitor: PriceMonitor, event: PriceMonitorEvent) async {
        guard monitor.systemNotificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "租车价格下降"
        content.body = event.message
        content.sound = .default
        content.userInfo = ["monitorID": monitor.id]
        let request = UNNotificationRequest(identifier: event.id, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
```

- [ ] **Step 4: Add scheduler implementation**

Create `Sources/CarRentalOptimizer/MonitorScheduler.swift`:

```swift
import CarRentalDomain
import Foundation

protocol MonitorIDGenerating {
    func nextID(prefix: String) -> String
}

struct UUIDMonitorIDGenerator: MonitorIDGenerating {
    func nextID(prefix: String) -> String {
        "\(prefix)-\(UUID().uuidString)"
    }
}

@MainActor
final class MonitorScheduler {
    private let store: MonitorStoring
    private let searchProvider: RentalSearchProviding
    private let mapService: MapService
    private let notificationService: MonitorNotificationSending
    private let now: () -> Date
    private let idGenerator: MonitorIDGenerating
    private var runningMonitorIDs = Set<String>()

    init(
        store: MonitorStoring,
        searchProvider: RentalSearchProviding,
        mapService: MapService,
        notificationService: MonitorNotificationSending,
        now: @escaping () -> Date = Date.init,
        idGenerator: MonitorIDGenerating = UUIDMonitorIDGenerator()
    ) {
        self.store = store
        self.searchProvider = searchProvider
        self.mapService = mapService
        self.notificationService = notificationService
        self.now = now
        self.idGenerator = idGenerator
    }

    func runDueChecks(limit: Int = 2) async throws {
        let currentTime = now()
        let dueMonitors = try await store.listMonitors()
            .filter { $0.status == .active || $0.status == .needsAttention }
            .filter { ($0.nextCheckAt ?? $0.createdAt) <= currentTime }
            .prefix(limit)

        for monitor in dueMonitors where !runningMonitorIDs.contains(monitor.id) {
            runningMonitorIDs.insert(monitor.id)
            defer { runningMonitorIDs.remove(monitor.id) }
            try await runCheck(for: monitor, at: currentTime)
        }
    }

    private func runCheck(for monitor: PriceMonitor, at checkedAt: Date) async throws {
        if let pickupAt = AppDateRules.parseRequestDate(monitor.request.pickupAt), monitor.status.shouldPauseAfterPickup(now: checkedAt, pickupAt: pickupAt) {
            try await store.markMonitorStatus(id: monitor.id, status: .expired, updatedAt: checkedAt)
            try await store.appendEvent(PriceMonitorEvent(
                id: idGenerator.nextID(prefix: "event"),
                monitorID: monitor.id,
                occurredAt: checkedAt,
                kind: .pausedAfterPickup,
                message: "取车时间已过，监控已自动暂停。"
            ))
            return
        }

        try await store.markMonitorStatus(id: monitor.id, status: .checking, updatedAt: checkedAt)
        let evidenceResults = await searchProvider.search(request: monitor.request)
        let listings = evidenceResults.flatMap(\.listings)
        let snapshot: PriceSnapshot

        if listings.isEmpty {
            snapshot = failureSnapshot(for: monitor, evidenceResults: evidenceResults, checkedAt: checkedAt)
        } else {
            let recommendations = await rankRentalListings(request: monitor.request, listings: listings, mapService: mapService)
            if let selected = selectMonitoredRecommendation(
                from: recommendations,
                signature: monitor.targetListingSignature,
                targetVehicleQuery: monitor.targetVehicleQuery,
                targetPlatform: monitor.targetPlatform
            ) {
                snapshot = successSnapshot(for: monitor, recommendation: selected, checkedAt: checkedAt)
            } else {
                snapshot = PriceSnapshot(
                    id: idGenerator.nextID(prefix: "snapshot"),
                    monitorID: monitor.id,
                    checkedAt: checkedAt,
                    status: .noMatch,
                    message: "本次查询没有找到匹配的监控车型。"
                )
            }
        }

        let previousSnapshots = try await store.snapshots(for: monitor.id)
        try await store.appendSnapshot(snapshot)
        if let event = makePriceDropEvent(monitor: monitor, previousSnapshots: previousSnapshots, currentSnapshot: snapshot, checkedAt: checkedAt) {
            try await store.appendEvent(event)
            await notificationService.sendPriceDropNotification(monitor: monitor, event: event)
        }

        var updated = monitor
        updated.status = snapshot.status == .successful ? .active : .needsAttention
        updated.lastCheckedAt = checkedAt
        if let pickupAt = AppDateRules.parseRequestDate(monitor.request.pickupAt) {
            updated.nextCheckAt = monitor.frequency.nextCheck(after: checkedAt, pickupAt: pickupAt)
            if updated.nextCheckAt == nil { updated.status = .expired }
        }
        updated.updatedAt = checkedAt
        try await store.saveMonitor(updated)
    }

    private func successSnapshot(for monitor: PriceMonitor, recommendation: Recommendation, checkedAt: Date) -> PriceSnapshot {
        PriceSnapshot(
            id: idGenerator.nextID(prefix: "snapshot"),
            monitorID: monitor.id,
            checkedAt: checkedAt,
            status: .successful,
            platformRentalPrice: recommendation.rentalTotal,
            recommendationTotalCost: recommendation.bestTotal,
            platform: recommendation.listing.platform,
            storeName: recommendation.listing.store.name,
            vehicleName: recommendation.listing.vehicleName,
            dataCompleteness: recommendation.listing.dataCompleteness,
            warnings: recommendation.warnings,
            sourceURL: recommendation.listing.sourceUrl,
            message: "已记录本次官方报价。"
        )
    }

    private func failureSnapshot(for monitor: PriceMonitor, evidenceResults: [PlatformEvidenceResult], checkedAt: Date) -> PriceSnapshot {
        let status = evidenceResults.map(\.status).first ?? PlatformEvidenceStatus(platform: .ehi, kind: .parseFailed, message: "平台查询失败。", sourceUrl: officialPlatformURL(for: .ehi))
        return PriceSnapshot(
            id: idGenerator.nextID(prefix: "snapshot"),
            monitorID: monitor.id,
            checkedAt: checkedAt,
            status: snapshotStatus(from: status.kind),
            platform: status.platform,
            sourceURL: status.sourceUrl,
            message: status.message
        )
    }

    private func snapshotStatus(from kind: PlatformEvidenceStatusKind) -> PriceSnapshotStatus {
        switch kind {
        case .waitingForEvidence:
            return .networkFailed
        case .ready:
            return .noCar
        case .unavailable:
            return .unavailable
        case .loginRequired:
            return .loginRequired
        case .captchaRequired:
            return .captchaRequired
        case .parseFailed:
            return .parseFailed
        }
    }

    private func makePriceDropEvent(
        monitor: PriceMonitor,
        previousSnapshots: [PriceSnapshot],
        currentSnapshot: PriceSnapshot,
        checkedAt: Date
    ) -> PriceMonitorEvent? {
        guard currentSnapshot.status == .successful,
              let currentPrice = currentSnapshot.platformRentalPrice,
              let previous = previousSnapshots.reversed().first(where: { $0.status == .successful && $0.platformRentalPrice != nil }),
              let previousPrice = previous.platformRentalPrice,
              monitor.alertRule.isSatisfied(previous: previousPrice, current: currentPrice)
        else { return nil }

        let rentalDelta = currentPrice - previousPrice
        let totalDelta = currentSnapshot.recommendationTotalCost.flatMap { currentTotal in
            previous.recommendationTotalCost.map { currentTotal - $0 }
        }
        return PriceMonitorEvent(
            id: idGenerator.nextID(prefix: "event"),
            monitorID: monitor.id,
            occurredAt: checkedAt,
            kind: .priceDrop,
            previousSnapshotID: previous.id,
            currentSnapshotID: currentSnapshot.id,
            platformRentalDelta: rentalDelta,
            totalCostDelta: totalDelta,
            message: "监控价格下降 \(formatMoney(abs(rentalDelta)))，请打开详情复查实时价格。"
        )
    }
}
```

- [ ] **Step 5: Run scheduler tests**

Run:

```bash
swift test --filter MonitorScheduler
```

Expected: `MonitorScheduler` tests pass.

- [ ] **Step 6: Commit Task 4**

```bash
git add Sources/CarRentalOptimizer/MonitorScheduler.swift Sources/CarRentalOptimizer/MonitorNotificationService.swift Tests/CarRentalOptimizerTests/MonitorSchedulerTests.swift
git commit -m "Add monitor scheduler"
```

---

### Task 5: Monitor Center View Model And App Wiring

**Files:**
- Create: `Sources/CarRentalOptimizer/MonitorCenterViewModel.swift`
- Test: `Tests/CarRentalOptimizerTests/MonitorCenterViewModelTests.swift`
- Modify: `Sources/CarRentalOptimizer/ContentView.swift`

- [ ] **Step 1: Write failing view model tests**

Add `Tests/CarRentalOptimizerTests/MonitorCenterViewModelTests.swift`:

```swift
import CarRentalDomain
import Foundation
import Testing
@testable import CarRentalOptimizer

@Suite("MonitorCenterViewModel")
@MainActor
struct MonitorCenterViewModelTests {
    @Test("Create monitor from recommendation saves monitor and first snapshot")
    func createMonitorFromRecommendationSavesMonitorAndFirstSnapshot() async throws {
        let store = InMemoryMonitorStore()
        let viewModel = MonitorCenterViewModel(store: store, scheduler: nil, now: { Date(timeIntervalSince1970: 100) }, idGenerator: FixedIDGenerator())
        let recommendation = makeRecommendation()

        try await viewModel.createMonitor(from: recommendation, request: AppDefaults.searchRequest, frequency: .smart, alertRule: .defaultRule, systemNotificationsEnabled: false)

        #expect(viewModel.monitors.count == 1)
        #expect(viewModel.selectedMonitorID == "monitor-fixed")
        #expect(try await store.snapshots(for: "monitor-fixed").count == 1)
        #expect(try await store.snapshots(for: "monitor-fixed").first?.platformRentalPrice == recommendation.rentalTotal)
    }

    @Test("Pause and resume update monitor status")
    func pauseAndResumeUpdateMonitorStatus() async throws {
        let store = InMemoryMonitorStore()
        let monitor = makeMonitor(id: "monitor-1")
        try await store.saveMonitor(monitor)
        let viewModel = MonitorCenterViewModel(store: store, scheduler: nil, now: { Date(timeIntervalSince1970: 100) }, idGenerator: FixedIDGenerator())
        try await viewModel.reload()

        try await viewModel.pauseMonitor(id: monitor.id)
        #expect(viewModel.monitors.first?.status == .paused)

        try await viewModel.resumeMonitor(id: monitor.id)
        #expect(viewModel.monitors.first?.status == .active)
    }

    private func makeMonitor(id: String) -> PriceMonitor {
        PriceMonitor(id: id, name: "瑞虎8", request: AppDefaults.searchRequest, targetVehicleQuery: "瑞虎8", createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0))
    }

    private func makeRecommendation() -> Recommendation {
        let store = Store(id: "store-1", platform: .ehi, name: "一嗨通州店", city: "北京", address: "通州", location: AppDefaults.searchRequest.origin, distanceKm: 2, hours: "08:00-22:00")
        let listing = RentalListing(id: "listing-1", platform: .ehi, store: store, vehicleName: "奇瑞 瑞虎8", vehicleClass: "SUV", basePrice: 360, platformFees: 0, insuranceFees: 0, oneWayFee: 0, sourceUrl: "https://booking.1hai.cn/", dataCompleteness: 0.9)
        return buildRecommendation(listing: listing, match: VehicleMatch(kind: .exact, score: 1, label: "精确匹配"), taxiRoute: RouteEstimate(mode: .taxi, cost: 30, durationMinutes: 20, distanceKm: 2, summary: "打车"), transitRoute: RouteEstimate(mode: .transit, cost: 6, durationMinutes: 40, distanceKm: 2, summary: "公交"))
    }
}
```

Add these fakes to the end of `MonitorCenterViewModelTests.swift`:

```swift
private actor InMemoryMonitorStore: MonitorStoring {
    private var monitors: [PriceMonitor] = []
    private var snapshotsByMonitor: [String: [PriceSnapshot]] = [:]
    private var eventsByMonitor: [String: [PriceMonitorEvent]] = [:]

    func listMonitors() async throws -> [PriceMonitor] { monitors }
    func saveMonitor(_ monitor: PriceMonitor) async throws {
        if let index = monitors.firstIndex(where: { $0.id == monitor.id }) {
            monitors[index] = monitor
        } else {
            monitors.append(monitor)
        }
    }
    func deleteMonitor(id: String) async throws { monitors.removeAll { $0.id == id } }
    func appendSnapshot(_ snapshot: PriceSnapshot) async throws { snapshotsByMonitor[snapshot.monitorID, default: []].append(snapshot) }
    func snapshots(for monitorID: String) async throws -> [PriceSnapshot] { snapshotsByMonitor[monitorID, default: []] }
    func appendEvent(_ event: PriceMonitorEvent) async throws { eventsByMonitor[event.monitorID, default: []].append(event) }
    func events(for monitorID: String) async throws -> [PriceMonitorEvent] { eventsByMonitor[monitorID, default: []] }
    func markMonitorStatus(id: String, status: PriceMonitorStatus, updatedAt: Date) async throws {
        guard let index = monitors.firstIndex(where: { $0.id == id }) else { return }
        monitors[index].status = status
        monitors[index].updatedAt = updatedAt
    }
}

private struct FixedIDGenerator: MonitorIDGenerating {
    func nextID(prefix: String) -> String { "\(prefix)-fixed" }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
swift test --filter MonitorCenterViewModel
```

Expected: build fails with `cannot find 'MonitorCenterViewModel' in scope`.

- [ ] **Step 3: Add monitor center view model**

Create `Sources/CarRentalOptimizer/MonitorCenterViewModel.swift`:

```swift
import CarRentalDomain
import Foundation

@MainActor
final class MonitorCenterViewModel: ObservableObject {
    @Published private(set) var monitors: [PriceMonitor] = []
    @Published private(set) var selectedSnapshots: [PriceSnapshot] = []
    @Published private(set) var selectedEvents: [PriceMonitorEvent] = []
    @Published var selectedMonitorID: String?
    @Published var storageErrorMessage: String?
    @Published var backgroundMonitoringEnabled = false

    private let store: MonitorStoring
    private let scheduler: MonitorScheduler?
    private let now: () -> Date
    private let idGenerator: MonitorIDGenerating

    init(
        store: MonitorStoring,
        scheduler: MonitorScheduler?,
        now: @escaping () -> Date = Date.init,
        idGenerator: MonitorIDGenerating = UUIDMonitorIDGenerator()
    ) {
        self.store = store
        self.scheduler = scheduler
        self.now = now
        self.idGenerator = idGenerator
    }

    var selectedMonitor: PriceMonitor? {
        guard let selectedMonitorID else { return monitors.first }
        return monitors.first { $0.id == selectedMonitorID }
    }

    var selectedTrend: PriceTrendSummary {
        PriceTrendSummary(snapshots: selectedSnapshots)
    }

    func reload() async throws {
        monitors = try await store.listMonitors()
        if selectedMonitorID == nil {
            selectedMonitorID = monitors.first?.id
        }
        try await reloadSelection()
    }

    func reloadSelection() async throws {
        guard let id = selectedMonitorID ?? monitors.first?.id else {
            selectedSnapshots = []
            selectedEvents = []
            return
        }
        selectedSnapshots = try await store.snapshots(for: id)
        selectedEvents = try await store.events(for: id)
    }

    func createMonitor(
        from recommendation: Recommendation,
        request: SearchRequest,
        frequency: MonitoringFrequency,
        alertRule: PriceDropRule,
        systemNotificationsEnabled: Bool
    ) async throws {
        let currentTime = now()
        let monitorID = idGenerator.nextID(prefix: "monitor")
        let pickupAt = AppDateRules.parseRequestDate(request.pickupAt)
        let monitor = PriceMonitor(
            id: monitorID,
            name: "\(recommendation.listing.vehicleName) \(request.pickupAt)",
            request: request,
            targetVehicleQuery: recommendation.listing.vehicleName,
            targetPlatform: recommendation.listing.platform,
            targetListingSignature: ListingSignature(recommendation: recommendation),
            frequency: frequency,
            alertRule: alertRule,
            systemNotificationsEnabled: systemNotificationsEnabled,
            createdAt: currentTime,
            updatedAt: currentTime,
            lastCheckedAt: currentTime,
            nextCheckAt: pickupAt.flatMap { frequency.nextCheck(after: currentTime, pickupAt: $0) }
        )
        let snapshot = PriceSnapshot(
            id: idGenerator.nextID(prefix: "snapshot"),
            monitorID: monitorID,
            checkedAt: currentTime,
            status: .successful,
            platformRentalPrice: recommendation.rentalTotal,
            recommendationTotalCost: recommendation.bestTotal,
            platform: recommendation.listing.platform,
            storeName: recommendation.listing.store.name,
            vehicleName: recommendation.listing.vehicleName,
            dataCompleteness: recommendation.listing.dataCompleteness,
            warnings: recommendation.warnings,
            sourceURL: recommendation.listing.sourceUrl,
            message: "创建监控时记录的历史快照。"
        )
        try await store.saveMonitor(monitor)
        try await store.appendSnapshot(snapshot)
        selectedMonitorID = monitorID
        try await reload()
    }

    func saveManualMonitor(
        name: String,
        request: SearchRequest,
        targetVehicleQuery: String,
        frequency: MonitoringFrequency,
        alertRule: PriceDropRule,
        systemNotificationsEnabled: Bool
    ) async throws {
        let currentTime = now()
        let monitor = PriceMonitor(
            id: idGenerator.nextID(prefix: "monitor"),
            name: name,
            request: request,
            targetVehicleQuery: targetVehicleQuery,
            frequency: frequency,
            alertRule: alertRule,
            systemNotificationsEnabled: systemNotificationsEnabled,
            createdAt: currentTime,
            updatedAt: currentTime,
            nextCheckAt: currentTime
        )
        try await store.saveMonitor(monitor)
        selectedMonitorID = monitor.id
        try await reload()
    }

    func pauseMonitor(id: String) async throws {
        try await store.markMonitorStatus(id: id, status: .paused, updatedAt: now())
        try await reload()
    }

    func resumeMonitor(id: String) async throws {
        try await store.markMonitorStatus(id: id, status: .active, updatedAt: now())
        try await reload()
    }

    func runDueChecks() async {
        do {
            try await scheduler?.runDueChecks()
            try await reload()
        } catch {
            storageErrorMessage = error.localizedDescription
        }
    }
}
```

- [ ] **Step 4: Wire view model into ContentView**

Modify `Sources/CarRentalOptimizer/ContentView.swift`:

```swift
import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel: SearchViewModel
    @StateObject private var monitorViewModel: MonitorCenterViewModel

    init() {
        _viewModel = StateObject(wrappedValue: SearchViewModel())
        let store: JSONMonitorStore
        do {
            store = try JSONMonitorStore.live()
        } catch {
            store = JSONMonitorStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("CarRentalOptimizer-MonitorFallback", isDirectory: true))
        }
        let scheduler = MonitorScheduler(
            store: store,
            searchProvider: LiveRentalSearchService(),
            mapService: AppleMapService(),
            notificationService: UserNotificationMonitorService()
        )
        _monitorViewModel = StateObject(wrappedValue: MonitorCenterViewModel(store: store, scheduler: scheduler))
    }

    var body: some View {
        MainView()
            .environmentObject(viewModel)
            .environmentObject(monitorViewModel)
            .task {
                try? await monitorViewModel.reload()
                await monitorViewModel.runDueChecks()
            }
            .frame(
                minWidth: AppWindowLayout.minimumWidth,
                minHeight: AppWindowLayout.minimumHeight
            )
            .background(
                WindowSizeConstraintView(minimumContentSize: AppWindowLayout.minimumContentSize)
                    .frame(width: 0, height: 0)
            )
    }
}
```

- [ ] **Step 5: Run view model tests**

Run:

```bash
swift test --filter MonitorCenterViewModel
```

Expected: `MonitorCenterViewModel` tests pass.

- [ ] **Step 6: Run app tests touched so far**

Run:

```bash
swift test --filter CarRentalOptimizerTests
```

Expected: app tests pass.

- [ ] **Step 7: Commit Task 5**

```bash
git add Sources/CarRentalOptimizer/MonitorCenterViewModel.swift Sources/CarRentalOptimizer/ContentView.swift Tests/CarRentalOptimizerTests/MonitorCenterViewModelTests.swift
git commit -m "Add monitor center view model"
```

---

### Task 6: Create Monitor Sheet And Result Actions

**Files:**
- Create: `Sources/CarRentalOptimizer/CreateMonitorSheet.swift`
- Modify: `Sources/CarRentalOptimizer/ResultPanelView.swift`
- Modify: `Sources/CarRentalOptimizer/DetailPanelView.swift`
- Modify: `Sources/CarRentalOptimizer/AppPresentation.swift`

- [ ] **Step 1: Add display helpers**

Modify `Sources/CarRentalOptimizer/AppPresentation.swift` by adding:

```swift
extension MonitoringFrequency {
    var label: String {
        switch self {
        case .smart:
            return "智能频率"
        case .fixed30Minutes:
            return "每 30 分钟"
        case .fixed1Hour:
            return "每 1 小时"
        case .fixed3Hours:
            return "每 3 小时"
        case .fixed1Day:
            return "每天"
        }
    }
}

extension PriceMonitorStatus {
    var label: String {
        switch self {
        case .active:
            return "监控中"
        case .paused:
            return "已暂停"
        case .checking:
            return "巡查中"
        case .needsAttention:
            return "需处理"
        case .expired:
            return "已过期"
        }
    }
}

func formatSignedMoney(_ value: Double?) -> String {
    guard let value else { return "--" }
    let prefix = value > 0 ? "+" : ""
    return "\(prefix)\(formatMoney(value))"
}
```

- [ ] **Step 2: Create shared monitor sheet**

Create `Sources/CarRentalOptimizer/CreateMonitorSheet.swift`:

```swift
import CarRentalDomain
import SwiftUI

struct CreateMonitorSheet: View {
    let recommendation: Recommendation?
    let request: SearchRequest
    let onSaveFromRecommendation: (MonitoringFrequency, PriceDropRule, Bool) async throws -> Void
    let onSaveManual: (String, SearchRequest, String, MonitoringFrequency, PriceDropRule, Bool) async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var vehicleQuery = ""
    @State private var frequency: MonitoringFrequency = .smart
    @State private var notifyOnAnyDecrease = true
    @State private var minimumDropAmount = ""
    @State private var minimumDropPercent = ""
    @State private var systemNotificationsEnabled = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(recommendation == nil ? "新建价格监控" : "监控这个方案")
                .font(.title3.weight(.semibold))
            summary
            controls
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(WorkbenchStyle.red)
            }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存监控") {
                    Task { await save() }
                }
                .buttonStyle(.borderedProminent)
                .tint(WorkbenchStyle.accent)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear {
            name = recommendation.map { "\($0.listing.vehicleName) \(request.pickupAt)" } ?? "租车价格监控"
            vehicleQuery = recommendation?.listing.vehicleName ?? request.vehicleQuery
        }
    }

    private var summary: some View {
        SurfaceBox {
            VStack(alignment: .leading, spacing: 8) {
                MonitorSheetFactLine(icon: "calendar", text: "\(request.pickupAt) 至 \(request.returnAt)")
                MonitorSheetFactLine(icon: "mappin.circle.fill", text: request.originLabel)
                MonitorSheetFactLine(icon: "car.fill", text: vehicleQuery.isEmpty ? "未指定车型" : vehicleQuery)
                if let recommendation {
                    MonitorSheetFactLine(icon: "yensign.circle", text: "租车价 \(formatMoney(recommendation.rentalTotal)) · 总成本 \(formatMoney(recommendation.bestTotal))")
                    MonitorSheetFactLine(icon: "building.2.fill", text: "\(recommendation.listing.platform.label) · \(recommendation.listing.store.name)")
                }
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if recommendation == nil {
                TextField("监控名称", text: $name)
                    .textFieldStyle(.roundedBorder)
                TextField("车型", text: $vehicleQuery)
                    .textFieldStyle(.roundedBorder)
            }
            Picker("巡查频率", selection: $frequency) {
                ForEach(MonitoringFrequency.allCases, id: \.self) { value in
                    Text(value.label).tag(value)
                }
            }
            Toggle("只要平台租车价下降就提醒", isOn: $notifyOnAnyDecrease)
            TextField("固定金额阈值，例如 20", text: $minimumDropAmount)
                .textFieldStyle(.roundedBorder)
            TextField("百分比阈值，例如 5", text: $minimumDropPercent)
                .textFieldStyle(.roundedBorder)
            Toggle("允许 macOS 系统通知", isOn: $systemNotificationsEnabled)
        }
    }

    private func save() async {
        do {
            let rule = PriceDropRule(
                notifyOnAnyDecrease: notifyOnAnyDecrease,
                minimumDropAmount: Double(minimumDropAmount),
                minimumDropPercent: Double(minimumDropPercent).map { $0 / 100 }
            )
            if recommendation != nil {
                try await onSaveFromRecommendation(frequency, rule, systemNotificationsEnabled)
            } else {
                var manualRequest = request
                manualRequest.vehicleQuery = vehicleQuery
                try await onSaveManual(name, manualRequest, vehicleQuery, frequency, rule, systemNotificationsEnabled)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct MonitorSheetFactLine: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: icon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(WorkbenchStyle.muted)
                .frame(width: 14, height: 14)
            Text(text)
                .font(.caption)
                .foregroundStyle(WorkbenchStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
```

- [ ] **Step 3: Add result row monitor action**

Modify `ResultPanelView` so `ResultRowView` receives an `onMonitor` closure:

```swift
ResultRowView(
    rank: index + 1,
    recommendation: result,
    isSelected: viewModel.selectedId == result.id,
    onMonitor: {
        viewModel.selectResult(result.id)
        pendingMonitorRecommendation = result
    }
)
```

Add the button inside `ResultRowView`:

```swift
let onMonitor: () -> Void

Button {
    onMonitor()
} label: {
    Label("监控", systemImage: "bell.badge")
}
.buttonStyle(.bordered)
.controlSize(.small)
.accessibilityLabel("监控此租车方案")
```

Add sheet state to `SearchViewModel` or keep it in `ResultPanelView`. Use the smaller change in `ResultPanelView`:

```swift
@EnvironmentObject var monitorViewModel: MonitorCenterViewModel
@State private var pendingMonitorRecommendation: Recommendation?
```

Attach the sheet:

```swift
.sheet(item: $pendingMonitorRecommendation) { recommendation in
    CreateMonitorSheet(
        recommendation: recommendation,
        request: viewModel.request,
        onSaveFromRecommendation: { frequency, rule, notifications in
            try await monitorViewModel.createMonitor(
                from: recommendation,
                request: viewModel.request,
                frequency: frequency,
                alertRule: rule,
                systemNotificationsEnabled: notifications
            )
        },
        onSaveManual: { _, _, _, _, _, _ in }
    )
}
```

- [ ] **Step 4: Add detail panel monitor action**

Modify `DetailPanelView`:

```swift
@EnvironmentObject var monitorViewModel: MonitorCenterViewModel
@State private var pendingMonitorRecommendation: Recommendation?
```

Add a button near the existing platform link:

```swift
Button {
    pendingMonitorRecommendation = recommendation
} label: {
    HStack(spacing: 6) {
        Spacer()
        Text("监控这个方案")
        Image(systemName: "bell.badge")
    }
    .font(.caption.weight(.semibold))
    .frame(maxWidth: .infinity)
}
.buttonStyle(.borderedProminent)
.controlSize(.small)
.tint(WorkbenchStyle.accent)
```

Attach the same `CreateMonitorSheet` call used by `ResultPanelView`.

- [ ] **Step 5: Build after UI action changes**

Run:

```bash
swift build
```

Expected: build succeeds.

- [ ] **Step 6: Commit Task 6**

```bash
git add Sources/CarRentalOptimizer/CreateMonitorSheet.swift Sources/CarRentalOptimizer/ResultPanelView.swift Sources/CarRentalOptimizer/DetailPanelView.swift Sources/CarRentalOptimizer/AppPresentation.swift
git commit -m "Add monitor creation actions"
```

---

### Task 7: Monitor Center UI And Trend Chart

**Files:**
- Create: `Sources/CarRentalOptimizer/MonitorCenterView.swift`
- Modify: `Sources/CarRentalOptimizer/MainView.swift`
- Modify: `Sources/CarRentalOptimizer/App.swift`

- [ ] **Step 1: Add monitor center view**

Create `Sources/CarRentalOptimizer/MonitorCenterView.swift`:

```swift
import CarRentalDomain
import Charts
import SwiftUI

struct MonitorCenterView: View {
    @EnvironmentObject var monitorViewModel: MonitorCenterViewModel
    @EnvironmentObject var searchViewModel: SearchViewModel
    @State private var showingCreateSheet = false

    var body: some View {
        HSplitView {
            monitorList
                .frame(minWidth: 300, idealWidth: 340)
            monitorDetail
                .frame(minWidth: 560, idealWidth: 680)
        }
        .frame(minWidth: 920, minHeight: 620)
        .task {
            try? await monitorViewModel.reload()
        }
        .sheet(isPresented: $showingCreateSheet) {
            CreateMonitorSheet(
                recommendation: nil,
                request: searchViewModel.request,
                onSaveFromRecommendation: { _, _, _ in },
                onSaveManual: { name, request, vehicleQuery, frequency, rule, notifications in
                    try await monitorViewModel.saveManualMonitor(
                        name: name,
                        request: request,
                        targetVehicleQuery: vehicleQuery,
                        frequency: frequency,
                        alertRule: rule,
                        systemNotificationsEnabled: notifications
                    )
                }
            )
        }
    }

    private var monitorList: some View {
        WorkbenchPanel(
            title: "监控中心",
            subtitle: "\(monitorViewModel.monitors.count) 个价格监控",
            trailing: AnyView(Button {
                showingCreateSheet = true
            } label: {
                Image(systemName: "plus")
            }.help("新建价格监控"))
        ) {
            List(selection: $monitorViewModel.selectedMonitorID) {
                ForEach(monitorViewModel.monitors) { monitor in
                    MonitorListRow(monitor: monitor)
                        .tag(monitor.id)
                }
            }
            .listStyle(.sidebar)
        }
    }

    private var monitorDetail: some View {
        WorkbenchPanel(title: monitorViewModel.selectedMonitor?.name ?? "监控详情", subtitle: monitorViewModel.selectedMonitor?.status.label) {
            if let monitor = monitorViewModel.selectedMonitor {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        MonitorSummaryBox(monitor: monitor, trend: monitorViewModel.selectedTrend)
                        MonitorTrendChart(snapshots: monitorViewModel.selectedSnapshots)
                            .frame(height: 220)
                        MonitorEventList(events: monitorViewModel.selectedEvents)
                        MonitorSnapshotTable(snapshots: monitorViewModel.selectedSnapshots)
                        HStack {
                            Button(monitor.status == .paused ? "恢复监控" : "暂停监控") {
                                Task {
                                    if monitor.status == .paused {
                                        try? await monitorViewModel.resumeMonitor(id: monitor.id)
                                    } else {
                                        try? await monitorViewModel.pauseMonitor(id: monitor.id)
                                    }
                                }
                            }
                            Button("立即巡查") {
                                Task { await monitorViewModel.runDueChecks() }
                            }
                        }
                    }
                    .padding(16)
                }
            } else {
                EmptyStateBlock(icon: "bell.badge", title: "暂无监控", message: "从候选方案或这里新建价格监控。")
            }
        }
    }
}
```

- [ ] **Step 2: Add monitor center subviews**

Append these subviews to `MonitorCenterView.swift`:

```swift
private struct MonitorListRow: View {
    let monitor: PriceMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(monitor.name)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                StatusPill(text: monitor.status.label, color: monitor.status == .needsAttention ? WorkbenchStyle.orange : WorkbenchStyle.accent, systemImage: nil)
            }
            Text("\(monitor.request.pickupAt) 至 \(monitor.request.returnAt)")
                .font(.caption)
                .foregroundStyle(WorkbenchStyle.muted)
            Text(monitor.frequency.label)
                .font(.caption2)
                .foregroundStyle(WorkbenchStyle.muted)
        }
        .padding(.vertical, 5)
    }
}

private struct MonitorSummaryBox: View {
    let monitor: PriceMonitor
    let trend: PriceTrendSummary

    var body: some View {
        SurfaceBox(fill: WorkbenchStyle.accentSoft) {
            HStack {
                MetricPill(title: "最近租车价", value: trend.latestPlatformRentalPrice.map(formatMoney) ?? "--")
                MetricPill(title: "相比上次", value: formatSignedMoney(trend.platformRentalDelta), color: (trend.platformRentalDelta ?? 0) < 0 ? WorkbenchStyle.green : WorkbenchStyle.muted)
                MetricPill(title: "下次巡查", value: monitor.nextCheckAt.map { DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .short) } ?? "--")
            }
        }
    }
}

private struct MonitorTrendChart: View {
    let snapshots: [PriceSnapshot]

    private var points: [PriceSnapshot] {
        snapshots.filter { $0.status == .successful }
    }

    var body: some View {
        SurfaceBox {
            Chart {
                ForEach(points) { snapshot in
                    if let price = snapshot.platformRentalPrice {
                        LineMark(x: .value("时间", snapshot.checkedAt), y: .value("价格", price))
                            .foregroundStyle(by: .value("口径", "平台租车价"))
                    }
                    if let total = snapshot.recommendationTotalCost {
                        LineMark(x: .value("时间", snapshot.checkedAt), y: .value("价格", total))
                            .foregroundStyle(by: .value("口径", "推荐总成本"))
                    }
                }
            }
            .chartLegend(position: .bottom)
        }
    }
}

private struct MonitorEventList: View {
    let events: [PriceMonitorEvent]

    var body: some View {
        SurfaceBox {
            VStack(alignment: .leading, spacing: 8) {
                MonitorSectionTitleRow(icon: "bell.badge", title: "事件")
                if events.isEmpty {
                    Text("暂无降价或异常事件。")
                        .font(.caption)
                        .foregroundStyle(WorkbenchStyle.muted)
                } else {
                    ForEach(events) { event in
                        Text(event.message)
                            .font(.caption)
                            .foregroundStyle(event.kind == .priceDrop ? WorkbenchStyle.green : WorkbenchStyle.muted)
                    }
                }
            }
        }
    }
}

private struct MonitorSnapshotTable: View {
    let snapshots: [PriceSnapshot]

    var body: some View {
        SurfaceBox {
            VStack(alignment: .leading, spacing: 8) {
                MonitorSectionTitleRow(icon: "chart.line.uptrend.xyaxis", title: "历史快照")
                ForEach(snapshots.reversed()) { snapshot in
                    HStack {
                        Text(DateFormatter.localizedString(from: snapshot.checkedAt, dateStyle: .short, timeStyle: .short))
                        Spacer()
                        Text(snapshot.platformRentalPrice.map(formatMoney) ?? snapshot.status.rawValue)
                        Text("历史快照，可能已失效")
                            .font(.caption2)
                            .foregroundStyle(WorkbenchStyle.orange)
                    }
                    .font(.caption)
                }
            }
        }
    }
}

private struct MonitorSectionTitleRow: View {
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

- [ ] **Step 3: Add header entry and sheet**

Modify the top of `MainView.swift`:

```swift
struct MainView: View {
    @EnvironmentObject var viewModel: SearchViewModel
    @EnvironmentObject var monitorViewModel: MonitorCenterViewModel
    @State private var showingMonitorCenter = false

    var body: some View {
        VStack(spacing: 0) {
            WorkbenchHeader {
                showingMonitorCenter = true
            }

            HSplitView {
                SearchPanelView()
                    .frame(
                        minWidth: AppWindowLayout.searchPanelMinimumWidth,
                        idealWidth: AppWindowLayout.searchPanelIdealWidth,
                        maxWidth: AppWindowLayout.searchPanelMaximumWidth
                    )

                ResultPanelView()
                    .frame(
                        minWidth: AppWindowLayout.resultsPanelMinimumWidth,
                        idealWidth: AppWindowLayout.resultsPanelIdealWidth
                    )

                DetailPanelView()
                    .frame(
                        minWidth: AppWindowLayout.detailPanelMinimumWidth,
                        idealWidth: AppWindowLayout.detailPanelIdealWidth,
                        maxWidth: AppWindowLayout.detailPanelMaximumWidth
                    )
            }
        }
        .background(WorkbenchStyle.background)
        .sheet(isPresented: $showingMonitorCenter) {
            MonitorCenterView()
                .environmentObject(viewModel)
                .environmentObject(monitorViewModel)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openMonitorCenter)) { _ in
            showingMonitorCenter = true
        }
    }
}
```

Modify `WorkbenchHeader` to receive an action and add the button to the trailing area:

```swift
private struct WorkbenchHeader: View {
    @EnvironmentObject var viewModel: SearchViewModel
    let onOpenMonitorCenter: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            Button {
                onOpenMonitorCenter()
            } label: {
                Label("监控中心", systemImage: "bell.badge")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}
```

When applying the patch, keep the existing `WorkbenchHeader` title, metrics, and status pill code and insert the button before the final status pill:

```swift
Button {
    onOpenMonitorCenter()
} label: {
    Label("监控中心", systemImage: "bell.badge")
}
.buttonStyle(.bordered)
.controlSize(.small)
```

- [ ] **Step 4: Add app menu command**

Modify `App.swift` commands:

```swift
CommandMenu("监控") {
    Button("打开监控中心") {
        NotificationCenter.default.post(name: .openMonitorCenter, object: nil)
    }
    .keyboardShortcut("m", modifiers: [.command, .shift])
}
```

Add notification name in `AppPresentation.swift`:

```swift
extension Notification.Name {
    static let openMonitorCenter = Notification.Name("OpenMonitorCenter")
}
```

Handle it in `MainView`:

```swift
.onReceive(NotificationCenter.default.publisher(for: .openMonitorCenter)) { _ in
    showingMonitorCenter = true
}
```

- [ ] **Step 5: Build UI**

Run:

```bash
swift build
```

Expected: build succeeds.

- [ ] **Step 6: Commit Task 7**

```bash
git add Sources/CarRentalOptimizer/MonitorCenterView.swift Sources/CarRentalOptimizer/MainView.swift Sources/CarRentalOptimizer/App.swift Sources/CarRentalOptimizer/AppPresentation.swift
git commit -m "Add monitor center UI"
```

---

### Task 8: Background Monitoring Toggle And Scheduler Loop

**Files:**
- Modify: `Sources/CarRentalOptimizer/MonitorCenterViewModel.swift`
- Modify: `Sources/CarRentalOptimizer/MonitorCenterView.swift`
- Modify: `Sources/CarRentalOptimizer/App.swift`
- Test: `Tests/CarRentalOptimizerTests/MonitorCenterViewModelTests.swift`

- [ ] **Step 1: Add failing loop preference test**

Append to `MonitorCenterViewModelTests`:

```swift
@Test("Background monitoring preference toggles without changing monitors")
func backgroundMonitoringPreferenceTogglesWithoutChangingMonitors() async throws {
    let store = InMemoryMonitorStore()
    let monitor = makeMonitor(id: "monitor-1")
    try await store.saveMonitor(monitor)
    let viewModel = MonitorCenterViewModel(store: store, scheduler: nil, now: { Date(timeIntervalSince1970: 100) }, idGenerator: FixedIDGenerator())
    try await viewModel.reload()

    viewModel.setBackgroundMonitoringEnabled(true)

    #expect(viewModel.backgroundMonitoringEnabled)
    #expect(viewModel.monitors.count == 1)

    viewModel.setBackgroundMonitoringEnabled(false)

    #expect(!viewModel.backgroundMonitoringEnabled)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift test --filter "Background monitoring preference"
```

Expected: build fails with `value of type 'MonitorCenterViewModel' has no member 'setBackgroundMonitoringEnabled'`.

- [ ] **Step 3: Add scheduler loop and preference**

Modify `MonitorCenterViewModel.swift`:

```swift
private var schedulerTask: Task<Void, Never>?

func setBackgroundMonitoringEnabled(_ enabled: Bool) {
    backgroundMonitoringEnabled = enabled
    if enabled {
        startSchedulerLoop()
    } else {
        schedulerTask?.cancel()
        schedulerTask = nil
    }
}

func startSchedulerLoop() {
    guard schedulerTask == nil else { return }
    schedulerTask = Task { [weak self] in
        while !Task.isCancelled {
            await self?.runDueChecks()
            try? await Task.sleep(nanoseconds: 60_000_000_000)
        }
    }
}

func stopSchedulerLoopForExplicitQuit() {
    schedulerTask?.cancel()
    schedulerTask = nil
}
```

- [ ] **Step 4: Add UI toggle**

Modify `MonitorCenterView.swift` by inserting the toggle immediately under `MonitorSummaryBox` in `monitorDetail`:

```swift
MonitorSummaryBox(monitor: monitor, trend: monitorViewModel.selectedTrend)
Toggle("关闭窗口后继续巡查", isOn: Binding(
    get: { monitorViewModel.backgroundMonitoringEnabled },
    set: { monitorViewModel.setBackgroundMonitoringEnabled($0) }
))
.toggleStyle(.checkbox)
.help("启用后，关闭主窗口时应用仍保持轻量运行；显式退出应用会停止巡查，下次启动时补跑到期任务。")
MonitorTrendChart(snapshots: monitorViewModel.selectedSnapshots)
    .frame(height: 220)
```

- [ ] **Step 5: Stop loop on explicit app quit**

Modify `App.swift` by adding an app delegate:

```swift
final class AppLifecycleDelegate: NSObject, NSApplicationDelegate {
    static weak var monitorViewModel: MonitorCenterViewModel?

    func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in
            AppLifecycleDelegate.monitorViewModel?.stopSchedulerLoopForExplicitQuit()
        }
    }
}
```

In `CarRentalOptimizerApp`:

```swift
@NSApplicationDelegateAdaptor(AppLifecycleDelegate.self) private var appDelegate
```

In `ContentView.init()`, replace the monitor view model construction with this concrete block:

```swift
let monitorViewModel = MonitorCenterViewModel(store: store, scheduler: scheduler)
AppLifecycleDelegate.monitorViewModel = monitorViewModel
_monitorViewModel = StateObject(wrappedValue: monitorViewModel)
```

- [ ] **Step 6: Run tests and build**

Run:

```bash
swift test --filter MonitorCenterViewModel
swift build
```

Expected: tests pass and build succeeds.

- [ ] **Step 7: Commit Task 8**

```bash
git add Sources/CarRentalOptimizer/MonitorCenterViewModel.swift Sources/CarRentalOptimizer/MonitorCenterView.swift Sources/CarRentalOptimizer/App.swift Sources/CarRentalOptimizer/ContentView.swift Tests/CarRentalOptimizerTests/MonitorCenterViewModelTests.swift
git commit -m "Add background monitoring toggle"
```

---

### Task 9: Documentation, Release Notes, And Full Verification

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Update README current capabilities**

Modify `README.md` under `当前能力` by adding:

```markdown
- 可从推荐方案创建价格监控，也可在监控中心手动新建监控；监控会按智能或固定频率重新调用一嗨/神州官方接口。
- 监控中心保存本机历史价格快照，展示平台租车价和推荐总成本趋势；历史报价会标记为快照，需复查实时可订价格。
- 平台租车价下降时会记录应用内事件，并可按用户设置发送 macOS 系统通知。
```

- [ ] **Step 2: Update changelog**

Add a new top entry to `CHANGELOG.md`:

```markdown
## [Unreleased]

### Added
- 新增价格监控中心，可从当前推荐或手动表单创建租车价格监控。
- 监控任务支持智能频率和固定频率巡查，记录平台租车价与推荐总成本历史趋势。
- 平台租车价下降时会记录事件，并可按设置发送 macOS 系统通知。
```

- [ ] **Step 3: Run full test suite**

Run:

```bash
swift test
```

Expected: all tests pass.

- [ ] **Step 4: Build app**

Run:

```bash
swift build
```

Expected: build succeeds.

- [ ] **Step 5: Run release smoke script**

Run:

```bash
scripts/verify-launch.sh
```

Expected: script completes without reporting launch failure.

- [ ] **Step 6: Inspect final diff**

Run:

```bash
git status --short
git diff --stat
git diff --check
```

Expected: only intended monitoring files, docs, tests, and UI changes are listed; `git diff --check` prints no whitespace errors.

- [ ] **Step 7: Commit Task 9**

```bash
git add README.md CHANGELOG.md
git commit -m "Document price monitoring"
```

---

## Self-Review Checklist

- Spec coverage:
  - Local monitor creation from recommendation: Task 5 and Task 6.
  - Manual monitor creation: Task 5, Task 6, Task 7.
  - Local JSON persistence: Task 3.
  - Foreground due checks: Task 4 and Task 8.
  - Optional background mode while app remains active: Task 8.
  - Smart and fixed frequencies: Task 1 and Task 8.
  - Any-decrease, amount, and percentage alert rules: Task 1 and Task 6.
  - Platform rental price and recommendation total trend tracking: Task 1, Task 4, Task 7.
  - Failure snapshots: Task 4.
  - In-app events and optional system notifications: Task 4 and Task 7.
  - Historical stale labels: Task 1 and Task 7.
  - Automatic pause after pickup: Task 1 and Task 4.
- Type consistency:
  - `PriceMonitor`, `PriceSnapshot`, `PriceMonitorEvent`, `MonitoringFrequency`, and `PriceDropRule` are defined before store, scheduler, and UI tasks use them.
  - `ListingSignature` is defined before monitor creation stores it.
  - `MonitorStoring`, `MonitorNotificationSending`, and `MonitorIDGenerating` are defined before view model tests use them.
- Verification:
  - Each task has a focused test/build command before commit.
  - Final task runs `swift test`, `swift build`, `scripts/verify-launch.sh`, and diff checks.
