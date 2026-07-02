import CarRentalDomain
import Foundation
import Testing
@testable import CarRentalOptimizer

@Suite("Vehicle insights")
struct VehicleInsightTests {
    @Test("Local inference extracts electric sedan battery seats and platform features")
    func localInferenceExtractsElectricSedanBatterySeatsAndPlatformFeatures() {
        let listing = makeInsightListing(
            vehicleName: "小鹏 MONA",
            vehicleClass: "纯电 51kWh | 三厢 5座 | 车龄1年内 | 360影像 | 手机无线充电 | 天窗"
        )

        let insight = VehicleInsightLocalInferencer.localInsight(for: listing, now: insightDate("2026-07-02 17:14"))

        #expect(insight.origin == .localInference)
        #expect(insight.vehicleName == "小鹏 MONA")
        #expect(insight.seriesName == "小鹏 MONA")
        #expect(insight.modelYear == nil)
        #expect(insight.modelYearConfidence == .low)
        #expect(insight.trimConfidence == .medium)
        #expect(insight.configurationSummary == "纯电、三厢、5座、51kWh、360影像、手机无线充电、天窗、车龄1年内")
        #expect(insight.specSheet.batteryKWh?.value == 51)
        #expect(insight.specSheet.batteryKWh?.appliesTo == .platformListing)
        #expect(insight.specSheet.seats?.value == 5)
        #expect(insight.specSheet.bodyStyle?.value == "三厢")
        #expect(insight.specSheet.features.map(\.name) == ["360影像", "手机无线充电", "天窗", "车龄1年内"])
        #expect(insight.shortSummary == "平台标注：纯电三厢 5座，51kWh；适合市内/短途出行，长途注意补能。")
        #expect(insight.longSummary.contains("车系介绍：本地根据平台返回字段推断车型特征。"))
        #expect(insight.longSummary.contains("当前租赁车辆配置以平台返回为准：纯电、三厢、5座、51kWh、360影像、手机无线充电、天窗、车龄1年内。"))
    }

    @Test("Local inference only sets model year from explicit year tokens")
    func localInferenceOnlySetsModelYearFromExplicitYearTokens() {
        let recentListing = makeInsightListing(
            vehicleName: "小鹏 MONA",
            vehicleClass: "纯电 51kWh | 三厢 5座 | 车龄1年内"
        )
        let explicitListing = makeInsightListing(
            vehicleName: "小鹏 MONA 2024款",
            vehicleClass: "纯电 51kWh | 三厢 5座 | 360影像"
        )

        let recentInsight = VehicleInsightLocalInferencer.localInsight(for: recentListing, now: insightDate("2026-07-02 17:14"))
        let explicitInsight = VehicleInsightLocalInferencer.localInsight(for: explicitListing, now: insightDate("2026-07-02 17:14"))

        #expect(recentInsight.modelYear == nil)
        #expect(recentInsight.modelYearConfidence == .low)
        #expect(recentInsight.longSummary.contains("年款未确认"))
        #expect(explicitInsight.modelYear == "2024款")
        #expect(explicitInsight.modelYearConfidence == .high)
    }

    @Test("Local inference extracts fuel and hybrid specs")
    func localInferenceExtractsFuelAndHybridSpecs() {
        let listing = makeInsightListing(
            vehicleName: "比亚迪宋 PLUS 新能源",
            vehicleClass: "1.5 插电混 | SUV 5座 | 后排隐私玻璃 | 电动后尾门"
        )

        let insight = VehicleInsightLocalInferencer.localInsight(for: listing, now: insightDate("2026-07-02 17:14"))

        #expect(insight.specSheet.bodyStyle?.value == "SUV")
        #expect(insight.specSheet.seats?.value == 5)
        #expect(insight.specSheet.features.map(\.name) == ["后排隐私玻璃", "电动后尾门"])
        #expect(insight.configurationSummary == "插电混、SUV、5座、后排隐私玻璃、电动后尾门")
        #expect(insight.shortSummary == "平台标注：插电混 SUV 5座；适合多人和行李，长途补能压力低于纯电。")
    }

    @Test("Basic spec facts include unknown states for important detail fields")
    func basicSpecFactsIncludeUnknownStatesForImportantDetailFields() {
        let listing = makeInsightListing(vehicleName: "大众 朗逸", vehicleClass: "1.5L | 三厢 5座 | 倒车雷达 | 蓝牙")
        let insight = VehicleInsightLocalInferencer.localInsight(for: listing, now: insightDate("2026-07-02 17:14"))

        let facts = insight.formattedBasicSpecs.map { "\($0.label)：\($0.value)" }

        #expect(facts.contains("座位数：5座"))
        #expect(facts.contains("车身形式：三厢"))
        #expect(facts.contains("轴距：未确认"))
        #expect(facts.contains("油箱/电池：未确认"))
        #expect(insight.platformFeatures.map(\.name) == ["倒车雷达", "蓝牙"])
    }
}

private func makeInsightListing(
    vehicleName: String,
    vehicleClass: String,
    platform: PlatformId = .ehi
) -> RentalListing {
    RentalListing(
        id: UUID().uuidString,
        platform: platform,
        store: Store(
            id: "test-store",
            platform: platform,
            name: "测试门店",
            city: "北京",
            address: "北京市通州区",
            location: GeoPoint(lat: 39.91, lng: 116.65),
            distanceKm: 0.86,
            hours: "08:00-22:00"
        ),
        vehicleName: vehicleName,
        vehicleClass: vehicleClass,
        basePrice: 53,
        platformFees: 0,
        insuranceFees: 0,
        oneWayFee: 0,
        sourceUrl: "https://booking.1hai.cn/",
        dataCompleteness: 1
    )
}

private func insightDate(_ value: String) -> Date {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
    return formatter.date(from: value)!
}
