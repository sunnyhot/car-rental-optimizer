import Foundation

public enum PlatformEvidenceStatusKind: String, Codable, Equatable {
    case waitingForEvidence = "waiting-for-evidence"
    case ready
    case unavailable
    case loginRequired = "login-required"
    case captchaRequired = "captcha-required"
    case parseFailed = "parse-failed"
}

public struct PlatformEvidenceStatus: Codable, Equatable, Identifiable {
    public var id: PlatformId { platform }

    public let platform: PlatformId
    public let kind: PlatformEvidenceStatusKind
    public let message: String
    public let sourceUrl: String

    public init(platform: PlatformId, kind: PlatformEvidenceStatusKind, message: String, sourceUrl: String) {
        self.platform = platform
        self.kind = kind
        self.message = message
        self.sourceUrl = sourceUrl
    }
}

public struct PlatformEvidenceInput: Codable, Equatable {
    public let platform: PlatformId
    public let text: String
    public let sourceUrl: String

    public init(platform: PlatformId, text: String, sourceUrl: String) {
        self.platform = platform
        self.text = text
        self.sourceUrl = sourceUrl
    }
}

public struct PlatformEvidenceResult: Codable, Equatable {
    public let platform: PlatformId
    public let status: PlatformEvidenceStatus
    public let listings: [RentalListing]

    public init(platform: PlatformId, status: PlatformEvidenceStatus, listings: [RentalListing]) {
        self.platform = platform
        self.status = status
        self.listings = listings
    }
}

public func parsePlatformEvidence(input: PlatformEvidenceInput, request: SearchRequest) -> PlatformEvidenceResult {
    let trimmedText = input.text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmedText.isEmpty {
        return result(input: input, kind: .waitingForEvidence, message: "等待粘贴\(input.platform.defaultLabel)官方搜索页面内容。")
    }

    if containsAny(trimmedText, captchaSignals) {
        return result(input: input, kind: .captchaRequired, message: "\(input.platform.defaultLabel)页面需要完成验证码或安全验证。")
    }

    if containsAny(trimmedText, loginSignals) {
        return result(input: input, kind: .loginRequired, message: "\(input.platform.defaultLabel)页面需要先登录后才能读取报价。")
    }

    if containsAny(trimmedText, unavailableSignals) {
        return result(input: input, kind: .unavailable, message: "\(input.platform.defaultLabel)官方页面显示当前日期未开放或暂无可租车辆。")
    }

    let listings = parseListings(input: input, request: request)
    if listings.isEmpty {
        return result(input: input, kind: .parseFailed, message: "\(input.platform.defaultLabel)官方页面内容已提供，但没有识别到完整车辆价格。")
    }

    return PlatformEvidenceResult(
        platform: input.platform,
        status: PlatformEvidenceStatus(
            platform: input.platform,
            kind: .ready,
            message: "已从\(input.platform.defaultLabel)官方页面识别 \(listings.count) 个候选车辆。",
            sourceUrl: input.sourceUrl
        ),
        listings: listings
    )
}

private let vehicleHints = ["瑞虎", "哈弗", "大众", "丰田", "本田", "日产", "别克", "宝马", "奔驰", "奥迪", "SUV", "自动"]
private let storeHints = ["店", "站", "机场", "门店", "取车点"]
private let basePriceHints = ["租车基础价", "基础价", "租车费", "车辆租金", "日租价", "总价", "报价"]
private let serviceFeeHints = ["平台服务费", "服务费", "手续费"]
private let insuranceHints = ["保险", "保障"]

private let unavailableSignals = ["暂未开放", "未开放", "暂无车辆", "暂无可租", "无可租", "没有车辆", "无车", "已约满", "售罄", "不可租"]
private let loginSignals = ["请先登录", "登录后查看", "手机号登录", "账号登录", "登录/注册"]
private let captchaSignals = ["验证码", "安全验证", "滑块", "人机验证", "拖动滑块"]

