import CarRentalDomain
import Foundation
import Testing
@testable import CarRentalOptimizer

@Suite("Current-location-only search") @MainActor
struct CurrentLocationOnlyTests {
    @Test func successfulLocationSuppliesTheActualSearchOrigin() async {
        let search = LocationSearchRecorder()
        let provider = SequenceLocationProvider([.success(location)])
        let model = makeModel(search: search, provider: provider)
        await model.refreshCurrentLocation()
        await model.runSearch()
        #expect(model.isCurrentLocationReady)
        #expect(search.requests.count == 1)
        #expect(search.requests.first?.origin == location.point)
        #expect(search.requests.first?.originLabel == location.label)
    }

    @Test func failedRefreshCannotFallBackToDefaultOrPreviousLocation() async {
        let search = LocationSearchRecorder()
        let provider = SequenceLocationProvider([.success(location), .failure(CurrentLocationError.denied)])
        let model = makeModel(search: search, provider: provider)
        await model.refreshCurrentLocation()
        await model.runSearch()
        await model.refreshCurrentLocation()
        await model.runSearch()
        #expect(search.requests.count == 1)
        #expect(!model.isCurrentLocationReady)
        #expect(model.request.originLabel.isEmpty)
        #expect(model.hasBlockingPreflightIssues)
        #expect(!model.originStatus.contains("输入地址"))
    }

    @Test func manualAddressChangesAreIgnoredInCurrentLocationMode() async {
        let search = LocationSearchRecorder()
        let model = makeModel(search: search, provider: SequenceLocationProvider([.success(location)]))
        await model.refreshCurrentLocation()
        await model.updateOriginInput("上海虹桥")
        #expect(model.request.originLabel == location.label)
        #expect(model.request.origin == location.point)
    }

    @Test func invalidCoordinatesNeverReachRentalPlatforms() async {
        let search = LocationSearchRecorder()
        let bad = ResolvedLocation(label: "无效位置", point: GeoPoint(lat: 999, lng: 116))
        let model = makeModel(search: search, provider: SequenceLocationProvider([.success(bad)]))
        await model.refreshCurrentLocation()
        await model.runSearch()
        #expect(search.requests.isEmpty)
        #expect(!model.isCurrentLocationReady)
    }

    @Test func inFlightLocationCannotStartAPISearch() async {
        let search = LocationSearchRecorder()
        let provider = DeferredLocationProvider()
        let model = SearchViewModel(searchProvider: search, geocoder: RejectManualGeocoding(), mapService: EstimatedMapService(), currentLocationProvider: provider, requiresCurrentLocation: true)
        let locating = Task { await model.refreshCurrentLocation() }
        var started = provider.started.makeAsyncIterator()
        _ = await started.next()
        await model.runSearch()
        #expect(model.isLocatingOrigin)
        #expect(model.hasBlockingPreflightIssues)
        #expect(search.requests.isEmpty)
        provider.finish(with: location)
        await locating.value
        await model.runSearch()
        #expect(search.requests.count == 1)
        #expect(search.requests.first?.origin == location.point)
    }

    @Test func changedCoordinatesWithoutANewSystemFixAreRejected() async {
        let search = LocationSearchRecorder()
        let model = makeModel(search: search, provider: SequenceLocationProvider([.success(location)]))
        await model.refreshCurrentLocation()
        model.request.origin = GeoPoint(lat: 31.2, lng: 121.5)
        await model.runSearch()
        #expect(!model.isCurrentLocationReady)
        #expect(search.requests.isEmpty)
    }

    private var location: ResolvedLocation { ResolvedLocation(label: "系统定位地点", point: GeoPoint(lat: 39.8, lng: 116.5)) }
    private func makeModel(search: LocationSearchRecorder, provider: SequenceLocationProvider) -> SearchViewModel {
        SearchViewModel(searchProvider: search, geocoder: RejectManualGeocoding(), mapService: EstimatedMapService(), currentLocationProvider: provider, requiresCurrentLocation: true)
    }

    @Test func liveSearchStartsWithoutAnAssumedDefaultAddress() {
        let model = SearchViewModel()
        model.refreshPreflightIssues()
        #expect(model.request.originLabel.isEmpty)
        #expect(model.hasBlockingPreflightIssues)
    }
}

@MainActor private final class LocationSearchRecorder: RentalSearchProviding {
    var requests: [SearchRequest] = []
    func search(request: SearchRequest) async -> [PlatformEvidenceResult] { requests.append(request); return [] }
}

@MainActor private final class SequenceLocationProvider: CurrentLocationProviding {
    var results: [Result<ResolvedLocation, Error>]
    init(_ results: [Result<ResolvedLocation, Error>]) { self.results = results }
    func currentLocation() async throws -> ResolvedLocation {
        guard !results.isEmpty else { throw CurrentLocationError.unavailable }
        return try results.removeFirst().get()
    }
}

@MainActor private final class DeferredLocationProvider: CurrentLocationProviding {
    let started: AsyncStream<Void>
    private let signal: AsyncStream<Void>.Continuation
    private var pending: CheckedContinuation<ResolvedLocation, Error>?

    init() {
        let pair = AsyncStream<Void>.makeStream()
        started = pair.stream
        signal = pair.continuation
    }

    func currentLocation() async throws -> ResolvedLocation {
        try await withCheckedThrowingContinuation { continuation in
            pending = continuation
            signal.yield(())
            signal.finish()
        }
    }

    func finish(with location: ResolvedLocation) {
        pending?.resume(returning: location)
        pending = nil
    }
}

private struct RejectManualGeocoding: AddressGeocoding {
    func geocode(_ address: String) async throws -> GeoPoint { throw AddressGeocodingError.notFound }
}
