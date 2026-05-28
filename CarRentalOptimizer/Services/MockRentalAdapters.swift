import Foundation

private let stores: [String: Store] = [
    "ehiTongzhou": Store(
        id: "ehi-tongzhou", platform: .ehi, name: "北京通州万达店",
        city: "北京", address: "北京市通州区万达广场附近",
        location: GeoPoint(lat: 39.909, lng: 116.657), distanceKm: 6.8, hours: "08:00-22:00"
    ),
    "ehiDezhou": Store(
        id: "ehi-dezhou-east", platform: .ehi, name: "德州东站店",
        city: "德州", address: "德州市德州东站出站口附近",
        location: GeoPoint(lat: 37.443, lng: 116.374), distanceKm: 286, hours: "08:00-20:00"
    ),
    "carSouth": Store(
        id: "car-beijing-south", platform: .carInc, name: "北京南站店",
        city: "北京", address: "北京市丰台区北京南站",
        location: GeoPoint(lat: 39.865, lng: 116.379), distanceKm: 32, hours: "07:30-22:30"
    ),
    "carTongzhouCompact": Store(
        id: "car-tongzhou-compact", platform: .carInc, name: "北京通州北苑店",
        city: "北京", address: "北京市通州区北苑附近",
        location: GeoPoint(lat: 39.903, lng: 116.642), distanceKm: 4.2, hours: "08:00-21:00"
    )
]

struct EhiMockAdapter: RentalAdapter {
    let platform: PlatformId = .ehi

    func search(request: SearchRequest) async -> [RentalListing] {
        let rentalDays = calculateRentalDays(pickupAt: request.pickupAt, returnAt: request.returnAt)

        let listings: [RentalListing] = [
            RentalListing(
                id: "ehi-tongzhou-tiggo8", platform: .ehi,
                store: stores["ehiTongzhou"]!,
                vehicleName: "奇瑞 瑞虎8 1.6T 自动", vehicleClass: "中型SUV",
                basePrice: dailyTotal(328, rentalDays), platformFees: 36, insuranceFees: 50,
                oneWayFee: request.returnMode == .differentStore ? 120 : 0,
                currency: "CNY", sourceUrl: "https://www.1hai.cn/",
                dataCompleteness: 0.98, warnings: []
            ),
            RentalListing(
                id: "ehi-dezhou-tiggo8", platform: .ehi,
                store: stores["ehiDezhou"]!,
                vehicleName: "奇瑞 瑞虎8", vehicleClass: "中型SUV",
                basePrice: dailyTotal(120, rentalDays), platformFees: 25, insuranceFees: 40,
                oneWayFee: request.returnMode == .differentStore ? 180 : 0,
                currency: "CNY", sourceUrl: "https://www.1hai.cn/",
                dataCompleteness: 0.92, warnings: [.crossCityPickup]
            )
        ]

        return filterByRadius(listings.map { withDynamicDistance($0, request) }, radiusKm: request.radiusKm)
    }
}

struct CarIncMockAdapter: RentalAdapter {
    let platform: PlatformId = .carInc

    func search(request: SearchRequest) async -> [RentalListing] {
        let rentalDays = calculateRentalDays(pickupAt: request.pickupAt, returnAt: request.returnAt)

        let listings: [RentalListing] = [
            RentalListing(
                id: "car-south-haval-h6", platform: .carInc,
                store: stores["carSouth"]!,
                vehicleName: "哈弗 H6 自动", vehicleClass: "紧凑型SUV",
                basePrice: dailyTotal(268, rentalDays), platformFees: 42, insuranceFees: 55,
                oneWayFee: request.returnMode == .differentStore ? 150 : 0,
                currency: "CNY", sourceUrl: "https://www.zuche.com/",
                dataCompleteness: 0.95, warnings: []
            ),
            RentalListing(
                id: "car-tongzhou-lavida", platform: .carInc,
                store: stores["carTongzhouCompact"]!,
                vehicleName: "大众 朗逸 自动", vehicleClass: "紧凑型轿车",
                basePrice: dailyTotal(98, rentalDays), platformFees: 30, insuranceFees: 45,
                oneWayFee: request.returnMode == .differentStore ? 100 : 0,
                currency: "CNY", sourceUrl: "https://www.zuche.com/",
                dataCompleteness: 0.94, warnings: []
            )
        ]

        return filterByRadius(listings.map { withDynamicDistance($0, request) }, radiusKm: request.radiusKm)
    }
}

private func filterByRadius(_ listings: [RentalListing], radiusKm: Double) -> [RentalListing] {
    listings.filter { $0.store.distanceKm <= radiusKm }
}

private func dailyTotal(_ dailyPrice: Double, _ rentalDays: Int) -> Double {
    dailyPrice * Double(rentalDays)
}

private func withDynamicDistance(_ listing: RentalListing, _ request: SearchRequest) -> RentalListing {
    let distanceKm = distanceKmBetween(request.origin, listing.store.location)
    var warnings = Set(listing.warnings)

    if distanceKm >= 80 {
        warnings.insert(.crossCityPickup)
    } else {
        warnings.remove(.crossCityPickup)
    }

    return RentalListing(
        id: listing.id, platform: listing.platform,
        store: Store(
            id: listing.store.id, platform: listing.store.platform,
            name: listing.store.name, city: listing.store.city,
            address: listing.store.address, location: listing.store.location,
            distanceKm: distanceKm, hours: listing.store.hours
        ),
        vehicleName: listing.vehicleName, vehicleClass: listing.vehicleClass,
        basePrice: listing.basePrice, platformFees: listing.platformFees,
        insuranceFees: listing.insuranceFees, oneWayFee: listing.oneWayFee,
        currency: listing.currency, sourceUrl: listing.sourceUrl,
        dataCompleteness: listing.dataCompleteness, warnings: Array(warnings)
    )
}
