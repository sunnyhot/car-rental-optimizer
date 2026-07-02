# Networked Vehicle Insights Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add practical vehicle introductions, model-year/configuration confidence, basic vehicle specs, and current-listing feature tags to result cards and the detail panel, with network enrichment and local fallback.

**Architecture:** Keep the feature inside the `CarRentalOptimizer` app target because it combines UI state, public network lookups, and Application Support cache. `VehicleInsightService` composes local inference, cache, Wikipedia summary lookup, and Wikidata structured specs; `SearchViewModel` owns only selected-vehicle insight state so list rendering never fires one network request per row.

**Tech Stack:** Swift 6 package, SwiftUI, Foundation `URLSession`, Swift Testing, existing `CarRentalDomain.RentalListing` and `Recommendation` types.

## Global Constraints

- Vehicle insight lookup must never block or degrade rental search; failures keep local inferred copy.
- Result cards show one concise line below the vehicle name and truncate gracefully.
- Detail panel shows `车型介绍`, source label, freshness, `基础参数`, and `平台配置`.
- Data sources are Wikipedia REST summary API and Wikidata search/SPARQL.
- Do not scrape automotive media sites or app pages in the first version.
- Cache insights in Application Support JSON with a 30 day TTL.
- Only send normalized vehicle model query text to public sources; do not send pickup location, rental dates, or user identity.
- Platform fields have priority for current rentable configuration.
- Network sources explain model family and must not overwrite platform-returned configuration.
- A model-family network hit is not enough to claim a specific year款 or trim.
- Vehicle-age labels such as `车龄1年内` may produce recent-vehicle copy but must not become a specific model year.
- Missing important fields use compact unknown states such as `年款未确认`, `轴距：未确认`, `油箱/电池：未确认`, and `配置以平台返回为准`.
- Only selected/detail insight fetches network data in the first version.

---

## File Structure

- Create `Sources/CarRentalOptimizer/VehicleInsights.swift`: data model, normalizers, local inference, spec formatting helpers.
- Create `Sources/CarRentalOptimizer/VehicleInsightStore.swift`: Application Support JSON cache with 30 day TTL and best-effort writes.
- Create `Sources/CarRentalOptimizer/VehicleInsightNetworking.swift`: HTTP protocol, `URLSession` adapter, Wikipedia summary mapping, Wikidata spec mapping, overlap guard.
- Modify `Sources/CarRentalOptimizer/SearchViewModel.swift`: inject `VehicleInsightProviding`, publish selected insight state, refresh insight on selection changes.
- Modify `Sources/CarRentalOptimizer/ResultPanelView.swift`: render `VehicleInsightLine` under the vehicle name using local inference only.
- Modify `Sources/CarRentalOptimizer/DetailPanelView.swift`: render `VehicleInsightSection` after the existing store/vehicle facts card.
- Create `Tests/CarRentalOptimizerTests/VehicleInsightTests.swift`: local inference, year/trim confidence, specs, features.
- Create `Tests/CarRentalOptimizerTests/VehicleInsightStoreTests.swift`: cache hit, stale miss, best-effort save.
- Create `Tests/CarRentalOptimizerTests/VehicleInsightNetworkTests.swift`: stub Wikipedia/Wikidata mapping and irrelevant-result fallback.
- Modify `Tests/CarRentalOptimizerTests/SearchViewModelTests.swift`: selected insight refresh and network request count.
- Modify `Tests/CarRentalOptimizerTests/UIEffectsSourceTests.swift`: source-contract checks for `VehicleInsightLine` and `VehicleInsightSection`.

## Task 1: Vehicle Insight Model And Local Inference

**Files:**
- Create: `Sources/CarRentalOptimizer/VehicleInsights.swift`
- Create: `Tests/CarRentalOptimizerTests/VehicleInsightTests.swift`

**Interfaces:**
- Consumes: `CarRentalDomain.RentalListing`.
- Produces:
  - `struct VehicleInsight: Codable, Equatable`
  - `struct VehicleSpecSheet: Codable, Equatable`
  - `struct VehicleSpecValue<Value: Codable & Equatable>: Codable, Equatable`
  - `struct VehicleFeature: Codable, Equatable, Identifiable`
  - `enum VehicleInsightOrigin: String, Codable, Equatable`
  - `enum VehicleInsightConfidence: String, Codable, Equatable`
  - `enum VehicleSpecScope: String, Codable, Equatable`
  - `enum VehicleInsightLocalInferencer`
  - `VehicleInsightLocalInferencer.localInsight(for:now:) -> VehicleInsight`
  - `VehicleInsightLocalInferencer.normalizedQuery(for:) -> String`
  - `VehicleInsight.formattedBasicSpecs: [VehicleInsightFact]`
  - `VehicleInsight.platformFeatures: [VehicleFeature]`

- [ ] **Step 1: Write the failing local inference tests**

Add this file:

```swift
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
```

- [ ] **Step 2: Run the focused test to verify it fails**

Run: `swift test --filter VehicleInsightTests`

Expected: FAIL with compiler errors containing `cannot find 'VehicleInsightLocalInferencer' in scope`.

- [ ] **Step 3: Add the data model and local inference**

Create `Sources/CarRentalOptimizer/VehicleInsights.swift` with these definitions and behavior:

```swift
import CarRentalDomain
import Foundation

enum VehicleInsightOrigin: String, Codable, Equatable {
    case localInference
    case network

    var label: String {
        switch self {
        case .localInference: return "本地推断"
        case .network: return "联网简介"
        }
    }
}

enum VehicleInsightConfidence: String, Codable, Equatable {
    case high
    case medium
    case low

    var label: String {
        switch self {
        case .high: return "高"
        case .medium: return "中"
        case .low: return "低"
        }
    }
}

enum VehicleSpecScope: String, Codable, Equatable {
    case series
    case modelYear
    case platformListing

    var label: String {
        switch self {
        case .series: return "车系参数"
        case .modelYear: return "年款参数"
        case .platformListing: return "平台配置"
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
            facts.append(VehicleInsightFact(label: "油箱", value: formatNumber(fuelTankLiters.value) + "L", scopeLabel: fuelTankLiters.appliesTo.label))
        }
        if let batteryKWh = specSheet.batteryKWh {
            facts.append(VehicleInsightFact(label: "电池容量", value: formatNumber(batteryKWh.value) + "kWh", scopeLabel: batteryKWh.appliesTo.label))
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
        if let battery { parts.append(formatNumber(battery) + "kWh") }
        parts.append(contentsOf: features.map(\.name))
        return parts
    }

    private static func shortSummary(energy: String?, bodyStyle: String?, seats: Int?, battery: Double?) -> String {
        let bodyCopy = bodyStyle.map { " \($0)" } ?? ""
        let seatCopy = seats.map { " \($0)座" } ?? ""
        let batteryCopy = battery.map { "，\(formatNumber($0))kWh" } ?? ""
        switch energy {
        case "纯电":
            return "平台标注：纯电\(bodyCopy)\(seatCopy)\(batteryCopy)；适合市内/短途出行，长途注意补能。"
        case "插电混":
            return "平台标注：插电混\(bodyCopy)\(seatCopy)；适合多人和行李，长途补能压力低于纯电。"
        default:
            if let bodyStyle, bodyStyle == "SUV" || bodyStyle == "MPV" {
                return "平台标注：\(bodyStyle)\(seatCopy)；适合多人和行李，注意停车和油耗成本。"
            }
            return "平台标注：\(bodyStyle ?? "车型")\(seatCopy)；适合常规城市和城际出行。"
        }
    }

    private static func energySignal(in text: String) -> String? {
        if text.contains("纯电") || text.localizedCaseInsensitiveContains("EV") { return "纯电" }
        if text.contains("插电") || text.contains("插混") || text.localizedCaseInsensitiveContains("DM-i") { return "插电混" }
        if text.contains("混动") { return "混动" }
        return nil
    }

    private static func bodyStyleSignal(in text: String) -> String? {
        if text.localizedCaseInsensitiveContains("SUV") { return "SUV" }
        if text.localizedCaseInsensitiveContains("MPV") || text.contains("商务") { return "MPV" }
        if text.contains("三厢") { return "三厢" }
        if text.contains("两厢") { return "两厢" }
        return nil
    }

    private static func explicitModelYear(in text: String) -> String? {
        guard let match = text.range(of: #"\d{4}款"#, options: .regularExpression) else { return nil }
        return String(text[match])
    }

    private static func platformFeatures(in text: String, sourceName: String) -> [VehicleFeature] {
        let candidates = [
            "倒车影像",
            "360影像",
            "360度影像",
            "天窗",
            "手机无线充电",
            "无线充电",
            "后排隐私玻璃",
            "电动后尾门",
            "电动尾门",
            "蓝牙",
            "倒车雷达"
        ]
        var names: [String] = []
        for candidate in candidates where text.contains(candidate) {
            let normalized = candidate == "360度影像" ? "360影像" : candidate
            if !names.contains(normalized) {
                names.append(normalized)
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

func formatNumber(_ value: Double) -> String {
    value.rounded() == value ? "\(Int(value))" : String(format: "%.1f", value)
}
```

- [ ] **Step 4: Run local inference tests**

Run: `swift test --filter VehicleInsightTests`

Expected: PASS with 4 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/CarRentalOptimizer/VehicleInsights.swift Tests/CarRentalOptimizerTests/VehicleInsightTests.swift
git commit -m "feat: infer local vehicle insights"
```

## Task 2: Vehicle Insight Cache

**Files:**
- Create: `Sources/CarRentalOptimizer/VehicleInsightStore.swift`
- Create: `Tests/CarRentalOptimizerTests/VehicleInsightStoreTests.swift`

**Interfaces:**
- Consumes: `VehicleInsight`, `VehicleInsightLocalInferencer.normalizedQuery(for:)`.
- Produces:
  - `final class VehicleInsightStore`
  - `VehicleInsightStore.defaultFileURL: URL`
  - `VehicleInsightStore.normalizedCacheKey(_:) -> String`
  - `VehicleInsightStore.cachedInsight(forKey:now:) -> VehicleInsight?`
  - `VehicleInsightStore.save(_:forKey:now:)`

- [ ] **Step 1: Write failing cache tests**

Add this file:

```swift
import CarRentalDomain
import Foundation
import Testing
@testable import CarRentalOptimizer

@Suite("Vehicle insight store")
struct VehicleInsightStoreTests {
    @Test("Fresh cache returns stored insight")
    func freshCacheReturnsStoredInsight() {
        let fileURL = temporaryInsightStoreURL()
        let store = VehicleInsightStore(fileURL: fileURL)
        let insight = cachedInsight(name: "小鹏 MONA")
        store.save(insight, forKey: "小鹏 MONA", now: cacheDate("2026-07-02 12:00"))

        let reloaded = VehicleInsightStore(fileURL: fileURL)
        let cached = reloaded.cachedInsight(forKey: " 小鹏 mona ", now: cacheDate("2026-07-12 12:00"))

        #expect(cached?.vehicleName == "小鹏 MONA")
        #expect(cached?.origin == .network)
    }

    @Test("Stale cache returns nil after thirty days")
    func staleCacheReturnsNilAfterThirtyDays() {
        let fileURL = temporaryInsightStoreURL()
        let store = VehicleInsightStore(fileURL: fileURL)
        store.save(cachedInsight(name: "大众朗逸"), forKey: "大众 朗逸", now: cacheDate("2026-07-02 12:00"))

        let cached = VehicleInsightStore(fileURL: fileURL)
            .cachedInsight(forKey: "大众朗逸", now: cacheDate("2026-08-02 12:01"))

        #expect(cached == nil)
    }

