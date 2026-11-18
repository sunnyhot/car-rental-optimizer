import CarRentalDomain
import Foundation
import Testing
@testable import CarRentalOptimizer

@Suite("Opt-in live search diagnostics") @MainActor
struct LiveSearchDiagnosticsTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CAR_RENTAL_LIVE_PROBE"] == "1"))
    func reproduceReportedEmptySearch() async throws {
        let environment = ProcessInfo.processInfo.environment
        let label = try #require(environment["CAR_RENTAL_PROBE_ORIGIN"])
        let pickup = try #require(environment["CAR_RENTAL_PROBE_PICKUP"])
        let returnTime = try #require(environment["CAR_RENTAL_PROBE_RETURN"])
        let origin = try await AppleAddressGeocoder().geocode(label)
        let request = SearchRequest(origin: origin, originLabel: label, pickupAt: pickup, returnAt: returnTime, returnMode: .sameStore, radiusKm: 100, vehicleQuery: "", platforms: [.carInc, .ehi])
        let results = await LiveRentalSearchService().search(request: request)
        for result in results {
            print("LIVE_RESULT \(result.platform) \(result.status.kind) count=\(result.listings.count) \(result.status.message)")
            for item in result.listings.prefix(2) { print("LIVE_LISTING \(item.store.name) \(item.vehicleName)") }
        }
        #expect(results.contains { !$0.listings.isEmpty })
        let referenceService: VehicleInsightProviding
        if environment["CAR_RENTAL_LIVE_BATCH"] == "1" {
            let path = try #require(environment["CAR_RENTAL_REFERENCE_CACHE_PATH"])
            referenceService = VehicleInsightService(store: VehicleInsightStore(fileURL: URL(fileURLWithPath: path)), networkProvider: VehicleInsightNetworkProvider(httpClient: ProbeReferenceHTTPClient()))
        } else { referenceService = LocalOnlyVehicleInsightService() }
        let suggestions = VehicleSuggestionStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("live-probe-suggestions-\(UUID().uuidString).json"))
        let model = SearchViewModel(searchProvider: DiagnosticResultReplay(results: results), geocoder: CurrentRequestGeocoder(point: origin), mapService: EstimatedMapService(), vehicleSuggestionStore: suggestions, vehicleInsightService: referenceService)
        model.request = request
        await model.runSearch()
        await model.vehicleReferences.waitUntilFinished()
        if environment["CAR_RENTAL_LIVE_BATCH"] == "1" {
            let loader = model.vehicleReferences
            print("LIVE_REFERENCE_BATCH total=\(loader.totalCount) processed=\(loader.processedCount) complete=\(loader.completeCount) partial=\(loader.partialCount) missing=\(loader.missingCount) deferred=\(loader.deferredCount)")
            print("LIVE_REFERENCE_MISSING \(loader.states.filter { $0.value == .unavailable }.keys.sorted())")
            #expect(loader.totalCount > 0)
            #expect(loader.processedCount == loader.totalCount)
            #expect(loader.completeCount > 0)
        }
        for result in results {
            let confirmedCount = result.listings.filter { $0.confirmedQuote?.isValid == true }.count
            print("LIVE_DISPLAY \(result.platform) confirmed=\(confirmedCount) status=\(model.platformStatus(for: result.platform).kind)")
            if confirmedCount > 0 && result.status.kind == .ready {
                #expect(model.platformStatus(for: result.platform).kind == .ready)
            }
        }
    }
}

private struct DiagnosticResultReplay: RentalSearchProviding {
    let results: [PlatformEvidenceResult]
    func search(request: SearchRequest) async -> [PlatformEvidenceResult] { results }
}


private struct ProbeReferenceHTTPClient: VehicleInsightHTTPClient {
    private let client = URLSessionVehicleInsightHTTPClient()
    func retryAfterDate() async -> Date? { await client.retryAfterDate() }
    func data(from url: URL) async throws -> (Data, URLResponse) {
        do {
            let result = try await client.data(from: url)
            if ProcessInfo.processInfo.environment["CAR_RENTAL_LOG_SPECS"] == "1" {
                let status = (result.1 as? HTTPURLResponse)?.statusCode ?? 0
                print("SPEC_HTTP \(status) bytes=\(result.0.count) \(url.absoluteString)")
                if url.host == "portal.auto.sohu.com" { print("SPEC_LOOKUP \(String(data: result.0.prefix(180), encoding: .utf8) ?? "binary")") }
            }
            return result
        } catch {
            if ProcessInfo.processInfo.environment["CAR_RENTAL_LOG_SPECS"] == "1" { print("SPEC_ERROR \(url.absoluteString) \(error)") }
            throw error
        }
    }
}
