import CarRentalDomain
import Foundation
import Testing
@testable import CarRentalOptimizer

@Suite("Opt-in live vehicle reference validation") @MainActor
struct VehicleReferenceLiveTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CAR_RENTAL_LIVE_SPECS"] == "1"))
    func fetchPersistAndReuseOffline() async throws {
        let environment = ProcessInfo.processInfo.environment
        let name = environment["CAR_RENTAL_SPEC_NAME"] ?? "北京BJ40"
        let fileURL = environment["CAR_RENTAL_REFERENCE_CACHE_PATH"].map { URL(fileURLWithPath: $0) } ?? (environment["CAR_RENTAL_PRIME_SPECS"] == "1"
            ? VehicleInsightStore.defaultFileURL
            : FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json"))
        let listing = RentalListing(id: "reference-probe", platform: .carInc, store: Store(id: "reference", platform: .carInc, name: "参数验证", city: "", address: "", location: GeoPoint(lat: 0, lng: 0), distanceKm: 0, hours: ""), vehicleName: name, vehicleClass: "", basePrice: 0, platformFees: 0, insuranceFees: 0, oneWayFee: 0, sourceUrl: "https://www.zuche.com/", dataCompleteness: 0)
        let service = VehicleInsightService(store: VehicleInsightStore(fileURL: fileURL))
        let result = await service.insight(for: listing)
        #expect(result.specSheet.hasCompleteDimensions)
        print("LIVE_SPECS \(name) length=\(result.specSheet.lengthMm?.value ?? 0) width=\(result.specSheet.widthMm?.value ?? 0) height=\(result.specSheet.heightMm?.value ?? 0) wheelbase=\(result.specSheet.wheelbaseMm?.value ?? 0) source=\(result.sourceURL ?? "none")")
        let offline = VehicleInsightService(store: VehicleInsightStore(fileURL: fileURL), networkProvider: VehicleInsightNetworkProvider(httpClient: NoVehicleReferenceNetwork()))
        #expect(offline.localInsight(for: listing).specSheet.lengthMm == result.specSheet.lengthMm)
        #expect(await offline.insight(for: listing).specSheet.wheelbaseMm == result.specSheet.wheelbaseMm)
    }
}

private struct NoVehicleReferenceNetwork: VehicleInsightHTTPClient {
    func data(from url: URL) async throws -> (Data, URLResponse) {
        Issue.record("Complete persisted dimensions should not require a network call")
        throw URLError(.notConnectedToInternet)
    }
}
