import XCTest
@testable import CarRentalDomain

final class VehicleMatcherTests: XCTestCase {

    // MARK: - Exact Match

    func testExactMatchTiggo8() {
        let match = matchVehicle(
            query: "瑞虎8",
            vehicleName: "奇瑞 瑞虎8 1.6T 自动",
            vehicleClass: "中型SUV"
        )
        XCTAssertEqual(match.kind, .exact)
        XCTAssertEqual(match.score, 1)
        XCTAssertTrue(match.label.contains("精确"))
    }

    // MARK: - Similar Class (Same Family)

    func testSimilarClassSuvFallback() {
        let match = matchVehicle(
            query: "瑞虎8",
            vehicleName: "哈弗 H6 自动",
            vehicleClass: "紧凑型SUV"
        )
        XCTAssertEqual(match.kind, .similarClass)
        XCTAssertTrue(match.score > 0.5)
        XCTAssertTrue(match.score < 1)
        XCTAssertTrue(match.label.contains("同级"))
    }

    // MARK: - Low Confidence

    func testLowConfidenceWhenClassMetadataMissing() {
        let match = matchVehicle(
            query: "瑞虎8",
            vehicleName: "经济型自动挡",
            vehicleClass: ""
        )
        XCTAssertEqual(match.kind, .lowConfidence)
        XCTAssertTrue(match.score < 0.5)
        XCTAssertTrue(match.label.contains("低置信"))
    }

    // MARK: - Not Specified

    func testNotSpecifiedWhenQueryEmpty() {
        let match = matchVehicle(
            query: "",
            vehicleName: "奇瑞 瑞虎8 1.6T 自动",
            vehicleClass: "中型SUV"
        )
        XCTAssertEqual(match.kind, .notSpecified)
        XCTAssertEqual(match.score, 0)
        XCTAssertTrue(match.label.contains("未指定"))
    }
}
