import CarRentalDomain
import Foundation
import Testing
@testable import CarRentalOptimizer

@Suite("Search trust presentation")
struct SearchTrustPresentationTests {
    @Test("Preflight validation reports blocking platform issue")
    func preflightValidationReportsBlockingPlatformIssue() {
        var request = AppDefaults.searchRequest
        request.platforms = []

        let result = validateSearchPreflight(request)

        #expect(result.hasBlockingIssue)
        #expect(result.issues.map(\.id).contains("platforms-empty"))
        #expect(result.issues.first { $0.id == "platforms-empty" }?.severity == .blocking)
    }

    @Test("Preflight validation reports helpful warnings")
    func preflightValidationReportsHelpfulWarnings() {
        var request = AppDefaults.searchRequest
        request.originLabel = "   "
        request.radiusKm = 420
        request.vehicleQuery = "瑞虎8 Pro 四驱七座"

        let result = validateSearchPreflight(request)

        #expect(!result.hasBlockingIssue)
        #expect(result.issues.map(\.id).contains("origin-empty"))
        #expect(result.issues.map(\.id).contains("specific-vehicle-wide-radius"))
    }

    @Test("Platform recovery actions are deterministic")
    func platformRecoveryActionsAreDeterministic() {
        let login = PlatformEvidenceStatus(
            platform: .ehi,
            kind: .loginRequired,
            message: "一嗨需要登录。",
            sourceUrl: "https://booking.1hai.cn/"
        )
        let parseFailed = PlatformEvidenceStatus(
            platform: .carInc,
            kind: .parseFailed,
            message: "神州返回字段未识别。",
            sourceUrl: "https://m.zuche.com/"
        )
        let carIncLogin = PlatformEvidenceStatus(
            platform: .carInc,
            kind: .loginRequired,
            message: "登录神州后可补全基础服务费。",
            sourceUrl: "https://www.zuche.com/"
        )

        #expect(SearchRecoveryAction.actions(for: login).map(\.id) == ["ehi-login", "retry-same-request"])
        #expect(SearchRecoveryAction.actions(for: carIncLogin).map(\.id) == ["carinc-login", "retry-same-request"])
        let carIncAction = SearchRecoveryAction.actions(for: carIncLogin).first
        #expect(carIncAction?.title == "登录神州")
        #expect(carIncAction?.message.contains("登录神州官网") == true)
        #expect(SearchRecoveryAction.actions(for: parseFailed).map(\.id) == ["retry-later", "open-platform"])
    }

    @Test("Quote credibility prefers concrete warning labels")
    func quoteCredibilityPrefersConcreteWarningLabels() {
        let complete = QuoteCredibility.make(for: makeRecommendation(dataCompleteness: 0.96, warnings: []))
        let partial = QuoteCredibility.make(for: makeRecommendation(dataCompleteness: 0.88, warnings: [.partialPrice]))
        let routeMissing = QuoteCredibility.make(for: makeRecommendation(dataCompleteness: 0.96, warnings: [.mapCostMissing]))
        let crossCity = QuoteCredibility.make(for: makeRecommendation(dataCompleteness: 0.96, warnings: [.crossCityPickup]))

        #expect(complete.level == .complete)
        #expect(complete.title == "完整报价")
        #expect(partial.level == .reviewRecommended)
        #expect(partial.title == "部分费用待复核")
        #expect(routeMissing.title == "路线估算缺失")
        #expect(crossCity.title == "跨城/异店风险")
    }

    @Test("Diagnostic summary counts platform outcomes")
    func diagnosticSummaryCountsPlatformOutcomes() {
        let evidenceResults = [
            PlatformEvidenceResult(
                platform: .ehi,
                status: PlatformEvidenceStatus(platform: .ehi, kind: .ready, message: "一嗨已返回 2 个报价。", sourceUrl: "https://booking.1hai.cn/"),
                listings: [makeListing(id: "ehi-1"), makeListing(id: "ehi-2")]
            ),
            PlatformEvidenceResult(
                platform: .carInc,
                status: PlatformEvidenceStatus(platform: .carInc, kind: .captchaRequired, message: "神州需要验证。", sourceUrl: "https://m.zuche.com/"),
                listings: []
            ),
        ]

        let summary = SearchDiagnosticSummary.make(
            evidenceResults: evidenceResults,
            recommendations: [makeRecommendation(id: "ehi-1")]
        )

        #expect(summary.queriedPlatforms == [.ehi, .carInc])
        #expect(summary.successfulPlatforms == [.ehi])
        #expect(summary.failedStatuses.map(\.kind) == [.captchaRequired])
        #expect(summary.listingCount == 2)
        #expect(summary.visibleResultCount == 1)
        #expect(summary.routeEstimateStatus == "路线估算已参与排序")
    }

    @Test("Quote credibility flags low completeness without warnings")
    func quoteCredibilityFlagsLowCompletenessWithoutWarnings() {
        let credibility = QuoteCredibility.make(for: makeRecommendation(dataCompleteness: 0.72, warnings: []))

        #expect(credibility.level == .reviewRecommended)
        #expect(credibility.title == "报价完整度偏低")
        #expect(credibility.message.contains("平台返回字段不够完整"))
    }
}

private func makeRecommendation(
    id: String = "rec-1",
    dataCompleteness: Double = 0.96,
    warnings: [ResultWarning] = []
) -> Recommendation {
    let listing = makeListing(id: id, dataCompleteness: dataCompleteness, warnings: warnings)
    let taxi = RouteEstimate(mode: .taxi, cost: 38, durationMinutes: 22, distanceKm: listing.store.distanceKm, summary: "打车约 22 分钟")
    let transit = RouteEstimate(mode: .transit, cost: 6, durationMinutes: 44, distanceKm: listing.store.distanceKm, summary: "公交约 44 分钟")
    return buildRecommendation(
        listing: listing,
        match: VehicleMatch(kind: .exact, score: 1, label: "精确匹配"),
        taxiRoute: taxi,
        transitRoute: transit
    )
}

private func makeListing(
    id: String,
    dataCompleteness: Double = 0.96,
    warnings: [ResultWarning] = []
) -> RentalListing {
    RentalListing(
        id: id,
        platform: .ehi,
        store: Store(
            id: "\(id)-store",
            platform: .ehi,
            name: "一嗨测试门店",
            city: "北京",
            address: "北京市通州区",
            location: GeoPoint(lat: 39.91, lng: 116.65),
            distanceKm: 3.2,
            hours: "08:00-22:00"
        ),
        vehicleName: "奇瑞 瑞虎8",
        vehicleClass: "中型SUV",
        basePrice: 320,
        platformFees: 20,
        insuranceFees: 50,
        oneWayFee: 0,
        sourceUrl: "https://booking.1hai.cn/",
        dataCompleteness: dataCompleteness,
        warnings: warnings
    )
}
