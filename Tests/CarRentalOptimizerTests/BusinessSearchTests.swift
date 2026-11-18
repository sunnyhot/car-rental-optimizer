import CarRentalDomain
import Foundation
import Testing
@testable import CarRentalOptimizer

@Suite("Business search correctness") @MainActor
struct BusinessSearchTests {
    @Test func preserveExplicitPickupAndReturnMinutes() {
        let model = SearchViewModel()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = AppDateRules.calendar.timeZone
        let pickup = Date().addingTimeInterval(10 * 86400 + 1234)
        let end = pickup.addingTimeInterval(27 * 3600)
        model.applyDates(pickup: pickup, returnDate: end)
        #expect(model.request.pickupAt == formatter.string(from: pickup))
        #expect(model.request.returnAt == formatter.string(from: end))
    }

    @Test func unknownFeesNeverShowZeroOrPriceAdvantage() {
        let partial = makeComparisonRecommendation(id: "partial", vehicleName: "A", rentalTotal: 100, bestTotal: 110, distanceKm: 1, dataCompleteness: 0.7)
        let complete = makeComparisonRecommendation(id: "complete", vehicleName: "A", rentalTotal: 200, bestTotal: 210, distanceKm: 1, dataCompleteness: 1)
        let rows = ComparisonPresentation.sections(candidates: [partial, complete], insightStates: [:], onlyDifferences: false).flatMap(\.rows)
        #expect(rows.first { $0.id == "best-total" }?.cells.first?.tone != .advantage)
        #expect(rows.first { $0.id == "insurance-fees" }?.cells.first?.text == "未确认/未单列")
    }

    @Test func legacySnapshotIsReadableButNotComparable() throws {
        let json = #"{"id":"old","monitorID":"m","checkedAt":0,"status":"successful","warnings":[],"message":"legacy"}"#
        let snapshot = try JSONDecoder().decode(PriceSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.listingSignature == nil)
        #expect(snapshot.priceIsComplete == nil)
        #expect(comparableMonitorSnapshots([snapshot]).isEmpty)
    }

    @Test func trendDoesNotJoinDifferentStoresOrIncompletePrices() {
        let a = ListingSignature(platform: .ehi, storeID: "a", normalizedStoreName: "a", normalizedVehicleName: "car", normalizedVehicleClass: "suv")
        let b = ListingSignature(platform: .ehi, storeID: "b", normalizedStoreName: "b", normalizedVehicleName: "car", normalizedVehicleClass: "suv")
        func snapshot(_ id: String, _ signature: ListingSignature, _ complete: Bool) -> PriceSnapshot {
            PriceSnapshot(id: id, monitorID: "m", checkedAt: Date(), status: .successful, platformRentalPrice: 100, listingSignature: signature, priceIsComplete: complete, message: "quote")
        }
        #expect(comparableMonitorSnapshots([snapshot("a", a, true), snapshot("b", b, true)]).map(\.id) == ["b"])
        #expect(comparableMonitorSnapshots([snapshot("a", a, true), snapshot("partial", a, false)]).isEmpty)
    }

    @Test func rejectPastEqualAndDateOnlyTimesWithFixedClock() {
        let now = parseRentalDate("2026-11-16 10:00")!
        var request = AppDefaults.searchRequest
        request.pickupAt = "2026-11-16 09:59"
        request.returnAt = "2026-11-17 10:00"
        #expect(validateSearchPreflight(request, now: now).hasBlockingIssue)
        request.pickupAt = "2026-11-17 10:00"
        #expect(validateSearchPreflight(request, now: now).hasBlockingIssue)
        request.pickupAt = "2026-11-16"
        #expect(validateSearchPreflight(request, now: now).hasBlockingIssue)
        request.pickupAt = "2026-11-16 10:01"
        #expect(!validateSearchPreflight(request, now: now).hasBlockingIssue)
    }

    @Test func rejectUnsupportedReturnAndReversedTimes() {
        var request = AppDefaults.searchRequest
        request.returnMode = .differentStore
        #expect(validateSearchPreflight(request).hasBlockingIssue)
        request.returnMode = .sameStore
        request.pickupAt = "2099-09-01 18:00"
        request.returnAt = "2099-09-01 10:00"
        #expect(validateSearchPreflight(request).hasBlockingIssue)
    }
}
