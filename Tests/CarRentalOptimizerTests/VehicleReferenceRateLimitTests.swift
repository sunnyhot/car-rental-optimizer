import CarRentalDomain
import Foundation
import Testing
@testable import CarRentalOptimizer

@Suite("Vehicle reference rate limits")
struct VehicleReferenceRateLimitTests {
    @Test func retryAfterSecondsAreRespected() {
        let now = Date(timeIntervalSince1970: 100)
        #expect(vehicleReferenceRetryDate("120", now: now) == now.addingTimeInterval(120))
        #expect(vehicleReferenceRetryDate(nil, now: now) == now.addingTimeInterval(60))
    }

    @Test func cooldownPreventsAdditionalNetworkPermits() async throws {
        let pacer = VehicleReferenceRequestPacer(minimumInterval: 0)
        let retry = Date().addingTimeInterval(60)
        await pacer.registerRateLimit(until: retry)
        do { try await pacer.waitForPermit(); Issue.record("Cooldown must reject the next request") }
        catch let error as VehicleReferenceRateLimitError { #expect(error.retryAfter == retry) }
        catch { Issue.record("Unexpected error: \(error)") }
    }

    @Test @MainActor func limitedLookupIsDeferredNotMissingData() async {
        let store = VehicleInsightStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json"))
        let deadline = Date().addingTimeInterval(60)
        let service = VehicleInsightService(store: store, networkProvider: VehicleInsightNetworkProvider(httpClient: LimitedReferenceClient(deadline: deadline)))
        let loader = VehicleReferenceBatchLoader(service: service)
        let listing = RentalListing(id: "l", platform: .carInc, store: Store(id: "s", platform: .carInc, name: "test", city: "北京", address: "北京", location: GeoPoint(lat: 40, lng: 116), distanceKm: 1, hours: "08-20"), vehicleName: "北京BJ40", vehicleClass: "SUV", basePrice: 100, platformFees: 0, insuranceFees: 0, oneWayFee: 0, sourceUrl: "https://www.zuche.com/", dataCompleteness: 1)
        loader.start(listings: [listing])
        await loader.waitUntilFinished()
        #expect(loader.deferredCount == 1)
        #expect(loader.missingCount == 0)
        #expect(loader.retryAfter == deadline)
        #expect(loader.needsMoreData)
    }
}

private struct LimitedReferenceClient: VehicleInsightHTTPClient {
    let deadline: Date
    func data(from url: URL) async throws -> (Data, URLResponse) { throw VehicleReferenceRateLimitError(retryAfter: deadline) }
    func retryAfterDate() async -> Date? { deadline }
}
