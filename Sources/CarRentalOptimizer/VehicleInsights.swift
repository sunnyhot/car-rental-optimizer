import CarRentalDomain
import Foundation

enum VehicleInsightOrigin: String, Codable, Equatable {
    case localInference
    case network

    var label: String {
        switch self {
        case .localInference:
            return "本地推断"
        case .network:
            return "联网简介"
        }
    }
}

enum VehicleInsightConfidence: String, Codable, Equatable {
    case high
    case medium
    case low

    var label: String {
        switch self {
        case .high:
            return "高"
        case .medium:
            return "中"
        case .low:
            return "低"
        }
    }
}

enum VehicleSpecScope: String, Codable, Equatable {
    case series
    case modelYear
    case platformListing

    var label: String {
        switch self {
        case .series:
            return "车系参数"
        case .modelYear:
            return "年款参数"
        case .platformListing:
            return "平台配置"
        }
    }
}

struct VehicleSpecValue<Value: Codable & Equatable>: Codable, Equatable {
    var value: Value
    var sourceName: String
    var sourceURL: String?
    var confidence: VehicleInsightConfidence
    var appliesTo: VehicleSpecScope
}

struct VehicleFeature: Codable, Equatable, Identifiable {
    var id: String { "\(name)-\(sourceName)-\(appliesTo.rawValue)" }
    var name: String
    var sourceName: String
    var confidence: VehicleInsightConfidence
    var appliesTo: VehicleSpecScope
}

struct VehicleSpecSheet: Codable, Equatable {
    var lengthMm: VehicleSpecValue<Int>?
    var widthMm: VehicleSpecValue<Int>?
    var heightMm: VehicleSpecValue<Int>?
    var wheelbaseMm: VehicleSpecValue<Int>?
    var fuelTankLiters: VehicleSpecValue<Double>?
    var batteryKWh: VehicleSpecValue<Double>?
    var rangeKm: VehicleSpecValue<Int>?
    var fuelConsumption: VehicleSpecValue<String>?
    var seats: VehicleSpecValue<Int>?
    var bodyStyle: VehicleSpecValue<String>?
    var features: [VehicleFeature] = []
}

struct VehicleInsightFact: Equatable, Identifiable {
    var id: String { label }
    let label: String
    let value: String
    let scopeLabel: String?
}

struct VehicleInsight: Codable, Equatable {
    var vehicleName: String
    var seriesName: String
    var specSheet: VehicleSpecSheet
    var configurationSummary: String?
    var modelYear: String?
    var modelYearConfidence: VehicleInsightConfidence
    var trimConfidence: VehicleInsightConfidence
    var shortSummary: String
    var longSummary: String
    var sourceName: String
    var sourceURL: String?
    var fetchedAt: Date?
    var confidence: VehicleInsightConfidence
    var origin: VehicleInsightOrigin

    var platformFeatures: [VehicleFeature] {
        specSheet.features.filter { $0.appliesTo == .platformListing }
    }

