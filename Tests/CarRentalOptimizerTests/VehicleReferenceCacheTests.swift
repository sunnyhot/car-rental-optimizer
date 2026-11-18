import CarRentalDomain
import Foundation
import Testing
@testable import CarRentalOptimizer

@Suite("Durable vehicle reference cache") @MainActor
struct VehicleReferenceCacheTests {
    @Test func oldDimensionsRemainImmediatelyAvailableOffline() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let store = VehicleInsightStore(fileURL: url)
        let saved = Date(timeIntervalSince1970: 100)
        store.save(reference(length: 4790), forKey: "北京BJ40", now: saved)
        let service = VehicleInsightService(store: VehicleInsightStore(fileURL: url), networkProvider: VehicleInsightNetworkProvider(httpClient: OfflineSpecsClient()), now: { saved.addingTimeInterval(400 * 86400) })
        #expect(service.localInsight(for: listing).specSheet.lengthMm?.value == 4790)
        #expect(await service.insight(for: listing).specSheet.wheelbaseMm?.value == 2760)
    }

    @Test func weakerRefreshCannotEraseKnownDimensions() {
        let store = VehicleInsightStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json"))
        store.save(reference(length: 4790), forKey: "北京BJ40")
        store.save(reference(length: nil), forKey: "北京BJ40")
        #expect(store.cachedInsight(forKey: "北京BJ40")?.specSheet.lengthMm?.value == 4790)
    }

    @Test func cacheRetainsReferenceFeaturesButNotAnotherRentalConfiguration() {
        let store = VehicleInsightStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json"))
        var cached = reference(length: 4790)
        cached.specSheet.features = [VehicleFeature(name: "倒车影像", sourceName: "车型库", confidence: .medium, appliesTo: .series), VehicleFeature(name: "蓝牙", sourceName: "旧平台", confidence: .high, appliesTo: .platformListing)]
        cached.specSheet.batteryKWh = VehicleSpecValue(value: 80, sourceName: "旧平台", sourceURL: nil, confidence: .high, appliesTo: .platformListing)
        store.save(cached, forKey: "北京BJ40")
        let service = VehicleInsightService(store: store, networkProvider: VehicleInsightNetworkProvider(httpClient: OfflineSpecsClient()))
        let current = service.localInsight(for: listing)
        #expect(current.specSheet.features.contains { $0.name == "倒车影像" })
        #expect(!current.specSheet.features.contains { $0.name == "蓝牙" })
        #expect(current.specSheet.batteryKWh == nil)
    }

    private var listing: RentalListing {
        RentalListing(id: "l", platform: .carInc, store: Store(id: "s", platform: .carInc, name: "test", city: "北京", address: "北京", location: GeoPoint(lat: 40, lng: 116), distanceKm: 1, hours: "08-20"), vehicleName: "北京BJ40", vehicleClass: "SUV 5座", basePrice: 100, platformFees: 0, insuranceFees: 0, oneWayFee: 0, sourceUrl: "https://www.zuche.com/", dataCompleteness: 1)
    }

    private func reference(length: Int?) -> VehicleInsight {
        var value = VehicleInsightLocalInferencer.localInsight(for: listing)
        value.origin = .network
        value.sourceName = "车型库"
        if let length {
            value.specSheet.lengthMm = VehicleSpecValue(value: length, sourceName: "车型库", sourceURL: nil, confidence: .medium, appliesTo: .series)
            value.specSheet.wheelbaseMm = VehicleSpecValue(value: 2760, sourceName: "车型库", sourceURL: nil, confidence: .medium, appliesTo: .series)
        }
        return value
    }
}

private struct OfflineSpecsClient: VehicleInsightHTTPClient {
    func data(from url: URL) async throws -> (Data, URLResponse) { throw URLError(.notConnectedToInternet) }
}
