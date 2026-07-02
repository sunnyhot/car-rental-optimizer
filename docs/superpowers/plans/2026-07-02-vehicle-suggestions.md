# Vehicle Suggestions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add typo-resistant vehicle suggestions using built-in options, learned search results, and recent selections.

**Architecture:** Add a focused vehicle suggestion module that owns normalization, ranking, bounded persistence, and built-in suggestions. Wire it into `SearchViewModel` as published suggestion state, then replace the plain vehicle `TextField` in `SearchPanelView` with a compact suggestion field that matches the existing address dropdown style.

**Tech Stack:** Swift 5.9, SwiftUI, Swift Testing, Foundation JSON persistence, existing `CarRentalDomain` recommendation types.

## Global Constraints

- The vehicle field remains optional and selecting a suggestion must not start a search.
- Show up to six suggestions.
- Source priority is recent selections, learned search-result vehicles, then built-in common options.
- Empty input shows recent selections first, then learned vehicles, then built-ins.
- Non-empty input matches Chinese text, ASCII fragments, and aliases such as `h5`, `suv`, `mpv`, `ruihu`, and `haval`.
- Suggestion row labels are exactly `最近使用`, `搜索结果`, or `常用`.
- Persistence is best-effort and must not block search.
- Recent selections are capped at 20; learned search-result vehicles are capped at 100.
- Ignore placeholder vehicle names such as `未指定车型`.
- Do not add a modal, popover dependency, new framework, or unrelated UI redesign.

---

## File Structure

- Create `Sources/CarRentalOptimizer/VehicleSuggestions.swift`
  - Owns `VehicleSuggestion`, `VehicleSuggestionSource`, `VehicleSuggestionEngine`, `VehicleSuggestionStore`, built-in defaults, normalization, matching, ranking, dedupe, record/select behavior, and JSON persistence.
- Modify `Sources/CarRentalOptimizer/SearchViewModel.swift`
  - Adds published vehicle suggestion state.
  - Adds dependency-injected `VehicleSuggestionStore`.
  - Records ranked successful recommendations and handles suggestion selection/dismissal.
- Modify `Sources/CarRentalOptimizer/SearchPanelView.swift`
  - Replaces the plain vehicle `TextField` with `VehicleSuggestionField`.
  - Adds compact `VehicleSuggestionDropdown` styled like the existing address dropdown.
  - Dismisses vehicle suggestions when date/origin/search actions dismiss other editors.
- Test `Tests/CarRentalOptimizerTests/VehicleSuggestionTests.swift`
  - Covers pure suggestion matching, ranking, dedupe, persistence caps, and placeholder filtering.
- Modify `Tests/CarRentalOptimizerTests/SearchViewModelTests.swift`
  - Covers ViewModel suggestion state, selection, and recording from successful blank-vehicle searches.
- Modify `Tests/CarRentalOptimizerTests/UIEffectsSourceTests.swift`
  - Covers that the search panel uses `VehicleSuggestionField`.

---

### Task 1: Vehicle Suggestion Core

**Files:**
- Create: `Sources/CarRentalOptimizer/VehicleSuggestions.swift`
- Create: `Tests/CarRentalOptimizerTests/VehicleSuggestionTests.swift`

**Interfaces:**
- Produces:
  - `enum VehicleSuggestionSource: String, Codable, Equatable`
  - `struct VehicleSuggestion: Identifiable, Codable, Equatable`
  - `struct VehicleSuggestionEngine`
  - `final class VehicleSuggestionStore`
  - `VehicleSuggestionStore.defaultFileURL`
  - `VehicleSuggestionStore.suggestions(matching:limit:) -> [VehicleSuggestion]`
  - `VehicleSuggestionStore.recordSearchResults(_ names:now:)`
  - `VehicleSuggestionStore.recordSelection(_ suggestion:now:)`
  - `VehicleSuggestion.isPlaceholderName(_:)`
- Consumes:
  - `Foundation`

- [ ] **Step 1: Write failing tests for matching, ranking, dedupe, and placeholder filtering**

Create `Tests/CarRentalOptimizerTests/VehicleSuggestionTests.swift`:

