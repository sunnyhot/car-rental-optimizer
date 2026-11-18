import CarRentalDomain
import Foundation
import Testing
@testable import CarRentalOptimizer

@Suite("Authenticated confirmation quotes")
struct ConfirmedQuoteTests {
    @Test func confirmationTotalIncludesPreparationFeeWithoutDoubleCounting() throws {
        let content = try decode(#"{"feeInfos":{"baseFeeInfo":[{"itemName":"车辆租赁及服务费","itemPrice":"188"},{"itemName":"基础服务费","itemPrice":"100"},{"itemName":"车辆整备费","itemPrice":"20"}]},"bottomInfo":{"totalPrice":"308"}}"#)
        let quote = try #require(zucheConfirmedQuote(from: content, checkedAt: Date(timeIntervalSince1970: 100)))
        #expect(quote.payableTotal == 308)
        #expect(quote.items.map(\.name) == ["车辆租赁及服务费", "基础服务费", "车辆整备费"])
        let store = Store(id: "s", platform: .carInc, name: "门店", city: "北京", address: "北京", location: GeoPoint(lat: 40, lng: 116), distanceKm: 1, hours: "08-20")
        let listing = RentalListing(id: "l", platform: .carInc, store: store, vehicleName: "车", vehicleClass: "SUV", basePrice: 999, platformFees: 100, insuranceFees: 0, oneWayFee: 0, sourceUrl: "https://www.zuche.com/", dataCompleteness: 0.9, confirmedQuote: quote)
        let route = RouteEstimate(mode: .taxi, cost: 10, durationMinutes: 5, distanceKm: 1, summary: "估算")
        let recommendation = buildRecommendation(listing: listing, match: matchVehicle(query: "", vehicleName: "车", vehicleClass: "SUV"), taxiRoute: route, transitRoute: route)
        #expect(recommendation.rentalTotal == 308)
        #expect(recommendation.bestTotal == 318)
        #expect(listing.hasCompleteRentalPrice)
        #expect(QuotePresentation.rentalLabel(recommendation) == "平台确认应付")
    }

    @Test func confirmationBasisDoesNotJoinLegacyPriceTrend() {
        let signature = ListingSignature(platform: .carInc, storeID: "s", normalizedStoreName: "store", normalizedVehicleName: "car", normalizedVehicleClass: "suv")
        let quote = ConfirmedRentalQuote(payableTotal: 100, items: [], checkedAt: Date(), sourceURL: "https://www.zuche.com/", scope: "default")
        let old = PriceSnapshot(id: "old", monitorID: "m", checkedAt: Date(), status: .successful, platformRentalPrice: 200, listingSignature: signature, priceIsComplete: true, message: "old")
        let current = PriceSnapshot(id: "new", monitorID: "m", checkedAt: Date(), status: .successful, platformRentalPrice: 100, listingSignature: signature, priceIsComplete: true, confirmedQuote: quote, message: "confirmed")
        #expect(comparableMonitorSnapshots([old, current]).map(\.id) == ["new"])
    }

    @Test func totalsAreNotReconstructedFromIncompleteFeeItems() throws {
        #expect(zucheConfirmedQuote(from: try decode(#"{"feeInfos":{"baseFeeInfo":[{"itemName":"基础服务费","itemPrice":"100"}]}}"#)) == nil)
        #expect(zucheConfirmedQuote(from: try decode(#"{"bottomInfo":{"totalPrice":"-1"}}"#)) == nil)
        #expect(zucheConfirmedQuote(from: try decode(#"{"bottomInfo":{"totalPrice":"NaN"}}"#)) == nil)
        #expect(zucheConfirmedQuote(from: try decode(#"{"bottomInfo":{"totalPrice":0}}"#))?.payableTotal == 0)
    }

    @Test func serverTotalWinsEvenIfBreakdownIsPartialOrDiscounted() throws {
        let quote = try #require(zucheConfirmedQuote(from: try decode(#"{"feeInfos":{"baseFeeInfo":[{"itemName":"基础服务费","itemPrice":"100"}]},"bottomInfo":{"totalPrice":"280"}}"#)))
        #expect(quote.payableTotal == 280)
        #expect(quote.items.count == 1)
    }

    private func decode(_ json: String) throws -> ZucheConfirmOrderContent {
        try JSONDecoder().decode(ZucheConfirmOrderContent.self, from: Data(json.utf8))
    }
}