private func parseListings(input: PlatformEvidenceInput, request: SearchRequest) -> [RentalListing] {
    let lines = input.text
        .split(whereSeparator: \.isNewline)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

    guard !lines.isEmpty else { return [] }

    let priceLines = lines.enumerated().filter { _, line in
        extractPrice(line) != nil && containsAny(line, basePriceHints)
    }

    let listings = priceLines.compactMap { index, line -> RentalListing? in
        guard let basePrice = extractPrice(line),
              let vehicleName = findVehicleName(lines: lines, priceLineIndex: index)
        else { return nil }

        let storeName = findStoreName(lines: lines, priceLineIndex: index) ?? "\(input.platform.defaultLabel)官方门店"
        let platformFees = findFee(lines: lines, priceLineIndex: index, hints: serviceFeeHints)
        let insuranceFees = findFee(lines: lines, priceLineIndex: index, hints: insuranceHints)
        let store = Store(
            id: "\(input.platform.rawValue)-\(storeName)",
            platform: input.platform,
            name: storeName,
            city: inferCity(storeName),
            address: storeName,
            location: request.origin,
            distanceKm: 0,
            hours: "以平台页面为准"
        )

        return RentalListing(
            id: "\(input.platform.rawValue)-official-\(index)-\(vehicleName)",
            platform: input.platform,
            store: store,
            vehicleName: vehicleName,
            vehicleClass: inferVehicleClass(vehicleName),
            basePrice: basePrice,
            platformFees: platformFees,
            insuranceFees: insuranceFees,
            oneWayFee: 0,
            sourceUrl: input.sourceUrl,
            dataCompleteness: platformFees > 0 && insuranceFees > 0 ? 0.9 : 0.72,
            warnings: [.partialPrice]
        )
    }

    return dedupe(listings)
}

private func findVehicleName(lines: [String], priceLineIndex: Int) -> String? {
    let start = max(0, priceLineIndex - 5)
    return lines[start...priceLineIndex].reversed().first { containsAny($0, vehicleHints) }
}

private func findStoreName(lines: [String], priceLineIndex: Int) -> String? {
    let start = max(0, priceLineIndex - 8)
    return lines[start...priceLineIndex].reversed().first { containsAny($0, storeHints) }
}

private func findFee(lines: [String], priceLineIndex: Int, hints: [String]) -> Double {
    let end = min(lines.count - 1, priceLineIndex + 5)
    for line in lines[priceLineIndex...end] where containsAny(line, hints) {
        return extractPrice(line) ?? 0
    }
    return 0
}

private func extractPrice(_ line: String) -> Double? {
    let patterns = [
        #"[¥￥]\s*(\d{2,7})"#,
        #"(\d{2,7})\s*元"#
    ]

    for pattern in patterns {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line)
        else { continue }
        return Double(line[range])
    }

    return nil
}

private func containsAny(_ text: String, _ needles: [String]) -> Bool {
    needles.contains { text.localizedCaseInsensitiveContains($0) }
}

private func result(input: PlatformEvidenceInput, kind: PlatformEvidenceStatusKind, message: String) -> PlatformEvidenceResult {
    PlatformEvidenceResult(
        platform: input.platform,
        status: PlatformEvidenceStatus(platform: input.platform, kind: kind, message: message, sourceUrl: input.sourceUrl),
        listings: []
    )
}

private func inferVehicleClass(_ vehicleName: String) -> String {
    vehicleName.localizedCaseInsensitiveContains("suv") || vehicleName.contains("瑞虎") || vehicleName.contains("哈弗")
        ? "SUV"
        : "未知车型"
}

private func inferCity(_ storeName: String) -> String {
    if storeName.contains("北京") { return "北京" }
    if storeName.contains("德州") { return "德州" }
    if storeName.contains("天津") { return "天津" }
    if storeName.contains("济南") { return "济南" }
    return "未知城市"
}

private func dedupe(_ listings: [RentalListing]) -> [RentalListing] {
    var seen = Set<String>()
    return listings.filter { listing in
        let key = "\(listing.platform.rawValue)-\(listing.store.name)-\(listing.vehicleName)-\(listing.basePrice)"
        return seen.insert(key).inserted
    }
}

private extension PlatformId {
    var defaultLabel: String {
        switch self {
        case .ehi:
            return "一嗨"
        case .carInc:
            return "神州"
        }
    }
}