```swift
import Foundation
import Testing
@testable import CarRentalOptimizer

@Suite("Vehicle suggestions")
struct VehicleSuggestionTests {
    @Test("Suggestions match Chinese text and aliases")
    func suggestionsMatchChineseTextAndAliases() {
        let store = VehicleSuggestionStore(
            learned: [
                VehicleSuggestion(name: "尚界 H5", source: .learned, aliases: ["shangjie", "h5"], lastUsedAt: nil, learnedAt: date("2026-07-02 10:00"), count: 2),
                VehicleSuggestion(name: "奇瑞瑞虎8", source: .learned, aliases: ["ruihu8", "tiggo8"], lastUsedAt: nil, learnedAt: date("2026-07-02 10:01"), count: 1)
            ],
            recent: [],
            builtIns: VehicleSuggestionStore.defaultBuiltIns,
            fileURL: temporaryURL()
        )

        #expect(store.suggestions(matching: "h5").map(\.name).contains("尚界 H5"))
        #expect(store.suggestions(matching: "瑞虎").map(\.name).contains("奇瑞瑞虎8"))
        #expect(store.suggestions(matching: "ruihu").map(\.name).contains("奇瑞瑞虎8"))
        #expect(store.suggestions(matching: "suv").contains { $0.name == "SUV" })
    }

    @Test("Recent learned and built in suggestions dedupe by source priority")
    func recentLearnedAndBuiltInSuggestionsDedupeBySourcePriority() {
        let store = VehicleSuggestionStore(
            learned: [
                VehicleSuggestion(name: "尚界 H5", source: .learned, aliases: ["h5"], lastUsedAt: nil, learnedAt: date("2026-07-02 09:00"), count: 5),
                VehicleSuggestion(name: "大众朗逸", source: .learned, aliases: ["lavida"], lastUsedAt: nil, learnedAt: date("2026-07-02 09:10"), count: 2)
            ],
            recent: [
                VehicleSuggestion(name: "尚界 H5", source: .recent, aliases: ["h5"], lastUsedAt: date("2026-07-02 11:00"), learnedAt: nil, count: 1)
            ],
            builtIns: [
                VehicleSuggestion(name: "尚界 H5", source: .builtIn, aliases: ["h5"], lastUsedAt: nil, learnedAt: nil, count: 0),
                VehicleSuggestion(name: "SUV", source: .builtIn, aliases: ["suv"], lastUsedAt: nil, learnedAt: nil, count: 0)
            ],
            fileURL: temporaryURL()
        )

        let suggestions = store.suggestions(matching: "", limit: 6)

        #expect(suggestions.map(\.name) == ["尚界 H5", "大众朗逸", "SUV"])
        #expect(suggestions.first?.source == .recent)
        #expect(suggestions.first?.sourceLabel == "最近使用")
    }

    @Test("Recording search results ignores placeholders and caps learned history")
    func recordingSearchResultsIgnoresPlaceholdersAndCapsLearnedHistory() {
        let store = VehicleSuggestionStore(
            learned: [],
            recent: [],
            builtIns: [],
            fileURL: temporaryURL()
        )
        let names = (0..<120).map { "测试车型\($0)" } + ["未指定车型", "   "]

        store.recordSearchResults(names, now: date("2026-07-02 12:00"))

        #expect(store.learnedSuggestions.count == 100)
        #expect(!store.learnedSuggestions.contains { $0.name == "未指定车型" })
        #expect(!store.learnedSuggestions.contains { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    @Test("Recording selection promotes item to recent and caps recent history")
    func recordingSelectionPromotesItemToRecentAndCapsRecentHistory() {
        let store = VehicleSuggestionStore(
            learned: [],
            recent: [],
            builtIns: [],
            fileURL: temporaryURL()
        )

        for index in 0..<25 {
            let suggestion = VehicleSuggestion(name: "最近车型\(index)", source: .learned, aliases: [], lastUsedAt: nil, learnedAt: nil, count: 0)
            store.recordSelection(suggestion, now: date("2026-07-02 12:\(String(format: "%02d", index))"))
        }

        #expect(store.recentSuggestions.count == 20)
        #expect(store.recentSuggestions.first?.name == "最近车型24")
        #expect(store.recentSuggestions.last?.name == "最近车型5")
    }
}

private func date(_ value: String) -> Date {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
    return formatter.date(from: value)!
}

private func temporaryURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("vehicle-suggestions-\(UUID().uuidString).json")
}
```

