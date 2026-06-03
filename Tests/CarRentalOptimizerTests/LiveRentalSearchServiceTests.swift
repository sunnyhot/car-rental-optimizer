import CarRentalDomain
import Foundation
import JavaScriptCore
import Testing
@testable import CarRentalOptimizer

@Suite("Live rental search service")
struct LiveRentalSearchServiceTests {
    @Test("Date-only pickup today uses a future platform time and keeps return hour aligned")
    func dateOnlyPickupTodayUsesFuturePlatformTime() {
        let now = date("2026-06-03 15:45")

        let range = platformQueryTimeRange(
            pickupDate: "2026-06-03",
            returnDate: "2026-06-04",
            now: now
        )

        #expect(range.pickupTime == "2026-06-03 18:00")
        #expect(range.returnTime == "2026-06-04 18:00")
    }

    @Test("Future date-only pickup keeps the standard platform hour")
    func futureDateOnlyPickupKeepsStandardPlatformHour() {
        let now = date("2026-06-03 15:45")

        let range = platformQueryTimeRange(
            pickupDate: "2026-06-05",
            returnDate: "2026-06-06",
            now: now
        )

        #expect(range.pickupTime == "2026-06-05 10:00")
        #expect(range.returnTime == "2026-06-06 10:00")
    }

    @Test("Explicit platform times are preserved")
    func explicitPlatformTimesArePreserved() {
        let now = date("2026-06-03 15:45")

        let range = platformQueryTimeRange(
            pickupDate: "2026-06-03 19:30",
            returnDate: "2026-06-04 20:30",
            now: now
        )

        #expect(range.pickupTime == "2026-06-03 19:30")
        #expect(range.returnTime == "2026-06-04 20:30")
    }

    @Test("eHi bridge decodes obfuscated price digits used by official stock API")
    func ehiBridgeDecodesObfuscatedPriceDigits() {
        let script = makeEhiSearchScript(json: "{}")

        #expect(script.contains("charCodeAt(0)"))
        #expect(script.contains("57345"))
        #expect(script.contains("57354"))
        #expect(script.contains("code - 57345"))
    }

    @Test("eHi obfuscated price digits convert to usable numeric prices")
    func ehiObfuscatedPriceDigitsConvertToUsableNumericPrices() throws {
        let context = try #require(JSContext())
        let decodedPrice = context.evaluateScript(
            """
            const decodeObfuscatedDigits = (value) => String(value).split('').map(ch => {
              const code = ch.charCodeAt(0);
              return code >= 57345 && code <= 57354 ? String(code - 57345) : ch;
            }).join('');
            const num = (value) => {
              if (value === null || value === undefined || value === '') return null;
              const n = Number(decodeObfuscatedDigits(value).replace(/[^0-9.]/g, ''));
              return Number.isFinite(n) ? n : null;
            };
            num('\u{E002}\u{E003}\u{E004}.5');
            """
        )

        #expect(decodedPrice?.toDouble() == 123.5)
    }

    @Test("eHi blank vehicle query probes nearby stores until one has priced listings")
    func ehiBlankVehicleQueryProbesNearbyStoresUntilPriced() {
        let script = makeEhiSearchScript(json: "{}")

        #expect(script.contains("nearestStoreProbeLimit = 12"))
        #expect(script.contains("storeCandidates.slice(0, nearestStoreProbeLimit)"))
        #expect(script.contains("listingsBeforeStore"))
        #expect(script.contains("!hasVehicleQuery && Object.keys(listingsByKey).length > listingsBeforeStore"))
        #expect(!script.contains("storeCandidates.slice(0, 1)"))
    }

    @Test("Blank vehicle query uses nearest store with available listings")
    func blankVehicleQueryUsesNearestStoreWithAvailableListings() {
        let emptyNearest = StoreListingsBatch(distanceKm: 1.2, listings: [])
        let availableSecond = StoreListingsBatch(
            distanceKm: 1.8,
            listings: [
                makeListing(id: "second-lavida", storeId: "second", distanceKm: 1.8),
                makeListing(id: "second-kruze", storeId: "second", distanceKm: 1.8),
            ]
        )
        let fartherAvailable = StoreListingsBatch(
            distanceKm: 3.4,
            listings: [
                makeListing(id: "farther-camry", storeId: "farther", distanceKm: 3.4),
            ]
        )

        let selected = nearestAvailableStoreListings(from: [fartherAvailable, emptyNearest, availableSecond])

        #expect(selected.map(\.id) == ["second-lavida", "second-kruze"])
    }
}

private func date(_ value: String) -> Date {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
    return formatter.date(from: value)!
}

private func makeListing(id: String, storeId: String, distanceKm: Double) -> RentalListing {
    RentalListing(
        id: id,
        platform: .carInc,
        store: Store(
            id: storeId,
            platform: .carInc,
            name: "\(storeId) store",
            city: "北京",
            address: "北京通州",
            location: GeoPoint(lat: 39.9 + distanceKm / 100, lng: 116.65),
            distanceKm: distanceKm,
            hours: "08:00-21:00"
        ),
        vehicleName: id,
        vehicleClass: "",
        basePrice: 100,
        platformFees: 0,
        insuranceFees: 0,
        oneWayFee: 0,
        sourceUrl: "https://m.zuche.com/",
        dataCompleteness: 0.88
    )
}
