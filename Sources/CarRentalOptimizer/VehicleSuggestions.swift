import Foundation

enum VehicleSuggestionSource: String, Codable, Equatable {
    case recent
    case learned
    case builtIn

    var label: String {
        switch self {
        case .recent:
            return "最近使用"
        case .learned:
            return "搜索结果"
        case .builtIn:
            return "常用"
        }
    }

    var priority: Int {
        switch self {
        case .recent:
            return 0
        case .learned:
            return 1
        case .builtIn:
            return 2
        }
    }
}

struct VehicleSuggestion: Identifiable, Codable, Equatable {
    var id: String { normalizedVehicleSuggestionKey(name) }
    let name: String
    var source: VehicleSuggestionSource
    var aliases: [String]
    var lastUsedAt: Date?
    var learnedAt: Date?
    var count: Int

    var sourceLabel: String {
        source.label
    }

    init(
        name: String,
        source: VehicleSuggestionSource,
        aliases: [String] = [],
        lastUsedAt: Date? = nil,
        learnedAt: Date? = nil,
        count: Int = 0
    ) {
        self.name = canonicalVehicleSuggestionName(name)
        self.source = source
        self.aliases = aliases
        self.lastUsedAt = lastUsedAt
        self.learnedAt = learnedAt
        self.count = count
    }

    static func isPlaceholderName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "未指定车型"
    }

    var canonicalizedForSuggestions: VehicleSuggestion {
        let canonicalName = canonicalVehicleSuggestionName(name)
        guard canonicalName != name else { return self }
        var canonicalAliases = aliases
        if !canonicalAliases.contains(name) {
            canonicalAliases.append(name)
        }
        return VehicleSuggestion(
            name: canonicalName,
            source: source,
            aliases: canonicalAliases,
            lastUsedAt: lastUsedAt,
            learnedAt: learnedAt,
            count: count
        )
    }
}

struct VehicleSuggestionEngine {
    static func suggestions(
        matching query: String,
        recent: [VehicleSuggestion],
        learned: [VehicleSuggestion],
        builtIns: [VehicleSuggestion],
        limit: Int = 6
    ) -> [VehicleSuggestion] {
        let normalizedQuery = normalizedVehicleSuggestionKey(query)
        let candidates = recent + learned + builtIns
        var bestByID: [String: VehicleSuggestion] = [:]

        for rawCandidate in candidates where !VehicleSuggestion.isPlaceholderName(rawCandidate.name) {
            let candidate = rawCandidate.canonicalizedForSuggestions
            guard normalizedQuery.isEmpty || matches(candidate, query: normalizedQuery) else { continue }
            if let existing = bestByID[candidate.id] {
                bestByID[candidate.id] = stronger(candidate, than: existing)
            } else {
                bestByID[candidate.id] = candidate
            }
        }

        return bestByID.values.sorted { lhs, rhs in
            let lhsScore = matchScore(lhs, query: normalizedQuery)
            let rhsScore = matchScore(rhs, query: normalizedQuery)
            if lhsScore != rhsScore { return lhsScore > rhsScore }
            if lhs.source.priority != rhs.source.priority { return lhs.source.priority < rhs.source.priority }
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            let lhsDate = lhs.lastUsedAt ?? lhs.learnedAt ?? .distantPast
            let rhsDate = rhs.lastUsedAt ?? rhs.learnedAt ?? .distantPast
            if lhsDate != rhsDate { return lhsDate > rhsDate }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        .prefix(max(0, limit))
        .map { $0 }
    }

    private static func stronger(_ lhs: VehicleSuggestion, than rhs: VehicleSuggestion) -> VehicleSuggestion {
        if lhs.source.priority != rhs.source.priority {
            return lhs.source.priority < rhs.source.priority ? lhs : rhs
        }
        if lhs.count != rhs.count {
            return lhs.count > rhs.count ? lhs : rhs
        }
        let lhsDate = lhs.lastUsedAt ?? lhs.learnedAt ?? .distantPast
        let rhsDate = rhs.lastUsedAt ?? rhs.learnedAt ?? .distantPast
        return lhsDate >= rhsDate ? lhs : rhs
    }

    private static func matches(_ suggestion: VehicleSuggestion, query: String) -> Bool {
        searchableKeys(for: suggestion).contains { $0.contains(query) || query.contains($0) }
    }

    private static func matchScore(_ suggestion: VehicleSuggestion, query: String) -> Int {
        guard !query.isEmpty else { return 0 }
        let keys = searchableKeys(for: suggestion)
        if keys.contains(query) { return 3 }
        if keys.contains(where: { $0.hasPrefix(query) }) { return 2 }
        if keys.contains(where: { $0.contains(query) }) { return 1 }
        return 0
    }

    private static func searchableKeys(for suggestion: VehicleSuggestion) -> [String] {
        ([suggestion.name] + suggestion.aliases).map(normalizedVehicleSuggestionKey)
    }
}

final class VehicleSuggestionStore {
    private struct PersistedState: Codable {
        var learned: [VehicleSuggestion]
        var recent: [VehicleSuggestion]
    }

    private static let directoryName = "CarRentalOptimizer"
    private static let fileName = "vehicle-suggestions.json"
    static let maxRecentCount = 20
    static let maxLearnedCount = 100

    static var defaultFileURL: URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return baseURL
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(fileName)
    }

