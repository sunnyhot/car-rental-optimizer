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
