import CarRentalDomain
import CoreLocation
import Foundation
import Testing
@testable import CarRentalOptimizer

@Suite("Location input")
@MainActor
struct LocationInputTests {
    @Test("Refreshing current location updates request origin")
    func refreshingCurrentLocationUpdatesRequestOrigin() async {
        let provider = StubCurrentLocationProvider(location: ResolvedLocation(
            label: "北京市朝阳区望京",
            point: GeoPoint(lat: 39.9928, lng: 116.4826)
        ))
        let viewModel = SearchViewModel(
            searchProvider: StubRentalSearchProvider(results: []),
            geocoder: CurrentRequestGeocoder(point: AppDefaults.searchRequest.origin),
            mapService: EstimatedMapService(),
            currentLocationProvider: provider,
            addressSuggestionProvider: StubAddressSuggestionProvider()
        )

        await viewModel.refreshCurrentLocation()

        #expect(viewModel.request.originLabel == "北京市朝阳区望京")
        #expect(viewModel.request.origin == GeoPoint(lat: 39.9928, lng: 116.4826))
        #expect(!viewModel.isLocatingOrigin)
    }

    @Test("CoreLocation unknown errors show retryable location guidance")
    func coreLocationUnknownErrorsShowRetryableLocationGuidance() async {
        let provider = FailingCurrentLocationProvider(error: CLError(.locationUnknown))
        let viewModel = SearchViewModel(
            searchProvider: StubRentalSearchProvider(results: []),
            geocoder: CurrentRequestGeocoder(point: AppDefaults.searchRequest.origin),
            mapService: EstimatedMapService(),
            currentLocationProvider: provider,
            addressSuggestionProvider: StubAddressSuggestionProvider()
        )

        await viewModel.refreshCurrentLocation()

        #expect(viewModel.originStatus == "暂时没有获取到当前位置，可重试定位或手动输入地址。")
        #expect(!viewModel.originStatus.contains("kCLErrorDomain"))
        #expect(!viewModel.isLocatingOrigin)
    }

    @Test("Initial current location refresh retries a temporary cold-start miss")
    func initialCurrentLocationRefreshRetriesTemporaryColdStartMiss() async {
        let provider = FlakyCurrentLocationProvider(results: [
            .failure(CurrentLocationError.unavailable),
            .success(ResolvedLocation(
                label: "北京市通州区京东总部2号楼",
                point: GeoPoint(lat: 39.7784, lng: 116.5629)
            )),
        ])
        let viewModel = SearchViewModel(
            searchProvider: StubRentalSearchProvider(results: []),
            geocoder: CurrentRequestGeocoder(point: AppDefaults.searchRequest.origin),
            mapService: EstimatedMapService(),
            currentLocationProvider: provider,
            addressSuggestionProvider: StubAddressSuggestionProvider(),
            initialLocationRetryDelayNanoseconds: 0
        )

        await viewModel.refreshCurrentLocationIfNeeded()

        #expect(provider.requestCount == 2)
        #expect(viewModel.request.originLabel == "北京市通州区京东总部2号楼")
        #expect(viewModel.request.origin == GeoPoint(lat: 39.7784, lng: 116.5629))
        #expect(viewModel.originStatus == "已定位当前位置。")
    }

