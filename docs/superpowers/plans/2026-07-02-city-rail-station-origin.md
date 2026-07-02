# City Rail Station Origin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the left-side origin input resolve a city-level train arrival point into confirmed rail-station origin suggestions before rental comparison.

**Architecture:** Add protocol-driven origin suggestion types beside the current location services, then have `SearchViewModel` merge rail-station and address candidates into one dropdown flow. Station selection writes the existing `SearchRequest.originLabel` and `SearchRequest.origin`, so platform search and ranking stay unchanged.

**Tech Stack:** Swift 5.9 package, SwiftUI, MapKit/CoreLocation, Swift Testing, macOS 14, no third-party dependencies.

## Global Constraints

- The feature should remain dependency-free beyond the existing Apple location frameworks.
- Suggestion results should appear through the existing debounced path, not through a new always-on background loop.
- The UI should preserve the compact left-panel workflow and avoid adding another required setup step.
- The resolver should be protocol-driven so tests can use deterministic stub data.
- Production recommendations only come from official platform evidence and route estimates; the app must not invent listings or prices when platforms fail.
- City-center coordinates must not be used as a silent fallback for station-oriented searches.
- A nearby station fallback is acceptable only when it is visible and selected by the user.

---

## File Structure

- Create `Sources/CarRentalOptimizer/OriginSuggestions.swift`: unified dropdown suggestion model, rail-station suggestion model, protocol, empty provider, merge/dedup helpers, and conservative city-level origin detection.
- Create `Sources/CarRentalOptimizer/RailStationServices.swift`: MapKit-backed rail-station provider and pure helper functions for query expansion, filtering, and station ranking.
- Modify `Sources/CarRentalOptimizer/SearchViewModel.swift`: inject the rail-station provider, change `originSuggestions` to the unified type, merge station/address lookups, track unresolved city-level input, and block search until a concrete candidate is selected.
- Modify `Sources/CarRentalOptimizer/SearchPanelView.swift`: render unified suggestions with station/address icons and fallback notes.
- Modify `Tests/CarRentalOptimizerTests/LocationInputTests.swift`: add deterministic station suggestion stubs and cover merge order, selection, city-only blocking, fallback, provider failure, stale lookup, and blank input behavior.

---

### Task 1: Add Unified Origin Suggestion Models

**Files:**
- Create: `Sources/CarRentalOptimizer/OriginSuggestions.swift`
- Test: `Tests/CarRentalOptimizerTests/LocationInputTests.swift`

**Interfaces:**
- Consumes: `AddressSuggestion`, `GeoPoint`, `localizedChineseLocationText(_:)`, `originCityCandidates(from:)`
- Produces:
  - `enum OriginSuggestionKind: Equatable`
  - `struct OriginSuggestion: Equatable, Identifiable`
  - `enum RailStationSuggestionKind: Equatable`
  - `struct RailStationSuggestion: Equatable, Identifiable`
  - `protocol RailStationSuggestionProviding`
  - `struct EmptyRailStationSuggestionProvider`
  - `func mergeOriginSuggestions(railStations: [RailStationSuggestion], addresses: [AddressSuggestion]) -> [OriginSuggestion]`
  - `func isKnownCityLevelOrigin(_ value: String) -> Bool`

- [ ] **Step 1: Write the failing model tests**

Append these tests inside `LocationInputTests`, before the closing brace of the suite:

```swift
    @Test("Rail station suggestions are merged before address suggestions")
    func railStationSuggestionsAreMergedBeforeAddressSuggestions() {
        let stations = [
            RailStationSuggestion(
                id: "dezhou-east",
                title: "德州东站",
                subtitle: "德州市",
                point: GeoPoint(lat: 37.443, lng: 116.374),
                kind: .recommended,
                fallbackNote: nil
            ),
            RailStationSuggestion(
                id: "dezhou",
                title: "德州站",
                subtitle: "德州市",
                point: GeoPoint(lat: 37.451, lng: 116.304),
                kind: .station,
                fallbackNote: nil
            ),
        ]
        let addresses = [
            AddressSuggestion(
                id: "wanda",
                title: "德州万达广场",
                subtitle: "德州市德城区",
                point: GeoPoint(lat: 37.458, lng: 116.307)
            ),
        ]

        let merged = mergeOriginSuggestions(railStations: stations, addresses: addresses)

        #expect(merged.map(\.title) == ["德州东站", "德州站", "德州万达广场"])
        #expect(merged.map(\.kind) == [.railStation, .railStation, .address])
        #expect(merged[0].displayName == "德州东站，德州市")
    }

    @Test("Duplicate station and address suggestions keep the rail station candidate")
    func duplicateStationAndAddressSuggestionsKeepRailStationCandidate() {
        let point = GeoPoint(lat: 37.443, lng: 116.374)
        let merged = mergeOriginSuggestions(
            railStations: [
                RailStationSuggestion(
                    id: "rail-dezhou-east",
                    title: "德州东站",
                    subtitle: "德州市",
                    point: point,
                    kind: .recommended,
                    fallbackNote: nil
                ),
            ],
            addresses: [
                AddressSuggestion(
                    id: "address-dezhou-east",
                    title: "德州东站",
                    subtitle: "德州市",
                    point: point
                ),
            ]
        )

        #expect(merged.count == 1)
        #expect(merged[0].kind == .railStation)
        #expect(merged[0].id == "rail-dezhou-east")
    }

    @Test("Known city level origin detection is conservative")
    func knownCityLevelOriginDetectionIsConservative() {
        #expect(isKnownCityLevelOrigin("北京"))
        #expect(isKnownCityLevelOrigin("上海市"))
        #expect(!isKnownCityLevelOrigin("北京南站"))
        #expect(!isKnownCityLevelOrigin("北京市丰台区北京南站"))
        #expect(!isKnownCityLevelOrigin("京东总部"))
    }
```

