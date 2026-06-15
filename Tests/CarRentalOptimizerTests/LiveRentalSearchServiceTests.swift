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

    @Test("eHi blank vehicle query probes stores inside radius before reporting no cars")
    func ehiBlankVehicleQueryProbesStoresInsideRadiusBeforeReportingNoCars() {
        let script = makeEhiSearchScript(json: "{}")

        #expect(script.contains("blankStoreProbeLimit = 40"))
        #expect(script.contains("const blankStoreCandidates = storeCandidates.filter(s => s.distanceKm <= request.radiusKm)"))
        #expect(script.contains(": blankStoreCandidates.slice(0, blankStoreProbeLimit)"))
        #expect(script.contains("selectedBlankStoreId"))
        #expect(script.contains("!hasVehicleQuery && selectedBlankStoreId && store.id !== selectedBlankStoreId"))
        #expect(script.contains("半径 ${Math.round(request.radiusKm)}km"))
        #expect(!script.contains(": storeCandidates.slice(0, nearestStoreProbeLimit)"))
    }

    @Test("eHi city matching recognizes English Beijing address from Apple location")
    func ehiCityMatchingRecognizesEnglishBeijingAddressFromAppleLocation() {
        let candidates = originCityCandidates(
            from: """
            Jingdong Group Quanqiu Headquarters Beijing No.2Park
            Beijing Tongzhou Beijing Economic and Technological Development Zone
            (Jinghai Road Subway Station West Entrance Exit A1 Pedestrian 120 Meters)
            """
        )
        let script = makeEhiSearchScript(json: "{}")

        #expect(candidates.contains("北京"))
        #expect(candidates.contains("通州"))
        #expect(script.contains("originCityCandidates"))
        #expect(script.contains("aliasMatchesCity"))
    }

    @Test("Blank vehicle query keeps all vehicles from nearest priced store only")
    func blankVehicleQueryKeepsAllVehiclesFromNearestPricedStoreOnly() {
        let sparseNearest = StoreListingsBatch(
            distanceKm: 0.3,
            listings: [
                makeListing(id: "nearest-lavida", storeId: "nearest", vehicleName: "大众朗逸", basePrice: 175, distanceKm: 0.3),
                makeListing(id: "nearest-kruze", storeId: "nearest", vehicleName: "雪佛兰科鲁泽", basePrice: 178, distanceKm: 0.3),
            ]
        )
        let richerNearby = StoreListingsBatch(
            distanceKm: 4.7,
            listings: [
                makeListing(id: "nearby-lavida", storeId: "nearby", vehicleName: "大众朗逸", basePrice: 168, distanceKm: 4.7),
                makeListing(id: "nearby-camry", storeId: "nearby", vehicleName: "丰田凯美瑞", basePrice: 198, distanceKm: 4.7),
                makeListing(id: "nearby-a6", storeId: "nearby", vehicleName: "奥迪A6L", basePrice: 408, distanceKm: 4.7),
            ]
        )

        let selected = blankVehicleCandidateListings(from: [richerNearby, sparseNearest], minimumVehicleCount: 4)

        #expect(Set(selected.map(\.vehicleName)) == ["大众朗逸", "雪佛兰科鲁泽"])
        #expect(selected.first { $0.vehicleName == "大众朗逸" }?.id == "nearest-lavida")
    }
}

private func date(_ value: String) -> Date {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
    return formatter.date(from: value)!
}

private func makeListing(
    id: String,
    storeId: String,
    vehicleName: String = "大众朗逸",
    basePrice: Double = 100,
    distanceKm: Double
) -> RentalListing {
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
        vehicleName: vehicleName,
        vehicleClass: "",
        basePrice: basePrice,
        platformFees: 0,
        insuranceFees: 0,
        oneWayFee: 0,
        sourceUrl: "https://m.zuche.com/",
        dataCompleteness: 0.88
    )
}