    var formattedBasicSpecs: [VehicleInsightFact] {
        var facts: [VehicleInsightFact] = []
        if let length = specSheet.lengthMm, let width = specSheet.widthMm, let height = specSheet.heightMm {
            facts.append(VehicleInsightFact(
                label: "长宽高",
                value: "\(length.value)x\(width.value)x\(height.value)mm",
                scopeLabel: mergedScopeLabel([length.appliesTo, width.appliesTo, height.appliesTo])
            ))
        } else {
            appendIntFact(&facts, label: "车长", value: specSheet.lengthMm, suffix: "mm")
            appendIntFact(&facts, label: "车宽", value: specSheet.widthMm, suffix: "mm")
            appendIntFact(&facts, label: "车高", value: specSheet.heightMm, suffix: "mm")
        }
        appendIntFact(&facts, label: "轴距", value: specSheet.wheelbaseMm, suffix: "mm", unknown: "未确认")
        appendIntFact(&facts, label: "座位数", value: specSheet.seats, suffix: "座")
        if let fuelTankLiters = specSheet.fuelTankLiters {
            facts.append(VehicleInsightFact(label: "油箱", value: formatVehicleInsightNumber(fuelTankLiters.value) + "L", scopeLabel: fuelTankLiters.appliesTo.label))
        }
        if let batteryKWh = specSheet.batteryKWh {
            facts.append(VehicleInsightFact(label: "电池容量", value: formatVehicleInsightNumber(batteryKWh.value) + "kWh", scopeLabel: batteryKWh.appliesTo.label))
        }
        if specSheet.fuelTankLiters == nil && specSheet.batteryKWh == nil {
            facts.append(VehicleInsightFact(label: "油箱/电池", value: "未确认", scopeLabel: nil))
        }
        appendIntFact(&facts, label: "续航", value: specSheet.rangeKm, suffix: "km")
        if let fuelConsumption = specSheet.fuelConsumption {
            facts.append(VehicleInsightFact(label: "油耗", value: fuelConsumption.value, scopeLabel: fuelConsumption.appliesTo.label))
        }
        if let bodyStyle = specSheet.bodyStyle {
            facts.append(VehicleInsightFact(label: "车身形式", value: bodyStyle.value, scopeLabel: bodyStyle.appliesTo.label))
        }
        return facts
    }

    private func appendIntFact(
        _ facts: inout [VehicleInsightFact],
        label: String,
        value: VehicleSpecValue<Int>?,
        suffix: String,
        unknown: String? = nil
    ) {
        if let value {
            facts.append(VehicleInsightFact(label: label, value: "\(value.value)\(suffix)", scopeLabel: value.appliesTo.label))
        } else if let unknown {
            facts.append(VehicleInsightFact(label: label, value: unknown, scopeLabel: nil))
        }
    }

    private func mergedScopeLabel(_ scopes: [VehicleSpecScope]) -> String {
        scopes.contains(.platformListing) ? VehicleSpecScope.platformListing.label : scopes[0].label
    }
}

