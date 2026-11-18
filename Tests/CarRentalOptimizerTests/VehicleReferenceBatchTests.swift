import CarRentalDomain
import Foundation
import Testing
@testable import CarRentalOptimizer

@Suite("Batch vehicle reference enrichment") @MainActor
struct VehicleReferenceBatchTests {
    @Test func deduplicatesSeriesAndSkipsCompleteCache() async {
        let service = BatchReferenceStub()
        service.cached.insert("大众朗逸")
        let loader = VehicleReferenceBatchLoader(service: service)
        loader.start(listings: [listing("大众朗逸"), listing("2022大众 朗逸"), listing("北京BJ40")])
        await loader.waitUntilFinished()
        #expect(loader.totalCount == 2)
        #expect(loader.completeCount == 2)
        #expect(service.requested == ["北京bj40"])
        #expect(!loader.isLoading)
    }

    @Test func processesAllVehiclesWithBoundedConcurrencyAndRetriesOnlyMissing() async {
        let service = BatchReferenceStub()
        let loader = VehicleReferenceBatchLoader(service: service)
        let items = ["车型A", "车型B", "车型C", "missing", "车型D"].map(listing)
        loader.start(listings: items)
        await loader.waitUntilFinished()
        #expect(loader.processedCount == 5)
        #expect(loader.completeCount == 4)
        #expect(loader.missingCount == 1)
        #expect(service.maximumActive <= 2)
        service.resolveMissing = true
        loader.start(listings: items, forceMissing: true)
        await loader.waitUntilFinished()
        #expect(service.forced == ["missing"])
        #expect(loader.completeCount == 5)
    }

    @Test func newlyFetchedSelectedReferenceUpdatesTheBatchSummary() async {
        let service = BatchReferenceStub()
        let loader = VehicleReferenceBatchLoader(service: service)
        let item = listing("missing")
        loader.start(listings: [item])
        await loader.waitUntilFinished()
        #expect(loader.missingCount == 1)
        service.resolveMissing = true
        let refreshed = await service.refreshInsight(for: item)
        loader.acceptReference(refreshed, for: item)
        #expect(loader.completeCount == 1)
        #expect(loader.missingCount == 0)
        #expect(loader.reference(for: item).specSheet.hasCompleteDimensions)
    }

    @Test func cancelledBatchCannotOverwriteNewSearchProgress() async {
        let service = BatchReferenceStub()
        let loader = VehicleReferenceBatchLoader(service: service)
        var updates: [String] = []
        loader.onUpdate = { key, _ in updates.append(key) }
        loader.start(listings: [listing("旧车系")])
        var started = service.started.makeAsyncIterator()
        _ = await started.next()
        loader.start(listings: [listing("新车系")])
        await loader.waitUntilFinished()
        #expect(loader.totalCount == 1)
        #expect(loader.completeCount == 1)
        #expect(!updates.contains("旧车系"))
        #expect(updates.contains("新车系"))
    }

    private func listing(_ name: String) -> RentalListing {
        RentalListing(id: name, platform: .carInc, store: Store(id: "s", platform: .carInc, name: "test", city: "北京", address: "北京", location: GeoPoint(lat: 40, lng: 116), distanceKm: 1, hours: "08-20"), vehicleName: name, vehicleClass: "SUV 5座", basePrice: 100, platformFees: 0, insuranceFees: 0, oneWayFee: 0, sourceUrl: "https://www.zuche.com/", dataCompleteness: 1)
    }
}

@MainActor private final class BatchReferenceStub: VehicleInsightProviding {
    var cached = Set<String>()
    var requested: [String] = []
    var forced: [String] = []
    var resolveMissing = false
    var active = 0
    var maximumActive = 0
    let started: AsyncStream<String>
    private let signal: AsyncStream<String>.Continuation

    init() {
        let pair = AsyncStream<String>.makeStream()
        started = pair.stream
        signal = pair.continuation
    }

    func localInsight(for listing: RentalListing) -> VehicleInsight {
        let key = VehicleInsightStore.normalizedCacheKey(listing.vehicleName)
        var value = reference(listing, complete: cached.contains(key))
        if cached.contains(key) { value.cacheState = .cached }
        return value
    }

    func insight(for listing: RentalListing) async -> VehicleInsight {
        let key = VehicleInsightStore.normalizedCacheKey(listing.vehicleName)
        requested.append(key)
        active += 1
        maximumActive = max(maximumActive, active)
        signal.yield(key)
        try? await Task.sleep(nanoseconds: 20_000_000)
        active -= 1
        let complete = key != "missing" || resolveMissing
        if complete { cached.insert(key) }
        return reference(listing, complete: complete)
    }

    func refreshInsight(for listing: RentalListing) async -> VehicleInsight {
        forced.append(VehicleInsightStore.normalizedCacheKey(listing.vehicleName))
        return await insight(for: listing)
    }

    private func reference(_ listing: RentalListing, complete: Bool) -> VehicleInsight {
        var value = VehicleInsightLocalInferencer.localInsight(for: listing)
        if complete {
            value.origin = .network
            value.specSheet.lengthMm = VehicleSpecValue(value: 4500, sourceName: "test", sourceURL: nil, confidence: .medium, appliesTo: .series)
            value.specSheet.widthMm = VehicleSpecValue(value: 1800, sourceName: "test", sourceURL: nil, confidence: .medium, appliesTo: .series)
            value.specSheet.heightMm = VehicleSpecValue(value: 1600, sourceName: "test", sourceURL: nil, confidence: .medium, appliesTo: .series)
            value.specSheet.wheelbaseMm = VehicleSpecValue(value: 2700, sourceName: "test", sourceURL: nil, confidence: .medium, appliesTo: .series)
        }
        return value
    }
}