    @Test("Current location selection prefers finer horizontal accuracy")
    func currentLocationSelectionPrefersFinerHorizontalAccuracy() {
        let coarse = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 39.9000, longitude: 116.4000),
            altitude: 0,
            horizontalAccuracy: 600,
            verticalAccuracy: 20,
            timestamp: Date()
        )
        let precise = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 39.7784, longitude: 116.5629),
            altitude: 0,
            horizontalAccuracy: 25,
            verticalAccuracy: 20,
            timestamp: Date().addingTimeInterval(-5)
        )

        let selected = bestCurrentLocation(from: [coarse, precise])

        #expect(selected?.coordinate.latitude == precise.coordinate.latitude)
        #expect(selected?.coordinate.longitude == precise.coordinate.longitude)
    }

    @Test("Current location selection ignores invalid horizontal accuracy")
    func currentLocationSelectionIgnoresInvalidHorizontalAccuracy() {
        let invalid = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 39.9000, longitude: 116.4000),
            altitude: 0,
            horizontalAccuracy: -1,
            verticalAccuracy: 20,
            timestamp: Date()
        )

        #expect(bestCurrentLocation(from: [invalid]) == nil)
    }

    @Test("Current location startup wait is capped below five seconds")
    func currentLocationStartupWaitIsCappedBelowFiveSeconds() {
        #expect(currentLocationWaitTimeoutNanoseconds < 5_000_000_000)
    }

    @Test("Current location acceptable accuracy is relaxed for faster startup")
    func currentLocationAcceptableAccuracyIsRelaxedForFasterStartup() {
        #expect(preferredCurrentLocationAccuracyMeters >= 200)
    }

    @Test("Apple location provider coalesces concurrent system requests")
    func appleLocationProviderCoalescesConcurrentSystemRequests() throws {
        let source = try locationServicesSource()

        #expect(source.contains("activeLocationRequest"))
        #expect(source.contains("if let activeLocationRequest"))
    }

    @Test("Apple location timeout waits until authorization has completed")
    func appleLocationTimeoutWaitsUntilAuthorizationHasCompleted() throws {
        let source = try locationServicesSource()
        let requestRange = try #require(source.range(of: "private func requestLocation() async throws -> CLLocation"))
        let requestBlock = String(source[requestRange.lowerBound...].prefix(1_500))

        #expect(!requestBlock.contains("timeoutTask = Task"))
        #expect(source.contains("startUpdatingLocation(with manager: CLLocationManager)"))
        #expect(source.contains("startLocationTimeout()"))
    }

    @Test("Address suggestions update as user edits origin")
    func addressSuggestionsUpdateAsUserEditsOrigin() async {
        let suggestions = [
            AddressSuggestion(id: "1", title: "北京南站", subtitle: "北京市丰台区", point: GeoPoint(lat: 39.8652, lng: 116.3786)),
            AddressSuggestion(id: "2", title: "北京西站", subtitle: "北京市丰台区", point: GeoPoint(lat: 39.8948, lng: 116.3213)),
        ]
        let suggestionProvider = StubAddressSuggestionProvider(suggestions: suggestions)
        let viewModel = SearchViewModel(
            searchProvider: StubRentalSearchProvider(results: []),
            geocoder: CurrentRequestGeocoder(point: AppDefaults.searchRequest.origin),
            mapService: EstimatedMapService(),
            currentLocationProvider: StubCurrentLocationProvider(),
            addressSuggestionProvider: suggestionProvider
        )

        await viewModel.updateOriginInput("北京站")

        #expect(suggestionProvider.queries == ["北京站"])
        #expect(viewModel.originSuggestions == suggestions)
        #expect(viewModel.isOriginSuggestionPanelVisible)

        await viewModel.selectOriginSuggestion(suggestions[0])

        #expect(viewModel.request.originLabel == "北京南站，北京市丰台区")
        #expect(viewModel.request.origin == GeoPoint(lat: 39.8652, lng: 116.3786))
        #expect(viewModel.originSuggestions.isEmpty)
        #expect(!viewModel.isOriginSuggestionPanelVisible)
    }

    @Test("Dismissed origin suggestions stay hidden when stale lookup finishes")
    func dismissedOriginSuggestionsStayHiddenWhenStaleLookupFinishes() async {
        let suggestion = AddressSuggestion(
            id: "1",
            title: "北京南站",
            subtitle: "北京市丰台区",
            point: GeoPoint(lat: 39.8652, lng: 116.3786)
        )
        let suggestionProvider = DelayedAddressSuggestionProvider()
        let viewModel = SearchViewModel(
            searchProvider: StubRentalSearchProvider(results: []),
            geocoder: CurrentRequestGeocoder(point: AppDefaults.searchRequest.origin),
            mapService: EstimatedMapService(),
            currentLocationProvider: StubCurrentLocationProvider(),
            addressSuggestionProvider: suggestionProvider
        )

        let lookupTask = Task {
            await viewModel.updateOriginInput("北京站")
        }
        while suggestionProvider.continuation == nil {
            await Task.yield()
        }

        viewModel.dismissOriginSuggestions()
        suggestionProvider.resume(with: [suggestion])
        await lookupTask.value

        #expect(viewModel.originSuggestions.isEmpty)
        #expect(!viewModel.isLoadingOriginSuggestions)
        #expect(!viewModel.isOriginSuggestionPanelVisible)
    }

    @Test("English Apple location output is normalized to Chinese display text")
    func englishAppleLocationOutputIsNormalizedToChineseDisplayText() async {
        let englishSuggestion = AddressSuggestion(
            id: "jd-hq",
            title: "Jingdong Group Quanqiu Headquarters Beijing No.2Park",
            subtitle: "Beijing Tongzhou Beijing Economic and Technological Development Zone",
            point: GeoPoint(lat: 39.7784, lng: 116.5629)
        )
        let viewModel = SearchViewModel(
            searchProvider: StubRentalSearchProvider(results: []),
            geocoder: CurrentRequestGeocoder(point: AppDefaults.searchRequest.origin),
            mapService: EstimatedMapService(),
            currentLocationProvider: StubCurrentLocationProvider(),
            addressSuggestionProvider: StubAddressSuggestionProvider(suggestions: [englishSuggestion])
        )

        await viewModel.updateOriginInput("京东总部")
        await viewModel.selectOriginSuggestion(englishSuggestion)

        #expect(viewModel.request.originLabel == "京东集团全球总部2号园区，北京通州 北京经济技术开发区")
    }

    @Test("Blank origin input clears suggestions")
    func blankOriginInputClearsSuggestions() async {
        let suggestionProvider = StubAddressSuggestionProvider(suggestions: [
            AddressSuggestion(id: "1", title: "北京南站", subtitle: "北京市丰台区", point: GeoPoint(lat: 39.8652, lng: 116.3786)),
        ])
        let viewModel = SearchViewModel(
            searchProvider: StubRentalSearchProvider(results: []),
            geocoder: CurrentRequestGeocoder(point: AppDefaults.searchRequest.origin),
            mapService: EstimatedMapService(),
            currentLocationProvider: StubCurrentLocationProvider(),
            addressSuggestionProvider: suggestionProvider
        )

        await viewModel.updateOriginInput("")

        #expect(viewModel.originSuggestions.isEmpty)
        #expect(suggestionProvider.queries.isEmpty)
    }

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
}