- [ ] **Step 2: Run the targeted tests to verify they fail**

Run:

```bash
swift test --filter LocationInputTests/railStationSuggestionsAreMergedBeforeAddressSuggestions
```

Expected: build fails because `RailStationSuggestion`, `mergeOriginSuggestions`, or related types are not defined.

- [ ] **Step 3: Add the unified model implementation**

Create `Sources/CarRentalOptimizer/OriginSuggestions.swift`:

```swift
import CarRentalDomain
import Foundation

enum OriginSuggestionKind: Equatable {
    case address
    case railStation
    case nearestRailStationFallback

    var systemImage: String {
        switch self {
        case .address:
            return "mappin.circle.fill"
        case .railStation:
            return "tram.fill"
        case .nearestRailStationFallback:
            return "tram.circle.fill"
        }
    }

    var label: String {
        switch self {
        case .address:
            return "地址"
        case .railStation:
            return "车站"
        case .nearestRailStationFallback:
            return "附近车站"
        }
    }
}

struct OriginSuggestion: Equatable, Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let point: GeoPoint
    let kind: OriginSuggestionKind
    let fallbackNote: String?

    var displayName: String {
        let localizedTitle = localizedChineseLocationText(title)
        let localizedSubtitle = localizedChineseLocationText(subtitle)
        return localizedSubtitle.isEmpty ? localizedTitle : "\(localizedTitle)，\(localizedSubtitle)"
    }

    static func address(_ suggestion: AddressSuggestion) -> OriginSuggestion {
        OriginSuggestion(
            id: suggestion.id,
            title: suggestion.title,
            subtitle: suggestion.subtitle,
            point: suggestion.point,
            kind: .address,
            fallbackNote: nil
        )
    }

    static func railStation(_ suggestion: RailStationSuggestion) -> OriginSuggestion {
        OriginSuggestion(
            id: suggestion.id,
            title: suggestion.title,
            subtitle: suggestion.subtitle,
            point: suggestion.point,
            kind: suggestion.kind.originSuggestionKind,
            fallbackNote: suggestion.fallbackNote
        )
    }
}

enum RailStationSuggestionKind: Equatable {
    case recommended
    case station
    case nearestFallback

    var originSuggestionKind: OriginSuggestionKind {
        switch self {
        case .recommended, .station:
            return .railStation
        case .nearestFallback:
            return .nearestRailStationFallback
        }
    }
}

struct RailStationSuggestion: Equatable, Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let point: GeoPoint
    let kind: RailStationSuggestionKind
    let fallbackNote: String?
}

protocol RailStationSuggestionProviding {
    func stationSuggestions(for query: String, near origin: GeoPoint?) async throws -> [RailStationSuggestion]
}

struct EmptyRailStationSuggestionProvider: RailStationSuggestionProviding {
    func stationSuggestions(for query: String, near origin: GeoPoint?) async throws -> [RailStationSuggestion] {
        []
    }
}

func mergeOriginSuggestions(
    railStations: [RailStationSuggestion],
    addresses: [AddressSuggestion]
) -> [OriginSuggestion] {
    let ordered = railStations.map(OriginSuggestion.railStation) + addresses.map(OriginSuggestion.address)
    var seen = Set<String>()
    return ordered.filter { suggestion in
        let key = normalizedOriginSuggestionKey(suggestion)
        guard !seen.contains(key) else { return false }
        seen.insert(key)
        return true
    }
}

func isKnownCityLevelOrigin(_ value: String) -> Bool {
    let localized = localizedChineseLocationText(value)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard localized.count >= 2 else { return false }

    let detailMarkers = ["站", "区", "县", "镇", "街", "路", "号", "机场", "园区", "广场", "大学", "酒店"]
    if detailMarkers.contains(where: { localized.contains($0) }) {
        return false
    }

    let withoutCitySuffix = localized.hasSuffix("市") ? String(localized.dropLast()) : localized
    let aliases = originCityCandidates(from: localized)
    if aliases.contains(where: { alias in localized == alias || withoutCitySuffix == alias }) {
        return true
    }
    return localized.hasSuffix("市")
}

private func normalizedOriginSuggestionKey(_ suggestion: OriginSuggestion) -> String {
    let title = localizedChineseLocationText(suggestion.title)
        .replacingOccurrences(of: " ", with: "")
        .lowercased()
    let subtitle = localizedChineseLocationText(suggestion.subtitle)
        .replacingOccurrences(of: " ", with: "")
        .lowercased()
    return "\(title)|\(subtitle)"
}
```

- [ ] **Step 4: Run the model tests to verify they pass**

Run:

```bash
swift test --filter LocationInputTests/railStationSuggestionsAreMergedBeforeAddressSuggestions
swift test --filter LocationInputTests/duplicateStationAndAddressSuggestionsKeepRailStationCandidate
swift test --filter LocationInputTests/knownCityLevelOriginDetectionIsConservative
```

Expected: all three targeted tests pass.

- [ ] **Step 5: Commit the model layer**

Run:

```bash
git add Sources/CarRentalOptimizer/OriginSuggestions.swift Tests/CarRentalOptimizerTests/LocationInputTests.swift
git commit -m "Add unified origin suggestion models"
```

Expected: commit succeeds with only the new model file and the model tests staged.

---

### Task 2: Implement the MapKit Rail Station Resolver

**Files:**
- Create: `Sources/CarRentalOptimizer/RailStationServices.swift`
- Test: `Tests/CarRentalOptimizerTests/LocationInputTests.swift`