- [ ] **Step 2: Run the tests and verify they fail**

Run: `swift test --filter VehicleSuggestionTests`

Expected: FAIL because `VehicleSuggestionStore`, `VehicleSuggestion`, and `VehicleSuggestionSource` are not defined.

- [ ] **Step 3: Implement the suggestion model, engine, and store**

Create `Sources/CarRentalOptimizer/VehicleSuggestions.swift`:

```swift
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
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
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

        for candidate in candidates where !VehicleSuggestion.isPlaceholderName(candidate.name) {
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
        var byID = Dictionary(uniqueKeysWithValues: learnedSuggestions.map { ($0.id, $0) })
        for rawName in names {
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !VehicleSuggestion.isPlaceholderName(name) else { continue }
            let key = normalizedVehicleSuggestionKey(name)
            var suggestion = byID[key] ?? VehicleSuggestion(name: name, source: .learned)
            suggestion.source = .learned
            suggestion.learnedAt = now
            suggestion.count += 1
            byID[key] = suggestion
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
        let selected = VehicleSuggestion(
            name: suggestion.name,
            source: .recent,
            aliases: suggestion.aliases,
            lastUsedAt: now,
            learnedAt: suggestion.learnedAt,
            count: suggestion.count + 1
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
    value
        .lowercased()
        .replacingOccurrences(of: " ", with: "")
        .replacingOccurrences(of: "-", with: "")
        .replacingOccurrences(of: "·", with: "")
        .replacingOccurrences(of: "_", with: "")
        .replacingOccurrences(of: "/", with: "")
        .replacingOccurrences(of: "　", with: "")
}
```

- [ ] **Step 4: Run the focused tests and verify they pass**

Run: `swift test --filter VehicleSuggestionTests`

Expected: PASS.

- [ ] **Step 5: Commit Task 1**

```bash
git add Sources/CarRentalOptimizer/VehicleSuggestions.swift Tests/CarRentalOptimizerTests/VehicleSuggestionTests.swift
git commit -m "feat: add vehicle suggestion store"
```

---

### Task 2: SearchViewModel Suggestion State

**Files:**
- Modify: `Sources/CarRentalOptimizer/SearchViewModel.swift`
- Modify: `Tests/CarRentalOptimizerTests/SearchViewModelTests.swift`

**Interfaces:**
- Consumes:
  - `VehicleSuggestionStore.suggestions(matching:limit:)`
  - `VehicleSuggestionStore.recordSearchResults(_:now:)`
  - `VehicleSuggestionStore.recordSelection(_:now:)`
- Produces:
  - `@Published var vehicleSuggestions: [VehicleSuggestion]`
  - `@Published var isVehicleSuggestionPanelVisible: Bool`
  - `func refreshVehicleSuggestions(for query: String)`
  - `func selectVehicleSuggestion(_ suggestion: VehicleSuggestion)`
  - `func dismissVehicleSuggestions()`
  - `func recordVehicleSuggestions(from recommendations: [Recommendation])`

- [ ] **Step 1: Write failing ViewModel tests**

Append these tests inside `SearchViewModelTests`:

