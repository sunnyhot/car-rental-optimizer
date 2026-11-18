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
    var cacheState: VehicleInsightCacheState? = nil
    var referenceRetryAfter: Date? = nil
    var referenceSourceURLs: [String]? = nil

    var platformFeatures: [VehicleFeature] {
        specSheet.features.filter { $0.appliesTo == .platformListing }
    }

    var formattedConfigurationFacts: [VehicleInsightFact] {
        VehicleInsight.commonConfigurationFeatureNames.map { name in
            let matchingFeatures = specSheet.features.filter { $0.name == name }
            if let platformFeature = matchingFeatures.first(where: { $0.appliesTo == .platformListing }) {
                return VehicleInsightFact(label: name, value: "平台确认", scopeLabel: platformFeature.sourceName)
            }
            if let modelYearFeature = matchingFeatures.first(where: { $0.appliesTo == .modelYear }) {
                return VehicleInsightFact(label: name, value: "年款参考", scopeLabel: modelYearFeature.sourceName)
            }
            if let seriesFeature = matchingFeatures.first(where: { $0.appliesTo == .series }) {
                return VehicleInsightFact(label: name, value: "车型库参考", scopeLabel: seriesFeature.sourceName)
            }
            return VehicleInsightFact(label: name, value: "未确认", scopeLabel: nil)
        }
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
            appendIntFact(&facts, label: "车长", value: specSheet.lengthMm, suffix: "mm", unknown: "未确认")
            appendIntFact(&facts, label: "车宽", value: specSheet.widthMm, suffix: "mm", unknown: "未确认")
            appendIntFact(&facts, label: "车高", value: specSheet.heightMm, suffix: "mm", unknown: "未确认")
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

    static let commonConfigurationFeatureNames = [
        "倒车影像",
        "360影像",
        "倒车雷达",
        "蓝牙",
        "CarPlay",
        "手机无线充电",
        "天窗",
        "无钥匙进入",
        "座椅加热",
        "定速巡航",
        "自适应巡航",
        "后排隐私玻璃",
        "电动尾门"
    ]
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
            #"^(?:19|20)\d{2}(?:款)?\s*"#,
            #"\d{4}款"#,
            #"\d+(?:\.\d+)?\s*kWh"#,
            #"(?<![A-Za-z0-9])\d+(?:\.\d+)?T\b"#,
            #"(?<![A-Za-z0-9])\d+(?:\.\d+)?L\b"#,
            #"\d+\s*座"#,
            #"自动"#,
            #"手动"#
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
            ("倒车视频影像", "倒车影像"),
            ("后视摄像头", "倒车影像"),
            ("360影像", "360影像"),
            ("360度影像", "360影像"),
            ("全景影像", "360影像"),
            ("手机无线充电", "手机无线充电"),
            ("无线充电", "无线充电"),
            ("天窗", "天窗"),
            ("后排隐私玻璃", "后排隐私玻璃"),
            ("电动后尾门", "电动后尾门"),
            ("电动尾门", "电动尾门"),
            ("倒车雷达", "倒车雷达"),
            ("蓝牙", "蓝牙"),
            ("CarPlay", "CarPlay"),
            ("手机互联", "CarPlay"),
            ("车机互联", "CarPlay"),
            ("无钥匙进入", "无钥匙进入"),
            ("座椅加热", "座椅加热"),
            ("定速巡航", "定速巡航"),
            ("自适应巡航", "自适应巡航"),
            ("ACC", "自适应巡航")
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

@MainActor
protocol VehicleInsightProviding: AnyObject {
    func localInsight(for listing: RentalListing) -> VehicleInsight
    func insight(for listing: RentalListing) async -> VehicleInsight
    func refreshInsight(for listing: RentalListing) async -> VehicleInsight
}

extension VehicleInsightProviding {
    func refreshInsight(for listing: RentalListing) async -> VehicleInsight { await insight(for: listing) }
}

final class LocalOnlyVehicleInsightService: VehicleInsightProviding {
    func localInsight(for listing: RentalListing) -> VehicleInsight { VehicleInsightLocalInferencer.localInsight(for: listing) }
    func insight(for listing: RentalListing) async -> VehicleInsight { localInsight(for: listing) }
}

final class VehicleInsightService: VehicleInsightProviding {
    private let store: VehicleInsightStore
    private let networkProvider: VehicleInsightNetworkProvider
    private let now: () -> Date
    private var inFlight: [String: Task<VehicleInsight?, Never>] = [:]
    private var lastAttempts: [String: Date] = [:]
    private var rateLimitedKeys = Set<String>()
    private let requestGate = VehicleReferenceRequestGate(limit: 2)

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
        let key = VehicleInsightLocalInferencer.normalizedQuery(for: listing)
        if let cached = store.cachedInsight(forKey: key, now: now()) {
            return merge(cached, withLocalConfigurationFrom: listing)
        }
        return VehicleInsightLocalInferencer.localInsight(for: listing, now: now())
    }

    func insight(for listing: RentalListing) async -> VehicleInsight {
        await loadInsight(for: listing, forceRefresh: false)
    }

    func refreshInsight(for listing: RentalListing) async -> VehicleInsight {
        await loadInsight(for: listing, forceRefresh: true)
    }

    private func loadInsight(for listing: RentalListing, forceRefresh: Bool) async -> VehicleInsight {
        let query = VehicleInsightLocalInferencer.normalizedQuery(for: listing)
        let key = VehicleInsightStore.normalizedCacheKey(query)
        if let pending = inFlight[key] {
            if let result = await pending.value { return merge(result, withLocalConfigurationFrom: listing) }
            return localInsight(for: listing)
        }
        if !forceRefresh, !rateLimitedKeys.contains(key), let cached = store.cachedInsight(forKey: key, now: now()), !store.needsRefresh(forKey: key, now: now()) {
            return merge(cached, withLocalConfigurationFrom: listing)
        }
        if !forceRefresh, !rateLimitedKeys.contains(key), let last = lastAttempts[key], now().timeIntervalSince(last) < 300 { return localInsight(for: listing) }
        rateLimitedKeys.remove(key)
        lastAttempts[key] = now()
        store.recordRefreshAttempt(forKey: key, now: now())
        let provider = networkProvider
        let timestamp = now()
        let gate = requestGate
        let task = Task {
            await gate.acquire()
            var value = await provider.networkInsight(for: listing, now: timestamp)
            if value == nil, let retry = await provider.httpClient.retryAfterDate() {
                var deferred = VehicleInsightLocalInferencer.localInsight(for: listing, now: timestamp)
                deferred.referenceRetryAfter = retry
                value = deferred
            }
            await gate.release()
            return value
        }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        if let network = await task.value {
            if let retry = network.referenceRetryAfter {
                rateLimitedKeys.insert(key)
                var fallback = localInsight(for: listing)
                fallback.referenceRetryAfter = retry
                return fallback
            }
            store.save(network, forKey: key, now: now())
            store.recordRefreshAttempt(forKey: key, now: now())
            if let persisted = store.cachedInsight(forKey: key, now: now()) {
                return merge(persisted, withLocalConfigurationFrom: listing)
            }
            return merge(network, withLocalConfigurationFrom: listing)
        }
        return localInsight(for: listing)
    }

    private func merge(_ cached: VehicleInsight, withLocalConfigurationFrom listing: RentalListing) -> VehicleInsight {
        mergeVehicleReference(cached, for: listing, now: now())
    }
}
