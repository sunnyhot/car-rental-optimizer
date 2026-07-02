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

    @Test("Older cache schema returns nil")
    func olderCacheSchemaReturnsNil() throws {
        let fileURL = temporaryInsightStoreURL()
        let oldCacheJSON = """
        {
          "entries" : {
            "大众朗逸" : {
              "insight" : {
                "vehicleName" : "大众朗逸",
                "seriesName" : "大众朗逸",
                "specSheet" : {
                  "features" : []
                },
                "configurationSummary" : null,
                "modelYear" : null,
                "modelYearConfidence" : "low",
                "trimConfidence" : "low",
                "shortSummary" : "旧缓存",
                "longSummary" : "旧缓存里只有 Wikipedia 简介。",
                "sourceName" : "Wikipedia",
                "sourceURL" : "https://zh.wikipedia.org/wiki/大众朗逸",
                "fetchedAt" : "2026-07-02T12:00:00Z",
                "confidence" : "medium",
                "origin" : "network"
              },
              "savedAt" : "2026-07-02T12:00:00Z"
            }
          }
        }
        """
        try oldCacheJSON.data(using: .utf8)?.write(to: fileURL)

        let cached = VehicleInsightStore(fileURL: fileURL)
            .cachedInsight(forKey: "大众朗逸", now: cacheDate("2026-07-03 12:00"))

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
