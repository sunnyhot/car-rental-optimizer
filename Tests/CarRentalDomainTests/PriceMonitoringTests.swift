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
        XCTAssertEqual(summary.lowestPlatformRentalPrice, 460)
        XCTAssertEqual(summary.highestPlatformRentalPrice, 500)
        XCTAssertEqual(summary.firstPlatformRentalPrice, 500)
        XCTAssertEqual(summary.platformRentalDeltaFromFirst, -40)
        XCTAssertEqual(summary.latestSuccessfulCheckAt, date(2026, 6, 12, 12, 0))
        XCTAssertTrue(snapshots[0].isHistoricalSnapshot(comparedToLatestID: "3"))
    }

    func testMonitorCenterFilterKeepsOnlyMatchingStatuses() {
        let active = makeMonitor(id: "active", status: .active)
        let attention = makeMonitor(id: "attention", status: .needsAttention)
        let paused = makeMonitor(id: "paused", status: .paused)
        let expired = makeMonitor(id: "expired", status: .expired)

        XCTAssertEqual(filterMonitorsForCenter([active, attention, paused, expired], filter: .all).map(\.id), ["active", "attention", "paused", "expired"])
        XCTAssertEqual(filterMonitorsForCenter([active, attention, paused, expired], filter: .active).map(\.id), ["active"])
        XCTAssertEqual(filterMonitorsForCenter([active, attention, paused, expired], filter: .needsAttention).map(\.id), ["attention"])
        XCTAssertEqual(filterMonitorsForCenter([active, attention, paused, expired], filter: .paused).map(\.id), ["paused"])
        XCTAssertEqual(filterMonitorsForCenter([active, attention, paused, expired], filter: .expired).map(\.id), ["expired"])
    }

    func testMonitorCenterSortsAttentionDropsUrgencyAndDueChecksFirst() {
        let now = date(2026, 6, 12, 10, 0)
        let ordinary = makeMonitor(id: "ordinary", status: .active, pickupAt: "2026-06-30", nextCheckAt: date(2026, 6, 13, 10, 0))
        let overdue = makeMonitor(id: "overdue", status: .active, pickupAt: "2026-06-30", nextCheckAt: date(2026, 6, 12, 9, 0))
        let urgent = makeMonitor(id: "urgent", status: .active, pickupAt: "2026-06-13", nextCheckAt: date(2026, 6, 13, 10, 0))
        let drop = makeMonitor(id: "drop", status: .active, pickupAt: "2026-06-30", nextCheckAt: date(2026, 6, 13, 10, 0))
        let attention = makeMonitor(id: "attention", status: .needsAttention, pickupAt: "2026-06-30", nextCheckAt: date(2026, 6, 13, 10, 0))
        let events = [
            "drop": [PriceMonitorEvent(id: "event-drop", monitorID: "drop", occurredAt: date(2026, 6, 12, 8, 0), kind: .priceDrop, message: "drop")]
        ]

        let sorted = sortMonitorsForCenter(
            [ordinary, overdue, urgent, drop, attention],
            eventsByMonitorID: events,
            now: now
        )

        XCTAssertEqual(sorted.map(\.id), ["attention", "drop", "urgent", "overdue", "ordinary"])
    }

    func testMonitorHealthSummaryCountsAttentionDropsAndDueToday() {
        let now = date(2026, 6, 12, 10, 0)
        let monitors = [
            makeMonitor(id: "active", status: .active, nextCheckAt: date(2026, 6, 12, 18, 0)),
            makeMonitor(id: "attention", status: .needsAttention, nextCheckAt: date(2026, 6, 12, 9, 0)),
            makeMonitor(id: "paused", status: .paused, nextCheckAt: date(2026, 6, 12, 12, 0)),
        ]
        let events = [
            "active": [PriceMonitorEvent(id: "event-drop", monitorID: "active", occurredAt: date(2026, 6, 12, 8, 0), kind: .priceDrop, message: "drop")]
        ]

        let summary = MonitorHealthSummary.make(
            monitors: monitors,
            eventsByMonitorID: events,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(summary.totalCount, 3)
        XCTAssertEqual(summary.activeCount, 1)
        XCTAssertEqual(summary.needsAttentionCount, 1)
        XCTAssertEqual(summary.recentPriceDropCount, 1)
        XCTAssertEqual(summary.dueTodayCount, 2)
    }

    func testMonitorLifecycleEventsDetectRepeatedFailureAndRecovery() {
        let monitor = makeMonitor(id: "monitor-1")
        let previousFailures = [
            PriceSnapshot(id: "old-1", monitorID: monitor.id, checkedAt: date(2026, 6, 12, 8, 0), status: .loginRequired, message: "login"),
            PriceSnapshot(id: "old-2", monitorID: monitor.id, checkedAt: date(2026, 6, 12, 9, 0), status: .loginRequired, message: "login"),
        ]
        let thirdFailure = PriceSnapshot(id: "new-fail", monitorID: monitor.id, checkedAt: date(2026, 6, 12, 10, 0), status: .loginRequired, message: "login")
        let success = PriceSnapshot(id: "new-success", monitorID: monitor.id, checkedAt: date(2026, 6, 12, 11, 0), status: .successful, platformRentalPrice: 460, message: "success")

        let repeatedFailure = makeMonitorLifecycleEvents(
            monitor: monitor,
            previousSnapshots: previousFailures,
            currentSnapshot: thirdFailure,
            checkedAt: thirdFailure.checkedAt,
            id: { "event-repeated" }
        )
        let recovery = makeMonitorLifecycleEvents(
            monitor: monitor,
            previousSnapshots: previousFailures + [thirdFailure],
            currentSnapshot: success,
            checkedAt: success.checkedAt,
            id: { "event-recovered" }
        )
        let fourthFailureNoise = makeMonitorLifecycleEvents(
            monitor: monitor,
            previousSnapshots: previousFailures + [thirdFailure],
            currentSnapshot: PriceSnapshot(id: "new-fail-2", monitorID: monitor.id, checkedAt: date(2026, 6, 12, 12, 0), status: .loginRequired, message: "login"),
            checkedAt: date(2026, 6, 12, 12, 0),
            id: { "event-noise" }
        )

        XCTAssertEqual(repeatedFailure.map(\.kind), [.repeatedFailure])
        XCTAssertEqual(repeatedFailure.first?.id, "event-repeated")
        XCTAssertEqual(repeatedFailure.first?.currentSnapshotID, "new-fail")
        XCTAssertEqual(recovery.map(\.kind), [.recovered])
        XCTAssertEqual(recovery.first?.previousSnapshotID, "new-fail")
        XCTAssertTrue(fourthFailureNoise.isEmpty)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func makeMonitor(
        id: String,
        status: PriceMonitorStatus = .active,
        pickupAt: String = "2026-06-20",
        nextCheckAt: Date? = nil
    ) -> PriceMonitor {
        var request = SearchRequest(
            origin: GeoPoint(lat: 39.91, lng: 116.65),
            originLabel: "北京通州",
            pickupAt: pickupAt,
            returnAt: "2026-06-21",
            returnMode: .sameStore,
            radiusKm: 100,
            vehicleQuery: "瑞虎8",
            platforms: [.ehi, .carInc]
        )
        request.pickupAt = pickupAt
        return PriceMonitor(
            id: id,
            name: id,
            request: request,
            targetVehicleQuery: "瑞虎8",
            status: status,
            createdAt: date(2026, 6, 1, 10, 0),
            updatedAt: date(2026, 6, 1, 10, 0),
            nextCheckAt: nextCheckAt
        )
    }
}