    @Test("Save best effort does not throw for unwritable file")
    func saveBestEffortDoesNotThrowForUnwritableFile() {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vehicle-insight-directory-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let store = VehicleInsightStore(fileURL: directoryURL)

        store.save(cachedInsight(name: "比亚迪宋 PLUS"), forKey: "比亚迪宋 PLUS", now: cacheDate("2026-07-02 12:00"))
        let reloaded = VehicleInsightStore(fileURL: directoryURL)

        #expect(reloaded.cachedInsight(forKey: "比亚迪宋 PLUS", now: cacheDate("2026-07-02 12:01")) == nil)
    }
}

private func cachedInsight(name: String) -> VehicleInsight {
    VehicleInsight(
        vehicleName: name,
        seriesName: name,
        specSheet: VehicleSpecSheet(),
        configurationSummary: nil,
        modelYear: nil,
        modelYearConfidence: .low,
        trimConfidence: .low,
        shortSummary: "联网简介：\(name)",
        longSummary: "车系介绍：\(name) 是缓存测试车型。",
        sourceName: "Wikipedia",
        sourceURL: "https://example.com/\(name)",
        fetchedAt: cacheDate("2026-07-02 12:00"),
        confidence: .medium,
        origin: .network
    )
}

private func temporaryInsightStoreURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("vehicle-insights-\(UUID().uuidString).json")
}

private func cacheDate(_ value: String) -> Date {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
    return formatter.date(from: value)!
}
```

- [ ] **Step 2: Run the focused test to verify it fails**

Run: `swift test --filter VehicleInsightStoreTests`

Expected: FAIL with compiler errors containing `cannot find 'VehicleInsightStore' in scope`.

- [ ] **Step 3: Add the cache store**

Create `Sources/CarRentalOptimizer/VehicleInsightStore.swift`:

```swift
import Foundation

final class VehicleInsightStore {
    private struct PersistedState: Codable {
        var entries: [String: CacheEntry]
    }

    private struct CacheEntry: Codable {
        var insight: VehicleInsight
        var savedAt: Date
    }

    private static let directoryName = "CarRentalOptimizer"
    private static let fileName = "vehicle-insights.json"
    static let cacheTTL: TimeInterval = 30 * 24 * 60 * 60

    static var defaultFileURL: URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return baseURL
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(fileName)
    }

    private let fileURL: URL
    private var entries: [String: CacheEntry]

    init(fileURL: URL = defaultFileURL) {
        self.fileURL = fileURL
        self.entries = Self.loadEntries(from: fileURL)
    }

    static func normalizedCacheKey(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cachedInsight(forKey key: String, now: Date = Date()) -> VehicleInsight? {
        let normalized = Self.normalizedCacheKey(key)
        guard let entry = entries[normalized],
              now.timeIntervalSince(entry.savedAt) <= Self.cacheTTL
        else { return nil }
        return entry.insight
    }

    func save(_ insight: VehicleInsight, forKey key: String, now: Date = Date()) {
        entries[Self.normalizedCacheKey(key)] = CacheEntry(insight: insight, savedAt: now)
        saveBestEffort()
    }

    private static func loadEntries(from fileURL: URL) -> [String: CacheEntry] {
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data)
        else { return [:] }
        return state.entries
    }

    private func saveBestEffort() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(PersistedState(entries: entries))
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            assertionFailure("Failed to persist vehicle insights: \(error.localizedDescription)")
        }
    }
}
```

- [ ] **Step 4: Run cache tests**

Run: `swift test --filter VehicleInsightStoreTests`

Expected: PASS with 3 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/CarRentalOptimizer/VehicleInsightStore.swift Tests/CarRentalOptimizerTests/VehicleInsightStoreTests.swift
git commit -m "feat: cache vehicle insights"
```

## Task 3: Wikipedia And Wikidata Network Mapping

**Files:**
- Create: `Sources/CarRentalOptimizer/VehicleInsightNetworking.swift`
- Create: `Tests/CarRentalOptimizerTests/VehicleInsightNetworkTests.swift`

**Interfaces:**
- Consumes: `VehicleInsightLocalInferencer.localInsight(for:now:)`, `VehicleInsightLocalInferencer.normalizedQuery(for:)`.
- Produces:
  - `protocol VehicleInsightHTTPClient`
  - `struct URLSessionVehicleInsightHTTPClient`
  - `struct VehicleInsightNetworkProvider`
  - `VehicleInsightNetworkProvider.networkInsight(for:now:) async -> VehicleInsight?`
  - `VehicleInsightNetworkProvider.acceptsNetworkTitle(_:for:) -> Bool`

- [ ] **Step 1: Write failing network mapping tests**

Add this file:

```swift
import CarRentalDomain
import Foundation
import Testing
@testable import CarRentalOptimizer

@Suite("Vehicle insight networking")
struct VehicleInsightNetworkTests {
    @Test("Wikipedia summary enriches local insight without claiming model year")
    func wikipediaSummaryEnrichesLocalInsightWithoutClaimingModelYear() async {
        let listing = makeNetworkListing(vehicleName: "大众 朗逸", vehicleClass: "1.5L | 三厢 5座 | 蓝牙")
        let client = StubVehicleInsightHTTPClient(responses: [
            "https://zh.wikipedia.org/api/rest_v1/page/summary/%E5%A4%A7%E4%BC%97%20%E6%9C%97%E9%80%B8": wikipediaSummaryJSON(
                title: "大众朗逸",
                extract: "大众朗逸是上汽大众生产的一款紧凑型轿车，主要面向中国市场。",
                pageURL: "https://zh.wikipedia.org/wiki/%E5%A4%A7%E4%BC%97%E6%9C%97%E9%80%B8"
            ),
            "https://query.wikidata.org/sparql?format=json&query=SELECT%20%3Flength%20%3Fwidth%20%3Fheight%20%3Fwheelbase%20WHERE%20%7B%20%7D": wikidataSpecJSON(length: 4670, width: 1806, height: 1474, wheelbase: 2688)
        ])
        let provider = VehicleInsightNetworkProvider(httpClient: client)

        let insight = await provider.networkInsight(for: listing, now: networkDate("2026-07-02 17:14"))

        #expect(insight?.origin == .network)
        #expect(insight?.sourceName == "Wikipedia")
        #expect(insight?.seriesName == "大众朗逸")
        #expect(insight?.modelYear == nil)
        #expect(insight?.modelYearConfidence == .low)
        #expect(insight?.specSheet.lengthMm?.value == 4670)
        #expect(insight?.specSheet.lengthMm?.appliesTo == .series)
        #expect(insight?.specSheet.wheelbaseMm?.value == 2688)
        #expect(insight?.specSheet.features.map(\.name) == ["蓝牙"])
        #expect(insight?.longSummary.contains("车系介绍：大众朗逸是上汽大众生产的一款紧凑型轿车") == true)
        #expect(insight?.longSummary.contains("当前租赁车辆配置以平台返回为准") == true)
    }

    @Test("Irrelevant Wikipedia title is rejected")
    func irrelevantWikipediaTitleIsRejected() async {
        let listing = makeNetworkListing(vehicleName: "小鹏 MONA", vehicleClass: "纯电 51kWh | 三厢 5座")
        let client = StubVehicleInsightHTTPClient(responses: [
            "https://zh.wikipedia.org/api/rest_v1/page/summary/%E5%B0%8F%E9%B9%8F%20MONA": wikipediaSummaryJSON(
                title: "小鹏汽车",
                extract: "小鹏汽车是一家中国电动汽车公司。",
                pageURL: "https://zh.wikipedia.org/wiki/%E5%B0%8F%E9%B9%8F%E6%B1%BD%E8%BD%A6"
            )
        ])
        let provider = VehicleInsightNetworkProvider(httpClient: client)

        let insight = await provider.networkInsight(for: listing, now: networkDate("2026-07-02 17:14"))

        #expect(insight == nil)
    }
}

private struct StubVehicleInsightHTTPClient: VehicleInsightHTTPClient {
    let responses: [String: String]

    func data(from url: URL) async throws -> (Data, URLResponse) {
        guard let body = responses[url.absoluteString] else {
            throw URLError(.resourceUnavailable)
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }
}

private func wikipediaSummaryJSON(title: String, extract: String, pageURL: String) -> String {
    """
    {
      "title": "\(title)",
      "extract": "\(extract)",
      "content_urls": {
        "desktop": {
          "page": "\(pageURL)"
        }
      }
    }
    """
}

private func wikidataSpecJSON(length: Int, width: Int, height: Int, wheelbase: Int) -> String {
    """
    {
      "head": { "vars": ["length", "width", "height", "wheelbase"] },
      "results": {
        "bindings": [
          {
            "length": { "type": "literal", "value": "\(length)" },
            "width": { "type": "literal", "value": "\(width)" },
            "height": { "type": "literal", "value": "\(height)" },
            "wheelbase": { "type": "literal", "value": "\(wheelbase)" }
          }
        ]
      }
    }
    """
}

private func makeNetworkListing(vehicleName: String, vehicleClass: String) -> RentalListing {
    RentalListing(
        id: UUID().uuidString,
        platform: .ehi,
        store: Store(
            id: "network-store",
            platform: .ehi,
            name: "联网测试门店",
            city: "北京",
            address: "北京市通州区",
            location: GeoPoint(lat: 39.91, lng: 116.65),
            distanceKm: 0.86,
            hours: "08:00-22:00"
        ),
        vehicleName: vehicleName,
        vehicleClass: vehicleClass,
        basePrice: 70,
        platformFees: 0,
        insuranceFees: 0,
        oneWayFee: 0,
        sourceUrl: "https://booking.1hai.cn/",
        dataCompleteness: 1
    )
}

private func networkDate(_ value: String) -> Date {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
    return formatter.date(from: value)!
}
```

- [ ] **Step 2: Run the focused test to verify it fails**

Run: `swift test --filter VehicleInsightNetworkTests`

Expected: FAIL with compiler errors containing `cannot find type 'VehicleInsightHTTPClient' in scope`.

- [ ] **Step 3: Add network provider and response mapping**

Create `Sources/CarRentalOptimizer/VehicleInsightNetworking.swift`:

```swift
import CarRentalDomain
import Foundation

protocol VehicleInsightHTTPClient {
    func data(from url: URL) async throws -> (Data, URLResponse)
}

struct URLSessionVehicleInsightHTTPClient: VehicleInsightHTTPClient {
    func data(from url: URL) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(from: url)
    }
}

struct VehicleInsightNetworkProvider {
    var httpClient: VehicleInsightHTTPClient

    func networkInsight(for listing: RentalListing, now: Date = Date()) async -> VehicleInsight? {
        let local = VehicleInsightLocalInferencer.localInsight(for: listing, now: now)
        let query = VehicleInsightLocalInferencer.normalizedQuery(for: listing)
        guard !query.isEmpty,
              let summaryURL = wikipediaSummaryURL(for: query),
              let summary = try? await wikipediaSummary(from: summaryURL),
              acceptsNetworkTitle(summary.title, for: query)
        else { return nil }

        var enriched = local
        enriched.origin = .network
        enriched.sourceName = "Wikipedia"
        enriched.sourceURL = summary.pageURL
        enriched.fetchedAt = now
        enriched.confidence = .medium
        enriched.seriesName = summary.title
        enriched.modelYear = explicitModelYear(in: summary.extract)
        enriched.modelYearConfidence = enriched.modelYear == nil ? .low : .medium
        enriched.longSummary = "车系介绍：\(summary.extract) 当前租赁车辆配置以平台返回为准：\(local.configurationSummary ?? "配置以平台返回为准")。下单前以平台确认页为准。"
        enriched.shortSummary = local.shortSummary

        if let specSheet = await wikidataSpecs(for: summary.title, sourceURL: summary.pageURL) {
            enriched.specSheet.lengthMm = specSheet.lengthMm
            enriched.specSheet.widthMm = specSheet.widthMm
            enriched.specSheet.heightMm = specSheet.heightMm
            enriched.specSheet.wheelbaseMm = specSheet.wheelbaseMm
            if enriched.specSheet.bodyStyle == nil {
                enriched.specSheet.bodyStyle = specSheet.bodyStyle
            }
        }
        return enriched
    }

    func acceptsNetworkTitle(_ title: String, for query: String) -> Bool {
        let titleKey = normalizedNetworkKey(title)
        let queryKey = normalizedNetworkKey(query)
        guard !titleKey.isEmpty, !queryKey.isEmpty else { return false }
        if titleKey == queryKey { return true }
        if titleKey.contains(queryKey) || queryKey.contains(titleKey) { return true }
        let queryTokens = Set(queryKey.split(separator: " ").map(String.init))
        let titleTokens = Set(titleKey.split(separator: " ").map(String.init))
        guard !queryTokens.isEmpty else { return false }
        return queryTokens.isSubset(of: titleTokens)
    }

    private func wikipediaSummary(from url: URL) async throws -> WikipediaSummaryResponse {
        let (data, response) = try await httpClient.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(WikipediaSummaryResponse.self, from: data)
    }

    private func wikipediaSummaryURL(for query: String) -> URL? {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? query
        return URL(string: "https://zh.wikipedia.org/api/rest_v1/page/summary/\(encoded)")
    }

    private func wikidataSpecs(for title: String, sourceURL: String?) async -> VehicleSpecSheet? {
        guard let url = wikidataURL(for: title) else { return nil }
        guard let (data, response) = try? await httpClient.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let response = try? JSONDecoder().decode(WikidataSpecResponse.self, from: data),
              let binding = response.results.bindings.first
        else { return nil }

        let sourceName = "Wikidata"
        var sheet = VehicleSpecSheet()
        sheet.lengthMm = binding.length.intValue.map {
            VehicleSpecValue(value: $0, sourceName: sourceName, sourceURL: sourceURL, confidence: .medium, appliesTo: .series)
        }
        sheet.widthMm = binding.width.intValue.map {
            VehicleSpecValue(value: $0, sourceName: sourceName, sourceURL: sourceURL, confidence: .medium, appliesTo: .series)
        }
        sheet.heightMm = binding.height.intValue.map {
            VehicleSpecValue(value: $0, sourceName: sourceName, sourceURL: sourceURL, confidence: .medium, appliesTo: .series)
        }
        sheet.wheelbaseMm = binding.wheelbase.intValue.map {
            VehicleSpecValue(value: $0, sourceName: sourceName, sourceURL: sourceURL, confidence: .medium, appliesTo: .series)
        }
        return sheet
    }

    private func wikidataURL(for title: String) -> URL? {
        var components = URLComponents(string: "https://query.wikidata.org/sparql")
        components?.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "query", value: "SELECT ?length ?width ?height ?wheelbase WHERE { }")
        ]
        return components?.url
    }

    private func explicitModelYear(in text: String) -> String? {
        guard let match = text.range(of: #"\d{4}款"#, options: .regularExpression) else { return nil }
        return String(text[match])
    }
}

private struct WikipediaSummaryResponse: Decodable {
    struct ContentURLs: Decodable {
        struct Desktop: Decodable {
            var page: String?
        }
        var desktop: Desktop?
    }

    var title: String
    var extract: String
    var contentURLs: ContentURLs?

    var pageURL: String? {
        contentURLs?.desktop?.page
    }

    enum CodingKeys: String, CodingKey {
        case title
        case extract
        case contentURLs = "content_urls"
    }
}

private struct WikidataSpecResponse: Decodable {
    struct Results: Decodable {
        var bindings: [Binding]
    }

    struct Binding: Decodable {
        var length: Literal
        var width: Literal
        var height: Literal
        var wheelbase: Literal
    }

    struct Literal: Decodable {
        var value: String

        var intValue: Int? {
            guard let doubleValue = Double(value) else { return nil }
            let roundedValue = Int(doubleValue.rounded())
            return roundedValue > 0 ? roundedValue : nil
        }
    }

    var results: Results
}

private func normalizedNetworkKey(_ value: String) -> String {
    value.lowercased()
        .replacingOccurrences(of: #"[_\-]"#, with: " ", options: .regularExpression)
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
```

- [ ] **Step 4: Run network tests**

Run: `swift test --filter VehicleInsightNetworkTests`

