import CarRentalDomain

/// Never join different stores, vehicles or partial prices into one price curve.
func comparableMonitorSnapshots(_ snapshots: [PriceSnapshot]) -> [PriceSnapshot] {
    guard let latest = snapshots.last(where: { $0.status == .successful }),
          latest.priceIsComplete == true, let signature = latest.listingSignature else { return [] }
    return snapshots.filter {
        $0.status == .successful && $0.priceIsComplete == true && $0.listingSignature == signature && $0.confirmedQuote?.scope == latest.confirmedQuote?.scope
    }
}
