import Foundation

final class VehicleInsightStore {
    private struct PersistedState: Codable {
        var entries: [String: CacheEntry]
    }

    private struct CacheEntry: Codable {
        var insight: VehicleInsight
        var savedAt: Date
        var schemaVersion: Int?
    }

    private static let directoryName = "CarRentalOptimizer"
    private static let fileName = "vehicle-insights.json"
    private static let cacheSchemaVersion = 2
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
              entry.schemaVersion == Self.cacheSchemaVersion,
              now.timeIntervalSince(entry.savedAt) <= Self.cacheTTL
        else { return nil }
        return entry.insight
    }

    func save(_ insight: VehicleInsight, forKey key: String, now: Date = Date()) {
        entries[Self.normalizedCacheKey(key)] = CacheEntry(
            insight: insight,
            savedAt: now,
            schemaVersion: Self.cacheSchemaVersion
        )
        saveBestEffort()
    }

    private static func loadEntries(from fileURL: URL) -> [String: CacheEntry] {
        guard let data = try? Data(contentsOf: fileURL) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let state = try? decoder.decode(PersistedState.self, from: data) else { return [:] }
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
            return
        }
    }
}