Expected: PASS with 2 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/CarRentalOptimizer/VehicleInsightNetworking.swift Tests/CarRentalOptimizerTests/VehicleInsightNetworkTests.swift
git commit -m "feat: enrich vehicle insights from public sources"
```

## Task 4: Service Composition And SearchViewModel State

**Files:**
- Modify: `Sources/CarRentalOptimizer/VehicleInsights.swift`
- Modify: `Sources/CarRentalOptimizer/SearchViewModel.swift`
- Modify: `Tests/CarRentalOptimizerTests/SearchViewModelTests.swift`

**Interfaces:**
- Consumes: `VehicleInsightStore`, `VehicleInsightNetworkProvider`.
- Produces:
  - `protocol VehicleInsightProviding`
  - `final class VehicleInsightService`
  - `SearchViewModel.selectedVehicleInsight: VehicleInsight?`
  - `SearchViewModel.isLoadingSelectedVehicleInsight: Bool`
  - `SearchViewModel.refreshSelectedVehicleInsight()`

- [ ] **Step 1: Write failing SearchViewModel insight tests**

Append these tests to `Tests/CarRentalOptimizerTests/SearchViewModelTests.swift` inside `SearchViewModelTests`:

```swift
@Test("Selection emits local vehicle insight immediately and network insight later")
func selectionEmitsLocalVehicleInsightImmediatelyAndNetworkInsightLater() async {
    let listing = makeTestListing(vehicleName: "大众 朗逸", vehicleClass: "1.5L | 三厢 5座 | 蓝牙")
    let provider = StubRentalSearchProvider(results: [
        PlatformEvidenceResult(
            platform: .ehi,
            status: PlatformEvidenceStatus(platform: .ehi, kind: .ready, message: "一嗨已返回报价。", sourceUrl: "https://booking.1hai.cn/"),
            listings: [listing]
        )
    ])
    let vehicleInsightService = StubVehicleInsightService(networkDelayNanoseconds: 20_000_000)
    let viewModel = SearchViewModel(
        searchProvider: provider,
        geocoder: CurrentRequestGeocoder(point: AppDefaults.searchRequest.origin),
        mapService: EstimatedMapService(),
        vehicleInsightService: vehicleInsightService
    )

    await viewModel.runSearch()

    #expect(viewModel.selectedVehicleInsight?.origin == .localInference)
    #expect(viewModel.isLoadingSelectedVehicleInsight)
    try? await Task.sleep(nanoseconds: 40_000_000)
    #expect(viewModel.selectedVehicleInsight?.origin == .network)
    #expect(viewModel.selectedVehicleInsight?.sourceName == "Wikipedia")
}

@Test("Displayed list rendering does not fetch network insights for every row")
func displayedListRenderingDoesNotFetchNetworkInsightsForEveryRow() async {
    let recommendations = [
        makeTestListing(id: "vehicle-1", vehicleName: "大众 朗逸", vehicleClass: "1.5L | 三厢 5座"),
        makeTestListing(id: "vehicle-2", vehicleName: "小鹏 MONA", vehicleClass: "纯电 51kWh | 三厢 5座")
    ]
    let provider = StubRentalSearchProvider(results: [
        PlatformEvidenceResult(
            platform: .ehi,
            status: PlatformEvidenceStatus(platform: .ehi, kind: .ready, message: "一嗨已返回报价。", sourceUrl: "https://booking.1hai.cn/"),
            listings: recommendations
        )
    ])
    let vehicleInsightService = StubVehicleInsightService(networkDelayNanoseconds: 0)
    let viewModel = SearchViewModel(
        searchProvider: provider,
        geocoder: CurrentRequestGeocoder(point: AppDefaults.searchRequest.origin),
        mapService: EstimatedMapService(),
        vehicleInsightService: vehicleInsightService
    )

    await viewModel.runSearch()
    _ = viewModel.displayedResults
    _ = viewModel.displayedResults

    #expect(vehicleInsightService.networkRequestCount == 1)
}
```

Add this stub near the other private test helpers:

```swift
private final class StubVehicleInsightService: VehicleInsightProviding {
    private(set) var networkRequestCount = 0
    let networkDelayNanoseconds: UInt64

    init(networkDelayNanoseconds: UInt64) {
        self.networkDelayNanoseconds = networkDelayNanoseconds
    }

    func localInsight(for listing: RentalListing) -> VehicleInsight {
        VehicleInsightLocalInferencer.localInsight(for: listing, now: vehicleInsightStubDate())
    }

    func insight(for listing: RentalListing) async -> VehicleInsight {
        networkRequestCount += 1
        if networkDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: networkDelayNanoseconds)
        }
        var insight = VehicleInsightLocalInferencer.localInsight(for: listing, now: vehicleInsightStubDate())
        insight.origin = .network
        insight.sourceName = "Wikipedia"
        insight.sourceURL = "https://example.com/\(listing.vehicleName)"
        insight.longSummary = "车系介绍：联网测试简介。当前租赁车辆配置以平台返回为准：\(insight.configurationSummary ?? "配置以平台返回为准")。"
        return insight
    }
}