private struct FailingCurrentLocationProvider: CurrentLocationProviding {
    let error: Error

    func currentLocation() async throws -> ResolvedLocation {
        throw error
    }
}

private struct StubCurrentLocationProvider: CurrentLocationProviding {
    var location: ResolvedLocation?

    func currentLocation() async throws -> ResolvedLocation {
        guard let location else {
            throw CurrentLocationError.unavailable
        }
        return location
    }
}

private func locationServicesSource() throws -> String {
    let testFile = URL(fileURLWithPath: #filePath)
    let repositoryRoot = testFile
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = repositoryRoot
        .appendingPathComponent("Sources/CarRentalOptimizer/LocationServices.swift")
    return try String(contentsOf: sourceURL, encoding: .utf8)
}

@MainActor
private final class FlakyCurrentLocationProvider: CurrentLocationProviding {
    private var results: [Result<ResolvedLocation, Error>]
    private(set) var requestCount = 0

    init(results: [Result<ResolvedLocation, Error>]) {
        self.results = results
    }

    func currentLocation() async throws -> ResolvedLocation {
        requestCount += 1
        guard !results.isEmpty else {
            throw CurrentLocationError.unavailable
        }
        return try results.removeFirst().get()
    }
}

@MainActor
private final class StubAddressSuggestionProvider: AddressSuggestionProviding {
    let suggestions: [AddressSuggestion]
    private(set) var queries: [String] = []

    init(suggestions: [AddressSuggestion] = []) {
        self.suggestions = suggestions
    }

    func suggestions(for query: String, near origin: GeoPoint?) async throws -> [AddressSuggestion] {
        queries.append(query)
        return suggestions
    }
}

private struct StubRentalSearchProvider: RentalSearchProviding {
    let results: [PlatformEvidenceResult]

    func search(request: SearchRequest) async -> [PlatformEvidenceResult] {
        results
    }
}

@MainActor
private final class DelayedAddressSuggestionProvider: AddressSuggestionProviding {
    private(set) var continuation: CheckedContinuation<[AddressSuggestion], Error>?

    func suggestions(for query: String, near origin: GeoPoint?) async throws -> [AddressSuggestion] {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume(with suggestions: [AddressSuggestion]) {
        continuation?.resume(returning: suggestions)
        continuation = nil
    }
}
