import CarRentalDomain
import Foundation

enum AppDefaults {
    static let searchRequest = SearchRequest(
        origin: GeoPoint(lat: 39.9169, lng: 116.6462),
        originLabel: "北京通州",
        pickupAt: "2026-06-05T09:00",
        returnAt: "2026-06-07T18:00",
        returnMode: .sameStore,
        radiusKm: 100,
        vehicleQuery: "瑞虎8",
        platforms: [.ehi, .carInc]
    )
}

extension PlatformId {
    var label: String {
        switch self {
        case .ehi:
            return "一嗨"
        case .carInc:
            return "神州"
        }
    }
}

extension ReturnMode {
    var label: String {
        switch self {
        case .sameStore:
            return "同店取还"
        case .differentStore:
            return "异店/异地还车"
        }
    }
}

extension RouteMode {
    var label: String {
        switch self {
        case .taxi:
            return "打车"
        case .transit:
            return "公共交通"
        }
    }
}

func renderWarnings(_ warnings: [ResultWarning]) -> String {
    if warnings.contains(.crossCityPickup) {
        return "这是跨城取车方案，租车价格低，但需要额外关注高铁班次、门店营业时间和行李不便。"
    }

    if warnings.contains(.partialPrice) {
        return "该方案存在部分价格缺失，建议打开原始平台复核。"
    }

    if warnings.contains(.mapCostMissing) {
        return "交通成本暂不可用，当前排序主要参考租车价格。"
    }

    return "该方案存在数据完整度提醒，建议打开原始平台复核。"
}

func formatMoney(_ value: Double) -> String {
    "¥\(Int(value.rounded()))"
}
