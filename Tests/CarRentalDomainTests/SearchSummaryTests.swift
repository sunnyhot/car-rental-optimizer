import XCTest
@testable import CarRentalDomain

final class SearchSummaryTests: XCTestCase {
    func testDateOnlyRentalDaysUseCalendarDifference() {
        XCTAssertEqual(calculateRentalDays(pickupAt: "2026-09-01", returnAt: "2026-10-11"), 40)
    }

    func testSameDateRentalIsAtLeastOneDay() {
        XCTAssertEqual(calculateRentalDays(pickupAt: "2026-09-01", returnAt: "2026-09-01"), 1)
    }

    func testDateOnlyStatusDoesNotShowTimes() {
        let request = SearchRequest(
            origin: GeoPoint(lat: 39.9169, lng: 116.6462),
            originLabel: "北京通州",
            pickupAt: "2026-09-01",
            returnAt: "2026-10-11",
            returnMode: .sameStore,
            radiusKm: 100,
            vehicleQuery: "瑞虎8",
            platforms: [.ehi, .carInc]
        )

        XCTAssertEqual(
            formatSearchCompletionStatus(request: request, resultCount: 0),
            "已按 2026/09/01 - 2026/10/11 查询，按 40 天计费，没有找到候选车辆。"
        )
    }
}
