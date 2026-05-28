import Foundation

private let vehicleHints = ["瑞虎", "哈弗", "大众", "丰田", "本田", "日产", "别克", "宝马", "奔驰", "奥迪", "SUV", "自动"]
private let storeHints = ["店", "站", "机场", "门店", "取车点"]
private let nonVehiclePriceHints = ["保险", "保障", "押金", "服务费", "手续费", "违章", "优惠", "券"]

func parseLivePlatformSnapshot(snapshot: LivePlatformSnapshot, request: SearchRequest) -> [RentalListing] {
    let lines = splitPageLines(snapshot.text)
    var listings: [RentalListing] = []

    for (index, line) in lines.enumerated() {
        if nonVehiclePriceHints.contains(where: { line.contains($0) }) { continue }
        guard let price = extractPrice(from: line) else { continue }
        guard let vehicleName = findVehicleName(in: lines, around: index) else { continue }

        let storeName = findStoreName(in: lines, around: index)
        let store = buildStore(platform: snapshot.platform, name: storeName, request: request)

        listings.append(RentalListing(
            id: "\(snapshot.platform)-live-\(index)-\(vehicleName)",
            platform: snapshot.platform,
            store: store,
            vehicleName: vehicleName,
            vehicleClass: inferVehicleClass(vehicleName),
            basePrice: price,
            platformFees: 0,
            insuranceFees: 0,
            oneWayFee: 0,
            currency: "CNY",
            sourceUrl: snapshot.url,
            dataCompleteness: 0.72,
            warnings: [.partialPrice]
        ))
    }

    return dedupeListings(listings)
}

func analyzeLivePlatformSnapshot(_ snapshot: LivePlatformSnapshot) -> SnapshotDiagnostics {
    let lines = splitPageLines(snapshot.text)
    return SnapshotDiagnostics(
        platform: snapshot.platform,
        title: snapshot.title,
        url: snapshot.url,
        textLength: snapshot.text.count,
        lineCount: lines.count,
        priceCandidateCount: lines.filter { extractPrice(from: $0) != nil }.count,
        vehicleCandidateCount: lines.filter(hasVehicleHint).count,
        storeCandidateCount: lines.filter(hasStoreHint).count
    )
}

private func splitPageLines(_ text: String) -> [String] {
    text.split(separator: "\n", omittingEmptySubsequences: true).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
}

private func extractPrice(from line: String) -> Double? {
    guard let match = line.range(of: "[¥￥]\\s*(\\d{2,6})|(\\d{2,6})\\s*元", options: .regularExpression) else { return nil }
    let matched = String(line[match])
    let digits = matched.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
    guard let value = Double(digits), value >= 10 else { return nil }
    return value
}

private func findVehicleName(in lines: [String], around index: Int) -> String? {
    let start = max(0, index - 4)
    let candidates = lines[start...index].reversed()
    return candidates.first(where: hasVehicleHint)
}

private func findStoreName(in lines: [String], around index: Int) -> String {
    let start = max(0, index - 8)
    let candidates = lines[start...index].reversed()
    return candidates.first(where: hasStoreHint) ?? "平台当前门店"
}

private func hasVehicleHint(_ line: String) -> Bool {
    vehicleHints.contains { line.lowercased().contains($0.lowercased()) }
}

private func hasStoreHint(_ line: String) -> Bool {
    storeHints.contains { line.contains($0) }
}

private func buildStore(platform: PlatformId, name: String, request: SearchRequest) -> Store {
    let location = resolveKnownOrigin(name) ?? request.origin
    let distanceKm = distanceKmBetween(request.origin, location)
    return Store(
        id: "\(platform)-\(name)",
        platform: platform,
        name: name,
        city: inferCity(name),
        address: name,
        location: location,
        distanceKm: distanceKm,
        hours: "以平台页面为准"
    )
}

private func inferVehicleClass(_ vehicleName: String) -> String {
    vehicleName.lowercased().contains("suv") || vehicleName.contains("瑞虎") || vehicleName.contains("哈弗") ? "SUV" : "未知车型"
}

private func inferCity(_ storeName: String) -> String {
    if storeName.contains("德州") { return "德州" }
    if storeName.contains("北京") { return "北京" }
    if storeName.contains("天津") { return "天津" }
    if storeName.contains("济南") { return "济南" }
    return "未知城市"
}

private func dedupeListings(_ listings: [RentalListing]) -> [RentalListing] {
    var seen = Set<String>()
    return listings.filter { listing in
        let key = "\(listing.platform)-\(listing.store.name)-\(listing.vehicleName)-\(listing.basePrice)"
        if seen.contains(key) { return false }
        seen.insert(key)
        return true
    }
}