**Interfaces:**
- Consumes: `RailStationSuggestionProviding`, `RailStationSuggestion`, `RailStationSuggestionKind`, `GeoPoint`
- Produces:
  - `struct AppleRailStationSuggestionProvider: RailStationSuggestionProviding`
  - `func railStationSearchQueries(for query: String) -> [String]`
  - `func isRailStationCandidateText(_ text: String) -> Bool`
  - `func isRejectedRailStationCandidateText(_ text: String) -> Bool`
  - `func rankedUniqueRailStationSuggestions(_ suggestions: [RailStationSuggestion]) -> [RailStationSuggestion]`

- [ ] **Step 1: Write failing pure resolver helper tests**

Append these tests inside `LocationInputTests`:

```swift
    @Test("Rail station search expands city input")
    func railStationSearchExpandsCityInput() {
        #expect(railStationSearchQueries(for: "德州") == ["德州 高铁站", "德州 火车站", "德州站", "德州"])
        #expect(railStationSearchQueries(for: "德州站") == ["德州站"])
    }

    @Test("Rail station text filtering accepts railway stations and rejects airports")
    func railStationTextFilteringAcceptsStationsAndRejectsAirports() {
        #expect(isRailStationCandidateText("德州东站 德州市"))
        #expect(isRailStationCandidateText("苏州北站 高铁站"))
        #expect(isRailStationCandidateText("济南火车站"))
        #expect(!isRailStationCandidateText("德州万达广场"))
        #expect(isRejectedRailStationCandidateText("德州机场"))
        #expect(isRejectedRailStationCandidateText("火车站机场大巴候车点"))
    }

    @Test("Rail station ranking keeps recommended stations first and deduplicates names")
    func railStationRankingKeepsRecommendedStationsFirstAndDeduplicatesNames() {
        let ranked = rankedUniqueRailStationSuggestions([
            RailStationSuggestion(id: "address", title: "德州站", subtitle: "德州市", point: GeoPoint(lat: 37.451, lng: 116.304), kind: .station, fallbackNote: nil),
            RailStationSuggestion(id: "east", title: "德州东站", subtitle: "德州市", point: GeoPoint(lat: 37.443, lng: 116.374), kind: .recommended, fallbackNote: nil),
            RailStationSuggestion(id: "east-duplicate", title: "德州东站", subtitle: "德州市德城区", point: GeoPoint(lat: 37.443, lng: 116.374), kind: .station, fallbackNote: nil),
        ])

        #expect(ranked.map(\.id) == ["east", "address"])
    }
```

- [ ] **Step 2: Run the resolver helper tests to verify they fail**

Run:

```bash
swift test --filter LocationInputTests/railStationSearchExpandsCityInput
```

Expected: build fails because the resolver helper functions are not defined.

- [ ] **Step 3: Add the MapKit resolver and helper functions**

Create `Sources/CarRentalOptimizer/RailStationServices.swift`:

```swift
import CarRentalDomain
import CoreLocation
import Foundation
import MapKit

struct AppleRailStationSuggestionProvider: RailStationSuggestionProviding {
    func stationSuggestions(for query: String, near origin: GeoPoint?) async throws -> [RailStationSuggestion] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        var suggestions: [RailStationSuggestion] = []
        for searchQuery in railStationSearchQueries(for: trimmed) {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = searchQuery
            request.resultTypes = [.address, .pointOfInterest]
            if let origin {
                request.region = MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: origin.lat, longitude: origin.lng),
                    latitudinalMeters: 250_000,
                    longitudinalMeters: 250_000
                )
            }

            let response = try await MKLocalSearch(request: request).start()
            let mapped = response.mapItems.compactMap { item -> RailStationSuggestion? in
                railStationSuggestion(from: item, query: trimmed)
            }
            suggestions.append(contentsOf: mapped)
        }

        return Array(rankedUniqueRailStationSuggestions(suggestions).prefix(6))
    }
}

func railStationSearchQueries(for query: String) -> [String] {
    let trimmed = localizedChineseLocationText(query)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return [] }
    if isRailStationCandidateText(trimmed) {
        return [trimmed]
    }
    return uniqueRailStationSearchQueries([
        "\(trimmed) 高铁站",
        "\(trimmed) 火车站",
        "\(trimmed)站",
        trimmed,
    ])
}

func isRailStationCandidateText(_ text: String) -> Bool {
    let localized = localizedChineseLocationText(text)
    guard !isRejectedRailStationCandidateText(localized) else { return false }
    let explicitTokens = ["火车站", "高铁站", "动车站", "铁路", "客运站"]
    if explicitTokens.contains(where: { localized.contains($0) }) {
        return true
    }
    let compact = localized.replacingOccurrences(of: " ", with: "")
    return compact.hasSuffix("站")
        || compact.contains("东站")
        || compact.contains("西站")
        || compact.contains("南站")
        || compact.contains("北站")
}

func isRejectedRailStationCandidateText(_ text: String) -> Bool {
    let localized = localizedChineseLocationText(text)
    let rejectedTokens = ["机场", "机场大巴", "公交站", "地铁站", "汽车站", "客运中心"]
    return rejectedTokens.contains(where: { localized.contains($0) })
}

func rankedUniqueRailStationSuggestions(_ suggestions: [RailStationSuggestion]) -> [RailStationSuggestion] {
    var seen = Set<String>()
    let unique = suggestions.filter { suggestion in
        let key = localizedChineseLocationText(suggestion.title)
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
        guard !seen.contains(key) else { return false }
        seen.insert(key)
        return true
    }

    return unique.sorted {
        if stationRank($0) != stationRank($1) {
            return stationRank($0) < stationRank($1)
        }
        return $0.title.localizedStandardCompare($1.title) == .orderedAscending
    }
}

private func railStationSuggestion(from item: MKMapItem, query: String) -> RailStationSuggestion? {
    guard let coordinate = item.placemark.location?.coordinate else { return nil }
    let title = localizedChineseLocationText(
        item.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? item.name!.trimmingCharacters(in: .whitespacesAndNewlines)
            : query
    )
    let subtitle = localizedChineseLocationText([
        item.placemark.locality,
        item.placemark.administrativeArea,
        item.placemark.subLocality,
    ]
    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
    .filter { !$0.isEmpty }
    .joined(separator: " "))
    let combined = "\(title) \(subtitle)"
    guard isRailStationCandidateText(combined) else { return nil }

    let kind: RailStationSuggestionKind = title.contains("东站")
        || title.contains("南站")
        || title.contains("高铁")
        ? .recommended
        : .station

    return RailStationSuggestion(
        id: "rail-\(title)-\(subtitle)-\(coordinate.latitude)-\(coordinate.longitude)",
        title: title,
        subtitle: subtitle,
        point: GeoPoint(lat: coordinate.latitude, lng: coordinate.longitude),
        kind: kind,
        fallbackNote: nil
    )
}

private func stationRank(_ suggestion: RailStationSuggestion) -> Int {
    switch suggestion.kind {
    case .recommended:
        return 0
    case .station:
        return 1
    case .nearestFallback:
        return 2
    }
}

private func uniqueRailStationSearchQueries(_ queries: [String]) -> [String] {
    var seen = Set<String>()
    return queries.filter { query in
        let key = query.replacingOccurrences(of: " ", with: "")
        guard !seen.contains(key) else { return false }
        seen.insert(key)
        return true
    }
}
```

