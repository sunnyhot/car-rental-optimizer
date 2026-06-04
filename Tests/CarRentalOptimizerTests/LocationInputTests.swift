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

        await viewModel.selectOriginSuggestion(suggestions[0])

        #expect(viewModel.request.originLabel == "北京南站，北京市丰台区")
        #expect(viewModel.request.origin == GeoPoint(lat: 39.8652, lng: 116.3786))
        #expect(viewModel.originSuggestions.isEmpty)
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