enum VehicleInsightLocalInferencer {
    static func localInsight(for listing: RentalListing, now: Date = Date()) -> VehicleInsight {
        let vehicleText = "\(listing.vehicleName) \(listing.vehicleClass)"
        let sourceName = "\(listing.platform.label)平台"
        let platformSourceURL = listing.sourceUrl.isEmpty ? nil : listing.sourceUrl
        let energy = energySignal(in: vehicleText)
        let bodyStyle = bodyStyleSignal(in: vehicleText)
        let seats = intMatch(in: vehicleText, pattern: #"(\d+)\s*座"#)
        let battery = doubleMatch(in: vehicleText, pattern: #"(\d+(?:\.\d+)?)\s*kWh"#)
        let modelYear = explicitModelYear(in: vehicleText)
        let features = platformFeatures(in: vehicleText, sourceName: sourceName)
        let configurationParts = configurationParts(energy: energy, bodyStyle: bodyStyle, seats: seats, battery: battery, features: features)
        let summary = configurationParts.joined(separator: "、")

        var specSheet = VehicleSpecSheet()
        specSheet.batteryKWh = battery.map {
            VehicleSpecValue(value: $0, sourceName: sourceName, sourceURL: platformSourceURL, confidence: .high, appliesTo: .platformListing)
        }
        specSheet.seats = seats.map {
            VehicleSpecValue(value: $0, sourceName: sourceName, sourceURL: platformSourceURL, confidence: .high, appliesTo: .platformListing)
        }
        specSheet.bodyStyle = bodyStyle.map {
            VehicleSpecValue(value: $0, sourceName: sourceName, sourceURL: platformSourceURL, confidence: .high, appliesTo: .platformListing)
        }
        specSheet.features = features

        let shortSummary = shortSummary(energy: energy, bodyStyle: bodyStyle, seats: seats, battery: battery)
        let yearCopy = modelYear ?? "年款未确认"
        let configurationCopy = summary.isEmpty ? "配置以平台返回为准" : summary
        return VehicleInsight(
            vehicleName: listing.vehicleName,
            seriesName: normalizedSeriesName(listing.vehicleName),
            specSheet: specSheet,
            configurationSummary: summary.isEmpty ? nil : summary,
            modelYear: modelYear,
            modelYearConfidence: modelYear == nil ? .low : .high,
            trimConfidence: summary.isEmpty ? .low : .medium,
            shortSummary: shortSummary,
            longSummary: "车系介绍：本地根据平台返回字段推断车型特征。\(yearCopy)。当前租赁车辆配置以平台返回为准：\(configurationCopy)。下单前以平台确认页为准。",
            sourceName: sourceName,
            sourceURL: platformSourceURL,
            fetchedAt: now,
            confidence: summary.isEmpty ? .low : .medium,
            origin: .localInference
        )
    }

    static func normalizedQuery(for listing: RentalListing) -> String {
        normalizedSeriesName(listing.vehicleName)
    }

    static func normalizedSeriesName(_ value: String) -> String {
        var result = value
        let patterns = [
            #"\d{4}款"#,
            #"\d+(?:\.\d+)?\s*kWh"#,
            #"\d+(?:\.\d+)?T"#,
            #"\d+(?:\.\d+)?L"#,
            #"\d+\s*座"#,
            #"自动"#,
            #"手动"#,
            #"新能源"#,
            #"纯电"#,
            #"插电混"#,
            #"混动"#
        ]
        for pattern in patterns {
            result = result.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private static func configurationParts(
        energy: String?,
        bodyStyle: String?,
        seats: Int?,
        battery: Double?,
        features: [VehicleFeature]
    ) -> [String] {
        var parts: [String] = []
        if let energy { parts.append(energy) }
        if let bodyStyle { parts.append(bodyStyle) }
        if let seats { parts.append("\(seats)座") }
        if let battery { parts.append(formatVehicleInsightNumber(battery) + "kWh") }
        parts.append(contentsOf: features.map(\.name))
        return parts
    }

    private static func shortSummary(energy: String?, bodyStyle: String?, seats: Int?, battery: Double?) -> String {
        let seatCopy = seats.map { " \($0)座" } ?? ""
        let batteryCopy = battery.map { "，\(formatVehicleInsightNumber($0))kWh" } ?? ""
        switch energy {
        case "纯电":
            let bodyCopy = bodyStyle ?? ""
            return "平台标注：纯电\(bodyCopy)\(seatCopy)\(batteryCopy)；适合市内/短途出行，长途注意补能。"
        case "插电混":
            let bodyCopy = bodyStyle.map { " \($0)" } ?? ""
            return "平台标注：插电混\(bodyCopy)\(seatCopy)；适合多人和行李，长途补能压力低于纯电。"
        default:
            if let bodyStyle, bodyStyle == "SUV" || bodyStyle == "MPV" {
                return "平台标注：\(bodyStyle)\(seatCopy)；适合多人和行李，注意停车和油耗成本。"
            }
            return "平台标注：\(bodyStyle ?? "车型")\(seatCopy)；适合常规城市和城际出行。"
        }
    }

    private static func energySignal(in text: String) -> String? {
        if text.contains("纯电") || text.localizedCaseInsensitiveContains("EV") {
            return "纯电"
        }
        if text.contains("插电") || text.contains("插混") || text.localizedCaseInsensitiveContains("DM-i") {
            return "插电混"
        }
        if text.contains("混动") {
            return "混动"
        }
        return nil
    }

    private static func bodyStyleSignal(in text: String) -> String? {
        if text.localizedCaseInsensitiveContains("SUV") {
            return "SUV"
        }
        if text.localizedCaseInsensitiveContains("MPV") || text.contains("商务") {
            return "MPV"
        }
        if text.contains("三厢") {
            return "三厢"
        }
        if text.contains("两厢") {
            return "两厢"
        }
        return nil
    }

    private static func explicitModelYear(in text: String) -> String? {
        guard let match = text.range(of: #"\d{4}款"#, options: .regularExpression) else { return nil }
        return String(text[match])
    }

    private static func platformFeatures(in text: String, sourceName: String) -> [VehicleFeature] {
        let candidates = [
            ("倒车影像", "倒车影像"),
            ("360影像", "360影像"),
            ("360度影像", "360影像"),
            ("手机无线充电", "手机无线充电"),
            ("无线充电", "无线充电"),
            ("天窗", "天窗"),
            ("后排隐私玻璃", "后排隐私玻璃"),
            ("电动后尾门", "电动后尾门"),
            ("电动尾门", "电动尾门"),
            ("倒车雷达", "倒车雷达"),
            ("蓝牙", "蓝牙")
        ]
        var names: [String] = []
        for (token, name) in candidates where text.contains(token) {
            if name == "无线充电", names.contains("手机无线充电") {
                continue
            }
            if name == "电动尾门", names.contains("电动后尾门") {
                continue
            }
            if !names.contains(name) {
                names.append(name)
            }
        }
        if let ageMatch = text.range(of: #"车龄\s*\d+\s*年内"#, options: .regularExpression) {
            names.append(String(text[ageMatch]).replacingOccurrences(of: " ", with: ""))
        }
        return names.map {
            VehicleFeature(name: $0, sourceName: sourceName, confidence: .high, appliesTo: .platformListing)
        }
    }

    private static func intMatch(in text: String, pattern: String) -> Int? {
        guard let value = capture(in: text, pattern: pattern) else { return nil }
        return Int(value)
    }

    private static func doubleMatch(in text: String, pattern: String) -> Double? {
        guard let value = capture(in: text, pattern: pattern) else { return nil }
        return Double(value)
    }

    private static func capture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range])
    }
}

func formatVehicleInsightNumber(_ value: Double) -> String {
    value.rounded() == value ? "\(Int(value))" : String(format: "%.1f", value)
}

protocol VehicleInsightProviding: AnyObject {
    func localInsight(for listing: RentalListing) -> VehicleInsight
    func insight(for listing: RentalListing) async -> VehicleInsight
}

final class VehicleInsightService: VehicleInsightProviding {
    private let store: VehicleInsightStore
    private let networkProvider: VehicleInsightNetworkProvider
    private let now: () -> Date

    init(
        store: VehicleInsightStore = VehicleInsightStore(),
        networkProvider: VehicleInsightNetworkProvider = VehicleInsightNetworkProvider(httpClient: URLSessionVehicleInsightHTTPClient()),
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.networkProvider = networkProvider
        self.now = now
    }

    func localInsight(for listing: RentalListing) -> VehicleInsight {
        VehicleInsightLocalInferencer.localInsight(for: listing, now: now())
    }

    func insight(for listing: RentalListing) async -> VehicleInsight {
        let key = VehicleInsightLocalInferencer.normalizedQuery(for: listing)
        if let cached = store.cachedInsight(forKey: key, now: now()) {
            return merge(cached, withLocalConfigurationFrom: listing)
        }
        if let network = await networkProvider.networkInsight(for: listing, now: now()) {
            store.save(network, forKey: key, now: now())
            return network
        }
        return localInsight(for: listing)
    }

    private func merge(_ cached: VehicleInsight, withLocalConfigurationFrom listing: RentalListing) -> VehicleInsight {
        let local = localInsight(for: listing)
        var merged = cached
        merged.vehicleName = listing.vehicleName
        merged.configurationSummary = local.configurationSummary
        merged.trimConfidence = local.trimConfidence
        merged.shortSummary = local.shortSummary
        merged.specSheet.features = local.specSheet.features
        if let seats = local.specSheet.seats {
            merged.specSheet.seats = seats
        }
        if let bodyStyle = local.specSheet.bodyStyle {
            merged.specSheet.bodyStyle = bodyStyle
        }
        if let battery = local.specSheet.batteryKWh {
            merged.specSheet.batteryKWh = battery
        }
        merged.longSummary = "\(cached.longSummary) 当前租赁车辆配置以平台返回为准：\(local.configurationSummary ?? "配置以平台返回为准")。"
        return merged
    }
}