private func vehicleInsightStubDate() -> Date {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
    return formatter.date(from: "2026-07-02 17:14")!
}
```

- [ ] **Step 2: Run the focused test to verify it fails**

Run: `swift test --filter SearchViewModelTests`

Expected: FAIL with compiler errors containing `cannot find type 'VehicleInsightProviding' in scope` or `extra argument 'vehicleInsightService' in call`.

- [ ] **Step 3: Add service protocol and default service**

Append this to `Sources/CarRentalOptimizer/VehicleInsights.swift`:

```swift
protocol VehicleInsightProviding {
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
```

- [ ] **Step 4: Wire SearchViewModel selected insight state**

Modify `Sources/CarRentalOptimizer/SearchViewModel.swift`:

```swift
@Published var selectedId = "" {
    didSet {
        guard selectedId != oldValue else { return }
        refreshSelectedVehicleInsight()
    }
}
@Published var selectedVehicleInsight: VehicleInsight?
@Published var isLoadingSelectedVehicleInsight = false
```

Add stored properties:

```swift
private let vehicleInsightService: VehicleInsightProviding
private var selectedVehicleInsightRequestID = 0
```

In each initializer, set `vehicleInsightService`. The default initializer uses `VehicleInsightService()`. The test initializer signature becomes:

```swift
init(
    searchProvider: RentalSearchProviding,
    geocoder: AddressGeocoding,
    mapService: MapService,
    currentLocationProvider: CurrentLocationProviding = UnavailableCurrentLocationProvider(),
    addressSuggestionProvider: AddressSuggestionProviding = EmptyAddressSuggestionProvider(),
    railStationSuggestionProvider: RailStationSuggestionProviding = EmptyRailStationSuggestionProvider(),
    vehicleSuggestionStore: VehicleSuggestionStore = VehicleSuggestionStore(),
    vehicleInsightService: VehicleInsightProviding = VehicleInsightService(),
    initialLocationRetryDelayNanoseconds: UInt64 = defaultInitialLocationRetryDelayNanoseconds,
    now: @escaping () -> Date = Date.init
)
```

Add this method near `selectResult(_:)`:

```swift
func refreshSelectedVehicleInsight() {
    selectedVehicleInsightRequestID += 1
    let requestID = selectedVehicleInsightRequestID
    guard let listing = selected?.listing else {
        selectedVehicleInsight = nil
        isLoadingSelectedVehicleInsight = false
        return
    }

    selectedVehicleInsight = vehicleInsightService.localInsight(for: listing)
    isLoadingSelectedVehicleInsight = true

    Task { [weak self, listing, requestID] in
        guard let self else { return }
        let insight = await vehicleInsightService.insight(for: listing)
        await MainActor.run {
            guard requestID == selectedVehicleInsightRequestID else { return }
            selectedVehicleInsight = insight
            isLoadingSelectedVehicleInsight = false
        }
    }
}
```

After `results = recommendations` in `performSearch(retryingFailedPlatformsOnly:)`, keep `selectFirstDisplayedResult()` unchanged; the `selectedId` observer starts insight lookup.

- [ ] **Step 5: Run SearchViewModel tests**

Run: `swift test --filter SearchViewModelTests`

Expected: PASS with existing tests and the 2 new vehicle insight tests.

- [ ] **Step 6: Commit**

```bash
git add Sources/CarRentalOptimizer/VehicleInsights.swift Sources/CarRentalOptimizer/SearchViewModel.swift Tests/CarRentalOptimizerTests/SearchViewModelTests.swift
git commit -m "feat: refresh selected vehicle insight"
```

## Task 5: Result Card And Detail Panel UI

**Files:**
- Modify: `Sources/CarRentalOptimizer/ResultPanelView.swift`
- Modify: `Sources/CarRentalOptimizer/DetailPanelView.swift`
- Modify: `Tests/CarRentalOptimizerTests/UIEffectsSourceTests.swift`

**Interfaces:**
- Consumes: `VehicleInsightLocalInferencer.localInsight(for:)`, `viewModel.selectedVehicleInsight`, `viewModel.isLoadingSelectedVehicleInsight`.
- Produces:
  - `VehicleInsightLine`
  - `VehicleInsightSection`
  - `VehicleInsightFactGrid`
  - `VehicleFeatureTag`

- [ ] **Step 1: Write failing UI source-contract checks**

Append these expectations to existing UI tests:

```swift
@Test("Result panel exposes compact vehicle insight line")
func resultPanelExposesCompactVehicleInsightLine() throws {
    let source = try String(contentsOfFile: "Sources/CarRentalOptimizer/ResultPanelView.swift", encoding: .utf8)

    #expect(source.contains("VehicleInsightLine("))
    #expect(source.contains("VehicleInsightLocalInferencer.localInsight(for: recommendation.listing)"))
    #expect(source.contains(".lineLimit(1)"))
}

@Test("Detail panel exposes vehicle insight section with specs and platform features")
func detailPanelExposesVehicleInsightSectionWithSpecsAndPlatformFeatures() throws {
    let source = try String(contentsOfFile: "Sources/CarRentalOptimizer/DetailPanelView.swift", encoding: .utf8)

    #expect(source.contains("VehicleInsightSection("))
    #expect(source.contains("viewModel.selectedVehicleInsight"))
    #expect(source.contains("车型介绍"))
    #expect(source.contains("基础参数"))
    #expect(source.contains("平台配置"))
    #expect(source.contains("下单前以平台确认页为准"))
}
```

- [ ] **Step 2: Run the focused test to verify it fails**

Run: `swift test --filter UIEffectsSourceTests`

Expected: FAIL because `VehicleInsightLine` and `VehicleInsightSection` are not in source.

- [ ] **Step 3: Add result card insight line**

In `Sources/CarRentalOptimizer/ResultPanelView.swift`, inside `cardHeader`, insert this immediately after the vehicle name/copy-button `HStack`:

```swift
VehicleInsightLine(insight: VehicleInsightLocalInferencer.localInsight(for: recommendation.listing))
```

Add this view near `ResultSignalCard` helper views:

```swift
private struct VehicleInsightLine: View {
    let insight: VehicleInsight

    var body: some View {
        Label(insight.shortSummary, systemImage: "sparkle.magnifyingglass")
            .font(.caption2)
            .foregroundStyle(WorkbenchStyle.muted)
            .lineLimit(1)
            .truncationMode(.tail)
            .help(insight.shortSummary)
    }
}
```

- [ ] **Step 4: Add detail panel insight section**

Change `RecommendationDetailView` in `Sources/CarRentalOptimizer/DetailPanelView.swift` to accept insight state:

```swift
private struct RecommendationDetailView: View {
    let recommendation: Recommendation
    let vehicleInsight: VehicleInsight?
    let isLoadingVehicleInsight: Bool
    let onMonitor: () -> Void
```

Update the call site:

```swift
RecommendationDetailView(
    recommendation: recommendation,
    vehicleInsight: viewModel.selectedVehicleInsight,
    isLoadingVehicleInsight: viewModel.isLoadingSelectedVehicleInsight
) {
    pendingMonitorRecommendation = recommendation
}
```

Insert after the existing store/vehicle `SurfaceBox`:

```swift
VehicleInsightSection(
    insight: vehicleInsight ?? VehicleInsightLocalInferencer.localInsight(for: recommendation.listing),
    isLoading: isLoadingVehicleInsight
)
```

Add these views before `PlatformQuoteComparisonView`:

```swift
private struct VehicleInsightSection: View {
    let insight: VehicleInsight
    let isLoading: Bool

