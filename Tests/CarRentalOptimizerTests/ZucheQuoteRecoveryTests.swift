import CarRentalDomain
import Testing
@testable import CarRentalOptimizer

@Suite("CAR Inc confirmation authentication recovery")
struct ZucheQuoteRecoveryTests {
    @Test func ordinaryQuoteFailureDoesNotInvalidateLogin() {
        let result = zucheUnconfirmedListing(listing, loginRejected: false)
        #expect(!result.warnings.contains(.loginRequired))
        #expect(result.warnings.contains(.partialPrice))
        #expect(result.id == listing.id)
        #expect(result.basePrice == listing.basePrice)
        #expect(result.confirmedQuote == nil)
    }

    @Test func explicitAuthenticationFailureStillRequiresLogin() {
        let result = zucheUnconfirmedListing(listing, loginRejected: true)
        #expect(result.warnings.contains(.loginRequired))
        #expect(result.warnings.contains(.partialPrice))
    }

    private var listing: RentalListing {
        let store = Store(id: "s", platform: .carInc, name: "test", city: "北京", address: "北京", location: GeoPoint(lat: 40, lng: 116), distanceKm: 1, hours: "08-20")
        return RentalListing(id: "l", platform: .carInc, store: store, vehicleName: "测试车型", vehicleClass: "SUV", basePrice: 100, platformFees: 0, insuranceFees: 0, oneWayFee: 0, sourceUrl: "https://www.zuche.com/", dataCompleteness: 0.7, warnings: [.partialPrice, .loginRequired])
    }
}