- [ ] **Step 4: Run the resolver helper tests to verify they pass**

Run:

```bash
swift test --filter LocationInputTests/railStationSearchExpandsCityInput
swift test --filter LocationInputTests/railStationTextFilteringAcceptsStationsAndRejectsAirports
swift test --filter LocationInputTests/railStationRankingKeepsRecommendedStationsFirstAndDeduplicatesNames
```

Expected: all resolver helper tests pass.

- [ ] **Step 5: Commit the resolver**

Run:

```bash
git add Sources/CarRentalOptimizer/RailStationServices.swift Tests/CarRentalOptimizerTests/LocationInputTests.swift
git commit -m "Add rail station suggestion resolver"
```

Expected: commit succeeds with the resolver and pure resolver tests staged.

---

### Task 3: Merge Rail Stations Into SearchViewModel Suggestions

**Files:**
- Modify: `Sources/CarRentalOptimizer/SearchViewModel.swift`
- Test: `Tests/CarRentalOptimizerTests/LocationInputTests.swift`

**Interfaces:**
- Consumes: `RailStationSuggestionProviding`, `OriginSuggestion`, `mergeOriginSuggestions`, `isKnownCityLevelOrigin`
- Produces:
  - `@Published var originSuggestions: [OriginSuggestion]`
  - `func selectOriginSuggestion(_ suggestion: OriginSuggestion) async`
  - `private var requiresOriginCandidateSelection: Bool`

- [ ] **Step 1: Add failing ViewModel merge and selection tests**

Replace the existing test named `Address suggestions update as user edits origin` with:

```swift
    @Test("Origin suggestions prioritize rail stations and selection updates request origin")
    func originSuggestionsPrioritizeRailStationsAndSelectionUpdatesRequestOrigin() async {
        let station = RailStationSuggestion(
            id: "dezhou-east",
            title: "德州东站",
            subtitle: "德州市",
            point: GeoPoint(lat: 37.443, lng: 116.374),
            kind: .recommended,
            fallbackNote: nil
        )
        let address = AddressSuggestion(
            id: "wanda",
            title: "德州万达广场",
            subtitle: "德州市德城区",
            point: GeoPoint(lat: 37.458, lng: 116.307)
        )
        let stationProvider = StubRailStationSuggestionProvider(suggestions: [station])
        let addressProvider = StubAddressSuggestionProvider(suggestions: [address])
        let viewModel = SearchViewModel(
            searchProvider: StubRentalSearchProvider(results: []),
            geocoder: CurrentRequestGeocoder(point: AppDefaults.searchRequest.origin),
            mapService: EstimatedMapService(),
            currentLocationProvider: StubCurrentLocationProvider(),
            addressSuggestionProvider: addressProvider,
            railStationSuggestionProvider: stationProvider
        )

        await viewModel.updateOriginInput("德州")

        #expect(stationProvider.queries == ["德州"])
        #expect(addressProvider.queries == ["德州"])
        #expect(viewModel.originSuggestions.map(\.title) == ["德州东站", "德州万达广场"])
        #expect(viewModel.originSuggestions.map(\.kind) == [.railStation, .address])
        #expect(viewModel.isOriginSuggestionPanelVisible)

        await viewModel.selectOriginSuggestion(viewModel.originSuggestions[0])

        #expect(viewModel.request.originLabel == "德州东站，德州市")
        #expect(viewModel.request.origin == GeoPoint(lat: 37.443, lng: 116.374))
        #expect(viewModel.originSuggestions.isEmpty)
        #expect(!viewModel.isOriginSuggestionPanelVisible)
    }
```

Append this stub near the existing `StubAddressSuggestionProvider`:

```swift
@MainActor
private final class StubRailStationSuggestionProvider: RailStationSuggestionProviding {
    let suggestions: [RailStationSuggestion]
    private(set) var queries: [String] = []

    init(suggestions: [RailStationSuggestion] = []) {
        self.suggestions = suggestions
    }

    func stationSuggestions(for query: String, near origin: GeoPoint?) async throws -> [RailStationSuggestion] {
        queries.append(query)
        return suggestions
    }
}
```