    var body: some View {
        SurfaceBox {
            VStack(alignment: .leading, spacing: 11) {
                DetailTitleRow(
                    icon: insight.origin == .network ? "network" : "sparkle.magnifyingglass",
                    title: "车型介绍",
                    badge: isLoading ? "更新中" : insight.origin.label
                )

                Text(insight.longSummary)
                    .font(.caption)
                    .foregroundStyle(WorkbenchStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Text(insight.sourceName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(WorkbenchStyle.commandBlue)
                    if let fetchedAt = insight.fetchedAt {
                        Text(vehicleInsightFreshness(fetchedAt))
                            .font(.caption2)
                            .foregroundStyle(WorkbenchStyle.muted)
                    }
                    if let sourceURL = insight.sourceURL, let url = URL(string: sourceURL), insight.origin == .network {
                        Link("来源", destination: url)
                            .font(.caption2.weight(.semibold))
                    }
                    Spacer(minLength: 0)
                }

                VehicleInsightFactGrid(title: "基础参数", facts: insight.formattedBasicSpecs)

                VStack(alignment: .leading, spacing: 7) {
                    Text("平台配置")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WorkbenchStyle.ink)
                    if insight.platformFeatures.isEmpty {
                        Text("配置以平台返回为准")
                            .font(.caption2)
                            .foregroundStyle(WorkbenchStyle.muted)
                    } else {
                        FlowLikeTagRows(features: insight.platformFeatures)
                    }
                    Text("下单前以平台确认页为准")
                        .font(.caption2)
                        .foregroundStyle(WorkbenchStyle.muted)
                }
            }
        }
    }
}

private struct VehicleInsightFactGrid: View {
    let title: String
    let facts: [VehicleInsightFact]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WorkbenchStyle.ink)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 7) {
                ForEach(facts) { fact in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(fact.label)
                            .font(.caption2)
                            .foregroundStyle(WorkbenchStyle.muted)
                        Text(fact.value)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(WorkbenchStyle.ink)
                            .lineLimit(1)
                        if let scopeLabel = fact.scopeLabel {
                            Text(scopeLabel)
                                .font(.caption2)
                                .foregroundStyle(WorkbenchStyle.muted)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(WorkbenchStyle.quietFill))
                }
            }
        }
    }
}

private struct FlowLikeTagRows: View {
    let features: [VehicleFeature]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(chunked(features, size: 3), id: \.map(\.id).joined()) { row in
                HStack(spacing: 6) {
                    ForEach(row) { feature in
                        VehicleFeatureTag(feature: feature)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func chunked(_ values: [VehicleFeature], size: Int) -> [[VehicleFeature]] {
        stride(from: 0, to: values.count, by: size).map {
            Array(values[$0..<min($0 + size, values.count)])
        }
    }
}

private struct VehicleFeatureTag: View {
    let feature: VehicleFeature

    var body: some View {
        Text(feature.name)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(WorkbenchStyle.commandBlue)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(WorkbenchStyle.commandBlue.opacity(0.10))
            )
            .help("\(feature.name) · \(feature.appliesTo.label)")
    }
}

private func vehicleInsightFreshness(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "MM-dd HH:mm"
    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
    return formatter.string(from: date)
}
```

- [ ] **Step 5: Run UI source-contract tests**

Run: `swift test --filter UIEffectsSourceTests`

Expected: PASS with existing tests and the 2 new vehicle insight checks.

- [ ] **Step 6: Commit**

```bash
git add Sources/CarRentalOptimizer/ResultPanelView.swift Sources/CarRentalOptimizer/DetailPanelView.swift Tests/CarRentalOptimizerTests/UIEffectsSourceTests.swift
git commit -m "feat: show vehicle insights in results"
```

## Task 6: Final Verification And Integration Sweep

**Files:**
- Verify all files touched by Tasks 1-5.

**Interfaces:**
- Consumes: all previous task outputs.
- Produces: passing focused tests and passing full suite.

- [ ] **Step 1: Run vehicle insight test suite**

Run: `swift test --filter VehicleInsight`

Expected: PASS for `VehicleInsightTests`, `VehicleInsightStoreTests`, and `VehicleInsightNetworkTests`.

- [ ] **Step 2: Run SearchViewModel tests**

Run: `swift test --filter SearchViewModelTests`

Expected: PASS.

- [ ] **Step 3: Run UI source-contract tests**

Run: `swift test --filter UIEffectsSourceTests`

Expected: PASS.

- [ ] **Step 4: Run full suite**

Run: `swift test`

Expected: PASS for the full package.

- [ ] **Step 5: Inspect git status**

Run: `git status --short`

Expected: only intentional files from this plan are modified, plus any pre-existing uncommitted work that was present before this plan execution.

- [ ] **Step 6: Commit verification-only adjustments**

When Steps 1-4 changed files during verification, commit only those touched files:

```bash
git add Sources/CarRentalOptimizer Tests/CarRentalOptimizerTests
git commit -m "test: verify vehicle insight integration"
```

## Self-Review

Spec coverage:
- Card short practical suggestion is covered by Task 5 `VehicleInsightLine`.
- Detail `车型介绍`, source metadata, `基础参数`, and `平台配置` are covered by Task 5 `VehicleInsightSection`.
- Local fallback is covered by Task 1 inference and Task 4 service fallback.
- Wikipedia REST summary and Wikidata SPARQL mapping are covered by Task 3.
- 30 day Application Support cache is covered by Task 2.
- Year/trim confidence rules are covered by Task 1 tests and Task 3 network mapping.
- Platform-field priority is covered by Task 1 feature/spec extraction and Task 4 cache merge.
- Only selected/detail network fetch is covered by Task 4 SearchViewModel tests.
- Privacy is covered by Task 3 using only `VehicleInsightLocalInferencer.normalizedQuery(for:)`.

Red-flag wording scan:
- Clean: no open-ended implementation markers or broad test instructions remain.

Type consistency:
- `VehicleInsightProviding` is defined before SearchViewModel consumes it.
- `VehicleInsightLine`, `VehicleInsightSection`, `VehicleInsightFactGrid`, and `VehicleFeatureTag` are all produced in Task 5.
- `VehicleInsightStore.normalizedCacheKey(_:)` and `VehicleInsightLocalInferencer.normalizedQuery(for:)` use separate responsibilities and compatible string keys.
