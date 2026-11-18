import CarRentalDomain

/// Called only after a cookie-bearing confirmation attempt. A timeout, rate limit
/// or missing fee response does not mean the user's login has expired.
func zucheUnconfirmedListing(_ listing: RentalListing, loginRejected: Bool) -> RentalListing {
    var warnings = listing.warnings.filter { $0 != .loginRequired }
    if !warnings.contains(.partialPrice) { warnings.append(.partialPrice) }
    if loginRejected { warnings.append(.loginRequired) }
    return RentalListing(
        id: listing.id, platform: listing.platform, store: listing.store,
        vehicleName: listing.vehicleName, vehicleClass: listing.vehicleClass,
        basePrice: listing.basePrice, platformFees: listing.platformFees,
        insuranceFees: listing.insuranceFees, oneWayFee: listing.oneWayFee,
        currency: listing.currency, sourceUrl: listing.sourceUrl,
        dataCompleteness: listing.dataCompleteness, warnings: warnings,
        confirmedQuote: listing.confirmedQuote
    )
}