```swift
@Test("Vehicle suggestions refresh and selection update request")
func vehicleSuggestionsRefreshAndSelectionUpdateRequest() {
    let store = VehicleSuggestionStore(
        learned: [
            VehicleSuggestion(name: "尚界 H5", source: .learned, aliases: ["h5"], learnedAt: date("2026-07-02 10:00"), count: 1)
        ],
        recent: [],
        builtIns: [],
        fileURL: temporarySuggestionURL()
    )
    let viewModel = SearchViewModel(
        searchProvider: StubRentalSearchProvider(results: []),
        geocoder: CurrentRequestGeocoder(point: AppDefaults.searchRequest.origin),
        mapService: EstimatedMapService(),
        vehicleSuggestionStore: store
    )

    viewModel.refreshVehicleSuggestions(for: "h5")
    #expect(viewModel.vehicleSuggestions.map(\.name) == ["尚界 H5"])
    #expect(viewModel.isVehicleSuggestionPanelVisible)

    let suggestion = viewModel.vehicleSuggestions[0]
    viewModel.selectVehicleSuggestion(suggestion)

    #expect(viewModel.request.vehicleQuery == "尚界 H5")
    #expect(viewModel.vehicleSuggestions.isEmpty)
    #expect(!viewModel.isVehicleSuggestionPanelVisible)
}

@Test("Successful blank vehicle search records returned vehicle names")
func successfulBlankVehicleSearchRecordsReturnedVehicleNames() async {
    let store = VehicleSuggestionStore(
        learned: [],
        recent: [],
        builtIns: [],
        fileURL: temporarySuggestionURL()
    )
    let provider = StubRentalSearchProvider(results: [
        PlatformEvidenceResult(
            platform: .carInc,
            status: PlatformEvidenceStatus(platform: .carInc, kind: .ready, message: "ok", sourceUrl: "https://www.zuche.com/"),
            listings: [
                makeListing(vehicleName: "尚界 H5"),
                makeListing(vehicleName: "未指定车型")
            ]
        )
    ])
    let viewModel = SearchViewModel(
        searchProvider: provider,
        geocoder: CurrentRequestGeocoder(point: AppDefaults.searchRequest.origin),
        mapService: EstimatedMapService(),
        vehicleSuggestionStore: store
    )
    viewModel.request.vehicleQuery = ""

    await viewModel.runSearch()

    #expect(store.learnedSuggestions.map(\.name) == ["尚界 H5"])
}

private func temporarySuggestionURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("vehicle-suggestions-\(UUID().uuidString).json")
}

private func makeListing(vehicleName: String) -> RentalListing {
    RentalListing(
        id: "listing-\(vehicleName)",
        platform: .carInc,
        store: Store(
            id: "store",
            platform: .carInc,
            name: "北京通州店",
            city: "北京",
            address: "北京通州",
            location: AppDefaults.searchRequest.origin,
            distanceKm: 0.5,
            hours: "08:00-21:00"
        ),
        vehicleName: vehicleName,
        vehicleClass: "",
        basePrice: 100,
        platformFees: 0,
        insuranceFees: 0,
        oneWayFee: 0,
        sourceUrl: "https://www.zuche.com/",
        dataCompleteness: 0.8
    )
}
```

If `SearchViewModelTests.swift` already has helper names that conflict with `date`, `makeListing`, or `temporarySuggestionURL`, rename the new helpers to `vehicleSuggestionDate`, `makeVehicleSuggestionListing`, and `temporaryVehicleSuggestionURL`.

- [ ] **Step 2: Run tests and verify they fail**

Run: `swift test --filter SearchViewModelTests/Vehicle`

Expected: FAIL because `vehicleSuggestionStore` initializer parameter and ViewModel suggestion properties/actions do not exist.

- [ ] **Step 3: Add ViewModel dependency and published state**

In `Sources/CarRentalOptimizer/SearchViewModel.swift`, add published properties near the origin suggestion state:

```swift
@Published var vehicleSuggestions: [VehicleSuggestion] = []
@Published var isVehicleSuggestionPanelVisible = false
```

Add a stored dependency near `addressSuggestionProvider`:

```swift
private let vehicleSuggestionStore: VehicleSuggestionStore
```

Update all initializers:

```swift
self.vehicleSuggestionStore = VehicleSuggestionStore()
```

For the dependency-injected initializer, add a parameter with a default:

```swift
vehicleSuggestionStore: VehicleSuggestionStore = VehicleSuggestionStore(),
```

and assign:

```swift
self.vehicleSuggestionStore = vehicleSuggestionStore
```

- [ ] **Step 4: Add ViewModel suggestion actions**

Add these methods near the origin suggestion methods:

```swift
func refreshVehicleSuggestions(for query: String) {
    vehicleSuggestions = vehicleSuggestionStore.suggestions(matching: query, limit: 6)
    isVehicleSuggestionPanelVisible = !vehicleSuggestions.isEmpty
}

func selectVehicleSuggestion(_ suggestion: VehicleSuggestion) {
    vehicleSuggestionStore.recordSelection(suggestion, now: now())
    request.vehicleQuery = suggestion.name
    dismissVehicleSuggestions()
    refreshPreflightIssues()
}

func dismissVehicleSuggestions() {
    vehicleSuggestions = []
    isVehicleSuggestionPanelVisible = false
}

func recordVehicleSuggestions(from recommendations: [Recommendation]) {
    let names = recommendations.map(\.listing.vehicleName)
    vehicleSuggestionStore.recordSearchResults(names, now: now())
}
```