- [ ] **Step 2: Run the ViewModel merge test to verify it fails**

Run:

```bash
swift test --filter LocationInputTests/originSuggestionsPrioritizeRailStationsAndSelectionUpdatesRequestOrigin
```

Expected: build fails because `SearchViewModel` does not accept `railStationSuggestionProvider` and still publishes `[AddressSuggestion]`.

- [ ] **Step 3: Update SearchViewModel injection and suggestion merging**

In `SearchViewModel.swift`, change the published suggestions and dependencies:

```swift
    @Published var originSuggestions: [OriginSuggestion] = []
```

Add the dependency and unresolved selection flag near existing providers:

```swift
    private let railStationSuggestionProvider: RailStationSuggestionProviding
    private var requiresOriginCandidateSelection = false
```

In the default initializer, set:

```swift
        self.railStationSuggestionProvider = AppleRailStationSuggestionProvider()
```

In the snapshot initializer, set:

```swift
        self.railStationSuggestionProvider = EmptyRailStationSuggestionProvider()
```

Extend the test initializer signature:

```swift
        railStationSuggestionProvider: RailStationSuggestionProviding = EmptyRailStationSuggestionProvider(),
```

and assign:

```swift
        self.railStationSuggestionProvider = railStationSuggestionProvider
```

Replace `updateOriginInput(_:)` with:

```swift
    func updateOriginInput(_ value: String) async {
        request.originLabel = value
        resolvedOriginLabel = nil
        requiresOriginCandidateSelection = false
        refreshPreflightIssues()
        originSuggestionRequestID += 1
        let requestID = originSuggestionRequestID

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            originSuggestions = []
            isLoadingOriginSuggestions = false
            isOriginSuggestionPanelVisible = false
            originStatus = "输入地址、城市或车站后会联想候选位置。"
            return
        }

        originSuggestions = []
        requiresOriginCandidateSelection = isKnownCityLevelOrigin(trimmed)
        isLoadingOriginSuggestions = true
        isOriginSuggestionPanelVisible = true
        refreshPreflightIssues()

        let railResult = await loadRailStationSuggestions(for: trimmed)
        let addressResult = await loadAddressSuggestions(for: trimmed)
        guard requestID == originSuggestionRequestID else { return }

        isLoadingOriginSuggestions = false
        let railSuggestions = (try? railResult.get()) ?? []
        let addressSuggestions = (try? addressResult.get()) ?? []
        originSuggestions = mergeOriginSuggestions(railStations: railSuggestions, addresses: addressSuggestions)
        requiresOriginCandidateSelection = isKnownCityLevelOrigin(trimmed) || !railSuggestions.isEmpty
        refreshPreflightIssues()

        isOriginSuggestionPanelVisible = !originSuggestions.isEmpty
        if !originSuggestions.isEmpty {
            originStatus = "选择一个候选位置。"
        } else if railResult.isFailure && addressResult.isFailure {
            originStatus = "位置联想失败，请输入更具体的车站或地址。"
        } else {
            originStatus = "没有找到匹配位置，可继续输入。"
        }
    }
```

Add these helpers inside `SearchViewModel`:

```swift
    private func loadRailStationSuggestions(for query: String) async -> Result<[RailStationSuggestion], Error> {
        do {
            return .success(try await railStationSuggestionProvider.stationSuggestions(for: query, near: request.origin))
        } catch {
            return .failure(error)
        }
    }

    private func loadAddressSuggestions(for query: String) async -> Result<[AddressSuggestion], Error> {
        do {
            return .success(try await addressSuggestionProvider.suggestions(for: query, near: request.origin))
        } catch {
            return .failure(error)
        }
    }
```

Add this private `Result` convenience below `SearchViewModel`:

```swift
private extension Result {
    var isFailure: Bool {
        if case .failure = self {
            return true
        }
        return false
    }
}
```

Replace `selectOriginSuggestion(_:)` with:

```swift
    func selectOriginSuggestion(_ suggestion: OriginSuggestion) async {
        originSuggestionRequestID += 1
        request.originLabel = suggestion.displayName
        request.origin = suggestion.point
        resolvedOriginLabel = request.originLabel
        requiresOriginCandidateSelection = false
        originSuggestions = []
        isLoadingOriginSuggestions = false
        isOriginSuggestionPanelVisible = false
        originStatus = suggestion.fallbackNote ?? "已选择候选位置。"
        refreshPreflightIssues()
    }
```

In `refreshCurrentLocationOutcome()`, after `resolvedOriginLabel = location.label`, add:

```swift
            requiresOriginCandidateSelection = false
```

In `dismissOriginSuggestions()`, keep `requiresOriginCandidateSelection` unchanged so dismissing the dropdown does not make a city-only origin safe to search.

- [ ] **Step 4: Run the ViewModel merge test to verify it passes**

Run:

```bash
swift test --filter LocationInputTests/originSuggestionsPrioritizeRailStationsAndSelectionUpdatesRequestOrigin
```

Expected: targeted test passes.

- [ ] **Step 5: Update older address selection assertions**

In `LocationInputTests.swift`, update any existing assertions that compare `viewModel.originSuggestions == suggestions` to compare titles or mapped address suggestions instead:

```swift
#expect(viewModel.originSuggestions.map(\.title) == suggestions.map(\.title))
#expect(viewModel.originSuggestions.allSatisfy { $0.kind == .address })
```

Update calls to `selectOriginSuggestion(suggestions[0])` to select from the ViewModel:

```swift
await viewModel.selectOriginSuggestion(viewModel.originSuggestions[0])
```

- [ ] **Step 6: Run the full location input suite**

Run:

```bash
swift test --filter LocationInputTests
```

