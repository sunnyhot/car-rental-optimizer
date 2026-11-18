import Foundation

final class VehicleInsightStore {
    private struct PersistedState: Codable {
        var entries: [String: CacheEntry]
    }

    private struct CacheEntry: Codable {
        var insight: VehicleInsight
        var savedAt: Date
        var schemaVersion: Int?
        var lastRefreshAttemptAt: Date? = nil
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
        VehicleModelIdentity.cacheKey(VehicleInsightLocalInferencer.normalizedSeriesName(value))
    }

    func cachedInsight(forKey key: String, now: Date = Date()) -> VehicleInsight? {
        let normalized = Self.normalizedCacheKey(key)
        guard let entry = entries[normalized],
              entry.schemaVersion == Self.cacheSchemaVersion
        else { return nil }
        var result = entry.insight
        result.specSheet = result.specSheet.sanitizedDimensions()
        result.cacheState = now.timeIntervalSince(entry.savedAt) <= Self.cacheTTL ? .cached : .stale
        return result
    }

    func needsRefresh(forKey key: String, now: Date = Date()) -> Bool {
        guard let entry = entries[Self.normalizedCacheKey(key)], entry.schemaVersion == Self.cacheSchemaVersion else { return true }
        if let lastAttempt = entry.lastRefreshAttemptAt, now.timeIntervalSince(lastAttempt) < 300 { return false }
        return !entry.insight.specSheet.sanitizedDimensions().hasCompleteDimensions || now.timeIntervalSince(entry.savedAt) > Self.cacheTTL
    }

    func recordRefreshAttempt(forKey key: String, now: Date = Date()) {
        let key = Self.normalizedCacheKey(key)
        guard entries[key] != nil else { return }
        entries[key]?.lastRefreshAttemptAt = now
        saveBestEffort(updating: key)
    }

    func save(_ insight: VehicleInsight, forKey key: String, now: Date = Date()) {
        let key = Self.normalizedCacheKey(key)
        var updated = insight
        updated.specSheet = insight.specSheet.sanitizedDimensions()
        if let old = cachedInsight(forKey: key, now: now) {
            if old.specSheet.hasReferenceDimensions && !updated.specSheet.hasReferenceDimensions {
                recordRefreshAttempt(forKey: key, now: now)
                return
            }
            updated.specSheet = updated.specSheet.fillingMissingValues(from: old.specSheet)
        }
        updated.cacheState = nil
        entries[key] = CacheEntry(insight: updated, savedAt: now, schemaVersion: Self.cacheSchemaVersion)
        saveBestEffort(updating: key)
    }

    private static func loadEntries(from fileURL: URL) -> [String: CacheEntry] {
        guard let data = try? Data(contentsOf: fileURL) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let state = try? decoder.decode(PersistedState.self, from: data) else { return [:] }
        var migrated: [String: CacheEntry] = [:]
        for (key, entry) in state.entries {
            let normalized = normalizedCacheKey(entry.insight.vehicleName.isEmpty ? key : entry.insight.vehicleName)
            if let existing = migrated[normalized] {
                if existing.insight.specSheet.hasReferenceDimensions && !entry.insight.specSheet.hasReferenceDimensions { continue }
                if existing.insight.specSheet.hasReferenceDimensions == entry.insight.specSheet.hasReferenceDimensions && existing.savedAt > entry.savedAt { continue }
            }
            migrated[normalized] = entry
        }
        return migrated
    }

    private func saveBestEffort(updating key: String) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let updatedEntry = entries[key]
            entries.merge(Self.loadEntries(from: fileURL)) { _, disk in disk }
            entries[key] = updatedEntry
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
