import XCTest
@testable import CarRentalDomain

final class PlatformEvidenceTests: XCTestCase {
    private let request = SearchRequest(
        origin: GeoPoint(lat: 39.9169, lng: 116.6462),
        originLabel: "北京通州",
        pickupAt: "2026-09-01",
        returnAt: "2026-10-11",
        returnMode: .sameStore,
        radiusKm: 100,
        vehicleQuery: "瑞虎8",
        platforms: [.ehi, .carInc]
    )

    func testEmptyEvidenceWaitsForOfficialPageContent() {
        let result = parsePlatformEvidence(
            input: PlatformEvidenceInput(platform: .carInc, text: "", sourceUrl: "https://www.zuche.com/"),
            request: request
        )

        XCTAssertEqual(result.status.kind, .waitingForEvidence)
        XCTAssertTrue(result.listings.isEmpty)
    }

    func testCarIncNotOpenPeriodIsUnavailableAndCreatesNoListing() {
        let result = parsePlatformEvidence(
            input: PlatformEvidenceInput(
                platform: .carInc,
                text: "神州租车\n当前时间段暂未开放租车，请调整取还车日期",
                sourceUrl: "https://www.zuche.com/"
            ),
            request: request
        )

        XCTAssertEqual(result.status.kind, .unavailable)
        XCTAssertTrue(result.listings.isEmpty)
        XCTAssertTrue(result.status.message.contains("未开放"))
    }

    func testLoginAndCaptchaStatesDoNotCreateListings() {
        let login = parsePlatformEvidence(
            input: PlatformEvidenceInput(platform: .ehi, text: "请先登录后查看车辆报价", sourceUrl: "https://www.1hai.cn/"),
            request: request
        )
        let captcha = parsePlatformEvidence(
            input: PlatformEvidenceInput(platform: .carInc, text: "请完成安全验证，拖动滑块继续", sourceUrl: "https://www.zuche.com/"),
            request: request
        )

        XCTAssertEqual(login.status.kind, .loginRequired)
        XCTAssertEqual(captcha.status.kind, .captchaRequired)
        XCTAssertTrue(login.listings.isEmpty)
        XCTAssertTrue(captcha.listings.isEmpty)
    }

    func testUnparseableOfficialContentReportsParseFailure() {
        let result = parsePlatformEvidence(
            input: PlatformEvidenceInput(platform: .ehi, text: "一嗨租车 北京 通州 搜索结果 已加载", sourceUrl: "https://www.1hai.cn/"),
            request: request
        )

        XCTAssertEqual(result.status.kind, .parseFailed)
        XCTAssertTrue(result.listings.isEmpty)
    }

    func testParsesOfficialEvidenceIntoRentalListing() {
        let result = parsePlatformEvidence(
            input: PlatformEvidenceInput(
                platform: .ehi,
                text: """
                一嗨租车
                北京通州万达店
                奇瑞 瑞虎8 1.6T 自动
                租车基础价 ¥12880
                平台服务费 ¥42
                保险保障 ¥55
                """,
                sourceUrl: "https://www.1hai.cn/"
            ),
            request: request
        )

        XCTAssertEqual(result.status.kind, .ready)
        XCTAssertEqual(result.listings.count, 1)
        XCTAssertEqual(result.listings[0].platform, .ehi)
        XCTAssertEqual(result.listings[0].store.name, "北京通州万达店")
        XCTAssertEqual(result.listings[0].vehicleName, "奇瑞 瑞虎8 1.6T 自动")
        XCTAssertEqual(result.listings[0].basePrice, 12880)
        XCTAssertEqual(result.listings[0].platformFees, 42)
        XCTAssertEqual(result.listings[0].insuranceFees, 55)
        XCTAssertTrue(result.listings[0].warnings.contains(.partialPrice))
    }
}