    static let defaultBuiltIns: [VehicleSuggestion] = [
        VehicleSuggestion(name: "尚界 H5", source: .builtIn, aliases: ["shangjie", "h5", "shangjieh5"]),
        VehicleSuggestion(name: "奇瑞瑞虎8", source: .builtIn, aliases: ["瑞虎8", "ruihu", "ruihu8", "tiggo8"]),
        VehicleSuggestion(name: "哈弗 H6", source: .builtIn, aliases: ["haval", "havalh6", "h6"]),
        VehicleSuggestion(name: "大众朗逸", source: .builtIn, aliases: ["lavida", "langyi"]),
        VehicleSuggestion(name: "雪佛兰科鲁泽", source: .builtIn, aliases: ["kruze", "keluze"]),
        VehicleSuggestion(name: "SUV", source: .builtIn, aliases: ["suv", "越野"]),
        VehicleSuggestion(name: "MPV", source: .builtIn, aliases: ["mpv", "商务"]),
        VehicleSuggestion(name: "新能源", source: .builtIn, aliases: ["ev", "electric", "diandong"])
    ]

    private(set) var learnedSuggestions: [VehicleSuggestion]
    private(set) var recentSuggestions: [VehicleSuggestion]
    private let builtIns: [VehicleSuggestion]
    private let fileURL: URL

    convenience init(fileURL: URL = defaultFileURL) {
        let persisted = Self.loadState(from: fileURL)
        self.init(
            learned: persisted.learned,
            recent: persisted.recent,
            builtIns: Self.defaultBuiltIns,
            fileURL: fileURL
        )
    }

    init(
        learned: [VehicleSuggestion],
        recent: [VehicleSuggestion],
        builtIns: [VehicleSuggestion],
        fileURL: URL
    ) {
        self.learnedSuggestions = Array(learned.prefix(Self.maxLearnedCount))
        self.recentSuggestions = Array(recent.prefix(Self.maxRecentCount))
        self.builtIns = builtIns
        self.fileURL = fileURL
    }

    func suggestions(matching query: String, limit: Int = 6) -> [VehicleSuggestion] {
        VehicleSuggestionEngine.suggestions(
            matching: query,
            recent: recentSuggestions,
            learned: learnedSuggestions,
            builtIns: builtIns,
            limit: limit
        )
    }

    func recordSearchResults(_ names: [String], now: Date = Date()) {
        var byID: [String: VehicleSuggestion] = [:]
        for suggestion in learnedSuggestions {
            let canonicalSuggestion = suggestion.canonicalizedForSuggestions
            byID[canonicalSuggestion.id] = canonicalSuggestion
        }
        for rawName in names {
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !VehicleSuggestion.isPlaceholderName(name) else { continue }
            let incomingSuggestion = VehicleSuggestion(name: name, source: .learned, aliases: name == canonicalVehicleSuggestionName(name) ? [] : [name])
            var suggestion = byID[incomingSuggestion.id] ?? incomingSuggestion
            suggestion.source = .learned
            suggestion.learnedAt = now
            suggestion.count += 1
            byID[incomingSuggestion.id] = suggestion
        }
        learnedSuggestions = byID.values.sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            return ($0.learnedAt ?? .distantPast) > ($1.learnedAt ?? .distantPast)
        }
        .prefix(Self.maxLearnedCount)
        .map { $0 }
        saveBestEffort()
    }

    func recordSelection(_ suggestion: VehicleSuggestion, now: Date = Date()) {
        guard !VehicleSuggestion.isPlaceholderName(suggestion.name) else { return }
        let canonicalSuggestion = suggestion.canonicalizedForSuggestions
        let selected = VehicleSuggestion(
            name: canonicalSuggestion.name,
            source: .recent,
            aliases: canonicalSuggestion.aliases,
            lastUsedAt: now,
            learnedAt: canonicalSuggestion.learnedAt,
            count: canonicalSuggestion.count + 1
        )
        recentSuggestions.removeAll { $0.id == selected.id }
        recentSuggestions.insert(selected, at: 0)
        recentSuggestions = Array(recentSuggestions.prefix(Self.maxRecentCount))
        saveBestEffort()
    }

    private static func loadState(from fileURL: URL) -> PersistedState {
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data)
        else {
            return PersistedState(learned: [], recent: [])
        }
        return state
    }

    private func saveBestEffort() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(PersistedState(learned: learnedSuggestions, recent: recentSuggestions))
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            assertionFailure("Failed to persist vehicle suggestions: \(error.localizedDescription)")
        }
    }
}

func normalizedVehicleSuggestionKey(_ value: String) -> String {
    canonicalVehicleSuggestionName(value)
        .lowercased()
        .replacingOccurrences(of: " ", with: "")
        .replacingOccurrences(of: "-", with: "")
        .replacingOccurrences(of: "·", with: "")
        .replacingOccurrences(of: "_", with: "")
        .replacingOccurrences(of: "/", with: "")
        .replacingOccurrences(of: "　", with: "")
}

func canonicalVehicleSuggestionName(_ value: String) -> String {
    var result = value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

    let qualifierPatterns = [
        #"(?i)(?:\s|　)*(?:新能源|京牌|沪牌|粤牌|浙牌|苏牌|津牌|冀牌|豫牌|鲁牌|川牌|渝牌|绿牌|蓝牌|油牌|电车|油车)$"#
    ]

    var stripped = true
    while stripped {
        stripped = false
        for pattern in qualifierPatterns {
            guard let range = result.range(of: pattern, options: .regularExpression) else { continue }
            let candidate = result[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !candidate.isEmpty else { continue }
            result = candidate
            stripped = true
        }
    }

    return result
}