Expected: all `LocationInputTests` pass.

- [ ] **Step 7: Commit ViewModel suggestion merging**

Run:

```bash
git add Sources/CarRentalOptimizer/SearchViewModel.swift Tests/CarRentalOptimizerTests/LocationInputTests.swift
git commit -m "Merge rail station origin suggestions"
```

Expected: commit succeeds with ViewModel and tests staged.

---

### Task 4: Block City-Level Search Until Candidate Selection

**Files:**
- Modify: `Sources/CarRentalOptimizer/SearchViewModel.swift`
- Test: `Tests/CarRentalOptimizerTests/LocationInputTests.swift`

**Interfaces:**
- Consumes: `requiresOriginCandidateSelection`, `SearchPreflightIssue`
- Produces: blocking preflight issue with id `origin-selection-required`

- [ ] **Step 1: Write the failing city-only blocking test**

Append this test inside `LocationInputTests`:

```swift
    @Test("City level origin requires selecting a concrete candidate before search")
    func cityLevelOriginRequiresSelectingConcreteCandidateBeforeSearch() async {
        let searchProvider = RecordingRentalSearchProvider()
        let stationProvider = StubRailStationSuggestionProvider(suggestions: [
            RailStationSuggestion(
                id: "dezhou-east",
                title: "德州东站",
                subtitle: "德州市",
                point: GeoPoint(lat: 37.443, lng: 116.374),
                kind: .recommended,
                fallbackNote: nil
            ),
        ])
        let viewModel = SearchViewModel(
            searchProvider: searchProvider,
            geocoder: CurrentRequestGeocoder(point: AppDefaults.searchRequest.origin),
            mapService: EstimatedMapService(),
            currentLocationProvider: StubCurrentLocationProvider(),
            addressSuggestionProvider: StubAddressSuggestionProvider(),
            railStationSuggestionProvider: stationProvider
        )

        await viewModel.updateOriginInput("德州")
        await viewModel.runSearch()

        #expect(searchProvider.requests.isEmpty)
        #expect(viewModel.searchProgressPhase == .failed)
        #expect(viewModel.preflightIssues.contains { $0.id == "origin-selection-required" && $0.severity == .blocking })

        await viewModel.selectOriginSuggestion(viewModel.originSuggestions[0])
        await viewModel.runSearch()

        #expect(searchProvider.requests.count == 1)
        #expect(searchProvider.requests[0].originLabel == "德州东站，德州市")
    }
```

Append this recording provider near `StubRentalSearchProvider`:

```swift
@MainActor
private final class RecordingRentalSearchProvider: RentalSearchProviding {
    private(set) var requests: [SearchRequest] = []

    func search(request: SearchRequest) async -> [PlatformEvidenceResult] {
        requests.append(request)
        return []
    }
}
```

- [ ] **Step 2: Run the city-only blocking test to verify it fails**

Run:

```bash
swift test --filter LocationInputTests/cityLevelOriginRequiresSelectingConcreteCandidateBeforeSearch
```

Expected: test fails because search still reaches the provider or no blocking issue is emitted.

- [ ] **Step 3: Add the ViewModel-specific preflight issue**

In `SearchViewModel.refreshPreflightIssues()`, replace the method body with:

```swift
    func refreshPreflightIssues() {
        var issues = validateSearchPreflight(request).issues
        if requiresOriginCandidateSelection {
            issues.append(SearchPreflightIssue(
                id: "origin-selection-required",
                severity: .blocking,
                title: "请选择到达车站",
                message: "已识别到城市或车站联想，请先选择推荐车站或更具体地址，再开始比较。"
            ))
        }
        preflightIssues = issues
    }
```

Do not add this issue to `validateSearchPreflight(_:)`, because the condition is ViewModel state derived from user edits and suggestion resolution, not part of `SearchRequest`.

- [ ] **Step 4: Run the city-only blocking test to verify it passes**

Run:

```bash
swift test --filter LocationInputTests/cityLevelOriginRequiresSelectingConcreteCandidateBeforeSearch
```

Expected: targeted test passes.

- [ ] **Step 5: Run related search and trust tests**

Run:

```bash
swift test --filter LocationInputTests
swift test --filter SearchViewModelTests
swift test --filter SearchTrustPresentationTests
```

Expected: all targeted suites pass.

- [ ] **Step 6: Commit city-only search blocking**

Run:

```bash
git add Sources/CarRentalOptimizer/SearchViewModel.swift Tests/CarRentalOptimizerTests/LocationInputTests.swift
git commit -m "Require station selection for city origins"
```

Expected: commit succeeds with ViewModel and tests staged.

---

### Task 5: Cover Fallback, Partial Failure, and Stale Lookup Paths

**Files:**
- Modify: `Tests/CarRentalOptimizerTests/LocationInputTests.swift`
- Modify: `Sources/CarRentalOptimizer/SearchViewModel.swift` if a test exposes a status-state bug

**Interfaces:**
- Consumes: `OriginSuggestion.fallbackNote`, stale `originSuggestionRequestID`, partial `Result` handling
- Produces: deterministic test coverage for requirements 9, 10, 11, and 12

- [ ] **Step 1: Add fallback and station failure tests**

Append these tests inside `LocationInputTests`:

```swift
    @Test("Nearest station fallback is visible and only applied after selection")
    func nearestStationFallbackIsVisibleAndOnlyAppliedAfterSelection() async {
        let fallback = RailStationSuggestion(
            id: "nearest-jinan-west",
            title: "济南西站",
            subtitle: "济南市槐荫区",
            point: GeoPoint(lat: 36.668, lng: 116.892),
            kind: .nearestFallback,
            fallbackNote: "未找到市内车站，已使用附近车站。"
        )
        let viewModel = SearchViewModel(
            searchProvider: StubRentalSearchProvider(results: []),
            geocoder: CurrentRequestGeocoder(point: AppDefaults.searchRequest.origin),
            mapService: EstimatedMapService(),
            currentLocationProvider: StubCurrentLocationProvider(),
            addressSuggestionProvider: StubAddressSuggestionProvider(),
            railStationSuggestionProvider: StubRailStationSuggestionProvider(suggestions: [fallback])
        )

        await viewModel.updateOriginInput("齐河")

        #expect(viewModel.request.originLabel == "齐河")
        #expect(viewModel.originSuggestions[0].kind == .nearestRailStationFallback)
        #expect(viewModel.originSuggestions[0].fallbackNote == "未找到市内车站，已使用附近车站。")

        await viewModel.selectOriginSuggestion(viewModel.originSuggestions[0])

        #expect(viewModel.request.originLabel == "济南西站，济南市槐荫区")
        #expect(viewModel.request.origin == GeoPoint(lat: 36.668, lng: 116.892))
        #expect(viewModel.originStatus == "未找到市内车站，已使用附近车站。")
    }

    @Test("Rail station lookup failure preserves address suggestions")
    func railStationLookupFailurePreservesAddressSuggestions() async {
        let address = AddressSuggestion(
            id: "jd",
            title: "京东总部",
            subtitle: "北京市通州区",
            point: GeoPoint(lat: 39.7784, lng: 116.5629)
        )
        let viewModel = SearchViewModel(
            searchProvider: StubRentalSearchProvider(results: []),
            geocoder: CurrentRequestGeocoder(point: AppDefaults.searchRequest.origin),
            mapService: EstimatedMapService(),
            currentLocationProvider: StubCurrentLocationProvider(),
            addressSuggestionProvider: StubAddressSuggestionProvider(suggestions: [address]),
            railStationSuggestionProvider: FailingRailStationSuggestionProvider()
        )

        await viewModel.updateOriginInput("京东总部")

        #expect(viewModel.originSuggestions.map(\.title) == ["京东总部"])
        #expect(viewModel.originSuggestions.allSatisfy { $0.kind == .address })
        #expect(viewModel.originStatus == "选择一个候选位置。")
    }
```

Add the failing provider near the station stub:

```swift
private struct FailingRailStationSuggestionProvider: RailStationSuggestionProviding {
    func stationSuggestions(for query: String, near origin: GeoPoint?) async throws -> [RailStationSuggestion] {
        throw AddressGeocodingError.notFound
    }
}
```

- [ ] **Step 2: Add stale station lookup test**

Append this test inside `LocationInputTests`:

```swift
    @Test("Dismissed origin suggestions ignore stale rail station lookup")
    func dismissedOriginSuggestionsIgnoreStaleRailStationLookup() async {
        let stationProvider = DelayedRailStationSuggestionProvider()
        let viewModel = SearchViewModel(
            searchProvider: StubRentalSearchProvider(results: []),
            geocoder: CurrentRequestGeocoder(point: AppDefaults.searchRequest.origin),
            mapService: EstimatedMapService(),
            currentLocationProvider: StubCurrentLocationProvider(),
            addressSuggestionProvider: StubAddressSuggestionProvider(),
            railStationSuggestionProvider: stationProvider
        )

        let lookupTask = Task {
            await viewModel.updateOriginInput("德州")
        }
        while stationProvider.continuation == nil {
            await Task.yield()
        }

        viewModel.dismissOriginSuggestions()
        stationProvider.resume(with: [
            RailStationSuggestion(
                id: "dezhou-east",
                title: "德州东站",
                subtitle: "德州市",
                point: GeoPoint(lat: 37.443, lng: 116.374),
                kind: .recommended,
                fallbackNote: nil
            ),
        ])
        await lookupTask.value

        #expect(viewModel.originSuggestions.isEmpty)
        #expect(!viewModel.isLoadingOriginSuggestions)
        #expect(!viewModel.isOriginSuggestionPanelVisible)
    }
```

Add the delayed provider near `DelayedAddressSuggestionProvider`:

```swift
@MainActor
private final class DelayedRailStationSuggestionProvider: RailStationSuggestionProviding {
    private(set) var continuation: CheckedContinuation<[RailStationSuggestion], Error>?

    func stationSuggestions(for query: String, near origin: GeoPoint?) async throws -> [RailStationSuggestion] {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume(with suggestions: [RailStationSuggestion]) {
        continuation?.resume(returning: suggestions)
        continuation = nil
    }
}
```

- [ ] **Step 3: Run the new edge-case tests**

Run:

```bash
swift test --filter LocationInputTests/nearestStationFallbackIsVisibleAndOnlyAppliedAfterSelection
swift test --filter LocationInputTests/railStationLookupFailurePreservesAddressSuggestions
swift test --filter LocationInputTests/dismissedOriginSuggestionsIgnoreStaleRailStationLookup
swift test --filter LocationInputTests/blankOriginInputClearsSuggestions
```

Expected: all four tests pass. If stale lookup fails, ensure `guard requestID == originSuggestionRequestID else { return }` remains after both provider calls complete and before assigning suggestions.

- [ ] **Step 4: Commit edge-case coverage**

Run:

```bash
git add Sources/CarRentalOptimizer/SearchViewModel.swift Tests/CarRentalOptimizerTests/LocationInputTests.swift
git commit -m "Cover rail station origin edge cases"
```

Expected: commit succeeds. If `SearchViewModel.swift` did not change in this task, only stage `LocationInputTests.swift`.

---

### Task 6: Render Unified Suggestions in the Origin Dropdown

