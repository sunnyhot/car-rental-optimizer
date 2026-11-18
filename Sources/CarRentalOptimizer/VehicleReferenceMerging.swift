import CarRentalDomain
import Foundation

extension VehicleSpecSheet {
    func sanitizedDimensions() -> VehicleSpecSheet {
        var result = self
        func valid(_ value: VehicleSpecValue<Int>?) -> VehicleSpecValue<Int>? {
            value.flatMap { (500...15000).contains($0.value) ? $0 : nil }
        }
        result.lengthMm = valid(lengthMm)
        result.widthMm = valid(widthMm)
        result.heightMm = valid(heightMm)
        result.wheelbaseMm = valid(wheelbaseMm)
        return result
    }

    var hasReferenceDimensions: Bool {
        lengthMm != nil || widthMm != nil || heightMm != nil || wheelbaseMm != nil
    }

    var hasCompleteDimensions: Bool {
        lengthMm != nil && widthMm != nil && heightMm != nil && wheelbaseMm != nil
    }

    func fillingMissingValues(from old: VehicleSpecSheet) -> VehicleSpecSheet {
        var result = self
        result.lengthMm = lengthMm ?? old.lengthMm
        result.widthMm = widthMm ?? old.widthMm
        result.heightMm = heightMm ?? old.heightMm
        result.wheelbaseMm = wheelbaseMm ?? old.wheelbaseMm
        result.fuelTankLiters = fuelTankLiters ?? old.fuelTankLiters
        result.batteryKWh = batteryKWh ?? old.batteryKWh
        result.rangeKm = rangeKm ?? old.rangeKm
        result.fuelConsumption = fuelConsumption ?? old.fuelConsumption
        result.seats = seats ?? old.seats
        result.bodyStyle = bodyStyle ?? old.bodyStyle
        for feature in old.features where !result.features.contains(where: { $0.name == feature.name && $0.appliesTo == feature.appliesTo }) {
            result.features.append(feature)
        }
        return result
    }
}

enum VehicleInsightCacheState: String, Codable, Equatable {
    case cached, stale
}

extension VehicleInsight {
    var sourceLabel: String {
        switch cacheState {
        case .cached: return "本地参数缓存"
        case .stale: return "本地缓存 · 待更新"
        case nil: return origin.label
        }
    }
}

func mergeVehicleReference(_ cached: VehicleInsight, for listing: RentalListing, now: Date = Date()) -> VehicleInsight {
        let local = VehicleInsightLocalInferencer.localInsight(for: listing, now: now)
        var merged = cached
        merged.vehicleName = listing.vehicleName
        merged.configurationSummary = local.configurationSummary
        merged.trimConfidence = local.trimConfidence
        merged.shortSummary = local.shortSummary
        merged.modelYear = local.modelYear
        merged.modelYearConfidence = local.modelYearConfidence
        merged.specSheet.features = cached.specSheet.features.filter { $0.appliesTo != .platformListing } + local.specSheet.features
        merged.specSheet.seats = local.specSheet.seats ?? cached.specSheet.seats.flatMap { $0.appliesTo == .platformListing ? nil : $0 }
        merged.specSheet.bodyStyle = local.specSheet.bodyStyle ?? cached.specSheet.bodyStyle.flatMap { $0.appliesTo == .platformListing ? nil : $0 }
        merged.specSheet.batteryKWh = local.specSheet.batteryKWh ?? cached.specSheet.batteryKWh.flatMap { $0.appliesTo == .platformListing ? nil : $0 }
        let referenceSummary = cached.longSummary.components(separatedBy: "当前租赁车辆配置以平台返回为准：").first ?? cached.longSummary
        merged.longSummary = "\(referenceSummary.trimmingCharacters(in: .whitespacesAndNewlines)) 当前租赁车辆配置以平台返回为准：\(local.configurationSummary ?? "配置以平台返回为准")。下单前以平台确认页为准。"
        return merged
}
