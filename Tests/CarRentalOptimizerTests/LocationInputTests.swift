import CarRentalDomain
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