**Files:**
- Modify: `Sources/CarRentalOptimizer/SearchPanelView.swift`
- Test: `Tests/CarRentalOptimizerTests/UIEffectsSourceTests.swift` or source-level checks in `LocationInputTests.swift`

**Interfaces:**
- Consumes: `OriginSuggestion`, `OriginSuggestionKind.systemImage`, `OriginSuggestionKind.label`, `fallbackNote`
- Produces: dropdown rows that distinguish station, fallback station, and address candidates

- [ ] **Step 1: Add source-level UI assertions**

In `Tests/CarRentalOptimizerTests/UIEffectsSourceTests.swift`, add a test in the existing suite that reads `SearchPanelView.swift`:

```swift
    @Test("Origin suggestion dropdown distinguishes stations from addresses")
    func originSuggestionDropdownDistinguishesStationsFromAddresses() throws {
        let source = try sourceFile("SearchPanelView.swift")

        #expect(source.contains("OriginSuggestionDropdown"))
        #expect(source.contains("suggestion.kind.systemImage"))
        #expect(source.contains("suggestion.kind.label"))
        #expect(source.contains("suggestion.fallbackNote"))
    }
```

If `UIEffectsSourceTests.swift` does not already have a helper named `sourceFile(_:)`, add this private helper at the bottom of that file:

```swift
private func sourceFile(_ name: String) throws -> String {
    let testFile = URL(fileURLWithPath: #filePath)
    let repositoryRoot = testFile
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = repositoryRoot
        .appendingPathComponent("Sources/CarRentalOptimizer")
        .appendingPathComponent(name)
    return try String(contentsOf: sourceURL, encoding: .utf8)
}
```

- [ ] **Step 2: Run the UI source test to verify it fails**

Run:

```bash
swift test --filter UIEffectsSourceTests/originSuggestionDropdownDistinguishesStationsFromAddresses
```

Expected: test fails because the dropdown still uses `AddressSuggestion` and fixed map-pin rendering.

- [ ] **Step 3: Update SearchPanelView dropdown types and row rendering**

In `SearchPanelView.swift`, change `OriginSuggestionDropdown` to accept unified suggestions:

```swift
private struct OriginSuggestionDropdown: View {
    let isLoading: Bool
    let suggestions: [OriginSuggestion]
    let onSelect: (OriginSuggestion) -> Void
```

Update `suggestionButton(_:)`:

```swift
    private func suggestionButton(_ suggestion: OriginSuggestion) -> some View {
        Button {
            onSelect(suggestion)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: suggestion.kind.systemImage)
                    .foregroundStyle(suggestion.kind == .address ? WorkbenchStyle.accent : WorkbenchStyle.teal)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(suggestion.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(WorkbenchStyle.ink)
                            .lineLimit(1)
                        Text(suggestion.kind.label)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(WorkbenchStyle.muted)
                            .lineLimit(1)
                    }
                    if !suggestion.subtitle.isEmpty {
                        Text(suggestion.subtitle)
                            .font(.caption2)
                            .foregroundStyle(WorkbenchStyle.muted)
                            .lineLimit(1)
                    }
                    if let fallbackNote = suggestion.fallbackNote, !fallbackNote.isEmpty {
                        Text(fallbackNote)
                            .font(.caption2)
                            .foregroundStyle(WorkbenchStyle.warning)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.black.opacity(0.001))
    }
```

No change is needed at the call site if `viewModel.originSuggestions` is already `[OriginSuggestion]`.

- [ ] **Step 4: Run UI source test and location tests**

Run:

```bash
swift test --filter UIEffectsSourceTests/originSuggestionDropdownDistinguishesStationsFromAddresses
swift test --filter LocationInputTests
```

Expected: targeted UI source test and location input suite pass.

- [ ] **Step 5: Commit dropdown rendering**

Run:

```bash
git add Sources/CarRentalOptimizer/SearchPanelView.swift Tests/CarRentalOptimizerTests/UIEffectsSourceTests.swift
git commit -m "Render rail station origin suggestions"
```

Expected: commit succeeds with UI and UI source test staged.

---

### Task 7: Final Verification and Cleanup

**Files:**
- Modify only files needed to fix compilation or test failures found by final verification.

**Interfaces:**
- Consumes: all prior tasks
- Produces: verified city rail-station origin feature

- [ ] **Step 1: Run formatting-sensitive diff checks**

Run:

```bash
git diff --check
```

Expected: no trailing whitespace or patch formatting errors.

- [ ] **Step 2: Run the full test suite**

Run:

```bash
swift test
```

Expected: all test targets pass.

- [ ] **Step 3: Build the app**

Run:

```bash
swift build
```

Expected: app target builds successfully.

- [ ] **Step 4: Manual smoke check**

Run:

```bash
swift run CarRentalOptimizer
```

Expected:
- App launches.
- Typing `德州` in the left origin field shows station-style suggestions before address suggestions.
- Selecting `德州东站` updates the field text to the station display name.
- Starting comparison after selection uses the selected station origin.
- Typing a city and starting comparison without selecting a candidate shows the blocking preflight issue.

- [ ] **Step 5: Commit verification fixes**

If final verification required fixes, commit them:

```bash
git add Sources Tests
git commit -m "Verify rail station origin flow"
```

Expected: commit succeeds only if fixes were needed. If no files changed, skip this commit.

---

## Self-Review Notes

- Spec requirements 1-6 are covered by Tasks 1, 3, and 6.
- Spec requirements 7-8 are covered by Task 4.
- Spec requirements 9-12 are covered by Task 5.
- The MapKit implementation stays dependency-free and is covered by pure helper tests in Task 2.
- The existing platform search and ranking path remains unchanged; selected station coordinates flow through the existing `SearchRequest`.