- [ ] **Step 5: Record suggestions only on successful fresh results**

In `performSearch`, after `recordSuccessfulResults(recommendations)` and before summary/status updates, add:

```swift
recordVehicleSuggestions(from: recommendations)
```

Do not add this call inside `restoreLatestSuccessfulResultsIfAvailable()`.

- [ ] **Step 6: Run ViewModel tests and verify they pass**

Run: `swift test --filter SearchViewModelTests`

Expected: PASS.

- [ ] **Step 7: Commit Task 2**

```bash
git add Sources/CarRentalOptimizer/SearchViewModel.swift Tests/CarRentalOptimizerTests/SearchViewModelTests.swift
git commit -m "feat: learn vehicle suggestions from searches"
```

---

### Task 3: Search Panel Suggestion UI

**Files:**
- Modify: `Sources/CarRentalOptimizer/SearchPanelView.swift`
- Modify: `Tests/CarRentalOptimizerTests/UIEffectsSourceTests.swift`

**Interfaces:**
- Consumes:
  - `SearchViewModel.vehicleSuggestions`
  - `SearchViewModel.isVehicleSuggestionPanelVisible`
  - `SearchViewModel.refreshVehicleSuggestions(for:)`
  - `SearchViewModel.selectVehicleSuggestion(_:)`
  - `SearchViewModel.dismissVehicleSuggestions()`
- Produces:
  - `private struct VehicleSuggestionField: View`
  - `private struct VehicleSuggestionDropdown: View`

- [ ] **Step 1: Write failing UI source-contract test**

In `Tests/CarRentalOptimizerTests/UIEffectsSourceTests.swift`, update `searchPanelUsesCommandConsoleComponents`:

```swift
#expect(source.contains("VehicleSuggestionField("))
#expect(source.contains("VehicleSuggestionDropdown("))
```

- [ ] **Step 2: Run the UI source test and verify it fails**

Run: `swift test --filter UIEffectsSourceTests/searchPanelUsesCommandConsoleComponents`

Expected: FAIL because `SearchPanelView.swift` does not contain the vehicle suggestion field or dropdown.

- [ ] **Step 3: Replace the plain vehicle text field**

In `Sources/CarRentalOptimizer/SearchPanelView.swift`, replace:

```swift
FieldView(label: "车型") {
    TextField("瑞虎8 / SUV / 留空查最近门店", text: $viewModel.request.vehicleQuery)
        .textFieldStyle(.roundedBorder)
        .controlSize(.large)
}
```

with:

```swift
VehicleSuggestionField()
```

In `compareButton`, call `viewModel.dismissVehicleSuggestions()` before starting search:

```swift
viewModel.dismissVehicleSuggestions()
```

In the date `onChange` handlers and `dismissOriginInput()`, also call `viewModel.dismissVehicleSuggestions()`.

- [ ] **Step 4: Add `VehicleSuggestionField` and dropdown views**

Add these private views below `OriginLocationField`:

```swift
private struct VehicleSuggestionField: View {
    @EnvironmentObject var viewModel: SearchViewModel
    @FocusState private var isVehicleFieldFocused: Bool
    @State private var isEditingVehicle = false

    private var shouldShowSuggestionPanel: Bool {
        isEditingVehicle
            && isVehicleFieldFocused
            && viewModel.isVehicleSuggestionPanelVisible
            && !viewModel.vehicleSuggestions.isEmpty
    }

    var body: some View {
        FieldView(label: "车型") {
            VStack(alignment: .leading, spacing: 8) {
                TextField(
                    "瑞虎8 / SUV / 留空查最近门店",
                    text: Binding(
                        get: { viewModel.request.vehicleQuery },
                        set: { value in
                            isEditingVehicle = true
                            viewModel.request.vehicleQuery = value
                            viewModel.refreshVehicleSuggestions(for: value)
                        }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .focused($isVehicleFieldFocused)
                .onSubmit {
                    closeSuggestions()
                }
                .onChange(of: isVehicleFieldFocused) { _, focused in
                    if focused {
                        isEditingVehicle = true
                        viewModel.refreshVehicleSuggestions(for: viewModel.request.vehicleQuery)
                    } else {
                        closeSuggestions()
                    }
                }

                if shouldShowSuggestionPanel {
                    VehicleSuggestionDropdown(suggestions: viewModel.vehicleSuggestions) { suggestion in
                        viewModel.selectVehicleSuggestion(suggestion)
                        closeSuggestions()
                    }
                }
            }
        }
    }

    private func closeSuggestions() {
        isEditingVehicle = false
        isVehicleFieldFocused = false
        viewModel.dismissVehicleSuggestions()
    }
}

private struct VehicleSuggestionDropdown: View {
    let suggestions: [VehicleSuggestion]
    let onSelect: (VehicleSuggestion) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(suggestions) { suggestion in
                suggestionButton(suggestion)

                if suggestion.id != suggestions.last?.id {
                    Divider()
                        .padding(.leading, 35)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(WorkbenchStyle.elevatedSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(WorkbenchStyle.commandBlue.opacity(0.24), lineWidth: 1)
                )
                .shadow(color: WorkbenchStyle.cardShadow.opacity(0.62), radius: 14, x: 0, y: 8)
        )
    }

    private func suggestionButton(_ suggestion: VehicleSuggestion) -> some View {
        Button {
            onSelect(suggestion)
        } label: {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "car.fill")
                    .foregroundStyle(WorkbenchStyle.accent)
                    .frame(width: 18)

                Text(suggestion.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WorkbenchStyle.ink)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(suggestion.sourceLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WorkbenchStyle.muted)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.black.opacity(0.001))
    }
}
```

- [ ] **Step 5: Run UI source tests and compile**

Run: `swift test --filter UIEffectsSourceTests`

Expected: PASS.

Run: `swift test --filter SearchViewModelTests`

Expected: PASS.

- [ ] **Step 6: Commit Task 3**

```bash
git add Sources/CarRentalOptimizer/SearchPanelView.swift Tests/CarRentalOptimizerTests/UIEffectsSourceTests.swift
git commit -m "feat: show vehicle suggestions in search panel"
```

---

### Task 4: Full Verification

**Files:**
- No new files.
- Verify all modified files from Tasks 1-3.

**Interfaces:**
- Consumes all produced interfaces from Tasks 1-3.
- Produces a verified working branch.

- [ ] **Step 1: Run focused suggestion tests**

Run: `swift test --filter VehicleSuggestionTests`

Expected: PASS.

- [ ] **Step 2: Run ViewModel tests**

Run: `swift test --filter SearchViewModelTests`

Expected: PASS.

- [ ] **Step 3: Run UI source tests**

Run: `swift test --filter UIEffectsSourceTests`

Expected: PASS.

- [ ] **Step 4: Run the full test suite**

Run: `swift test`

Expected: PASS with all tests green.

- [ ] **Step 5: Inspect final diff**

Run: `git diff --stat HEAD~3..HEAD`

Expected: Diff includes only:

```text
Sources/CarRentalOptimizer/VehicleSuggestions.swift
Sources/CarRentalOptimizer/SearchViewModel.swift
Sources/CarRentalOptimizer/SearchPanelView.swift
Tests/CarRentalOptimizerTests/VehicleSuggestionTests.swift
Tests/CarRentalOptimizerTests/SearchViewModelTests.swift
Tests/CarRentalOptimizerTests/UIEffectsSourceTests.swift
```

- [ ] **Step 6: Final commit only if verification changes were needed**

If Task 4 required any fixes after Task 3, commit them:

```bash
git add Sources/CarRentalOptimizer Tests/CarRentalOptimizerTests
git commit -m "test: verify vehicle suggestions"
```

If no files changed during Task 4, do not create an empty commit.

---

## Self-Review Notes

- Spec coverage: Task 1 covers built-ins, matching, ranking, caps, dedupe, persistence model, and placeholder filtering. Task 2 covers recording successful blank searches and selection behavior. Task 3 covers the compact dropdown and non-searching selection UI. Task 4 covers full verification.
- Placeholder scan: The plan has no TBD/TODO/fill-later steps. Conditional Task 4 commit is explicit and does not require an empty commit.
- Type consistency: `VehicleSuggestion`, `VehicleSuggestionSource`, `VehicleSuggestionStore`, `refreshVehicleSuggestions(for:)`, `selectVehicleSuggestion(_:)`, `dismissVehicleSuggestions()`, and `recordVehicleSuggestions(from:)` are introduced before later tasks consume them.
