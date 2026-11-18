import CarRentalDomain
import Foundation

protocol VehicleInsightHTTPClient {
    func data(from url: URL) async throws -> (Data, URLResponse)
    func retryAfterDate() async -> Date?
}

extension VehicleInsightHTTPClient {
    func retryAfterDate() async -> Date? { nil }
}

struct URLSessionVehicleInsightHTTPClient: VehicleInsightHTTPClient {
    private let session: URLSession
    private let pacer = VehicleReferenceRequestPacer()

    init(timeoutInterval: TimeInterval = 5) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeoutInterval
        configuration.timeoutIntervalForResource = timeoutInterval
        self.session = URLSession(configuration: configuration)
    }

    func data(from url: URL) async throws -> (Data, URLResponse) {
        try await pacer.waitForPermit()
        let result = try await session.data(from: url)
        if let response = result.1 as? HTTPURLResponse, response.statusCode == 429 {
            let retry = vehicleReferenceRetryDate(response.value(forHTTPHeaderField: "Retry-After"))
            await pacer.registerRateLimit(until: retry)
            throw VehicleReferenceRateLimitError(retryAfter: retry)
        }
        return result
    }
}

extension URLSessionVehicleInsightHTTPClient {
    func retryAfterDate() async -> Date? { await pacer.retryAfterDate() }
}

struct VehicleInsightNetworkProvider {
    var httpClient: VehicleInsightHTTPClient

    func networkInsight(for listing: RentalListing, now: Date = Date()) async -> VehicleInsight? {
        let local = VehicleInsightLocalInferencer.localInsight(for: listing, now: now)
        let query = VehicleInsightLocalInferencer.normalizedQuery(for: listing)
        guard !query.isEmpty else { return nil }

        if let modelLibraryInsight = await sohuModelLibraryInsight(for: query, local: local, now: now) {
            return modelLibraryInsight
        }

        if let summaryInsight = await wikipediaInsight(for: query, local: local, now: now) {
            return summaryInsight
        }

        return await wikidataInsight(for: query, local: local, now: now)
    }

    private func sohuModelLibraryInsight(for query: String, local: VehicleInsight, now: Date) async -> VehicleInsight? {
        let candidates = await sohuModelCandidates(for: query)
        if candidates.count > 1 { return await commonVariantInsight(candidates, query: query, local: local, now: now) }
        guard let model = candidates.first,
              acceptsNetworkTitle(model.content, for: query),
              let modelURL = URL(string: "https://db.auto.sohu.com/model_\(model.modelID)"),
              let html = try? await htmlString(from: modelURL)
        else { return nil }

        let sourceName = "搜狐车型库"
        let sourceURL = modelURL.absoluteString
        let parsedSheet = sohuSpecSheet(from: html, sourceName: sourceName, sourceURL: sourceURL)
        guard parsedSheet.hasReferenceData else { return nil }

        var enriched = local
        enriched.origin = .network
        enriched.sourceName = sourceName
        enriched.sourceURL = sourceURL
        enriched.fetchedAt = now
        enriched.confidence = .medium
        enriched.seriesName = sohuModelName(from: html) ?? model.content
        enriched.modelYear = nil
        enriched.modelYearConfidence = .low
        enriched.specSheet.lengthMm = parsedSheet.lengthMm ?? enriched.specSheet.lengthMm
        enriched.specSheet.widthMm = parsedSheet.widthMm ?? enriched.specSheet.widthMm
        enriched.specSheet.heightMm = parsedSheet.heightMm ?? enriched.specSheet.heightMm
        enriched.specSheet.wheelbaseMm = parsedSheet.wheelbaseMm ?? enriched.specSheet.wheelbaseMm
        enriched.specSheet.fuelConsumption = parsedSheet.fuelConsumption ?? enriched.specSheet.fuelConsumption
        if enriched.specSheet.seats == nil {
            enriched.specSheet.seats = parsedSheet.seats
        }
        enriched.specSheet.features = mergedFeatures(enriched.specSheet.features, with: parsedSheet.features)
        enriched.longSummary = "车系介绍：资料来自搜狐车型库的车系参配概述，提供车系级尺寸与部分配置参考。当前租赁车辆配置以平台返回为准：\(local.configurationSummary ?? "配置以平台返回为准")。下单前以平台确认页为准。"
        enriched.shortSummary = local.shortSummary
        return enriched
    }

    private func sohuModelCandidates(for query: String) async -> [SohuModelSearchResult] {
        for candidateQuery in VehicleModelIdentity.lookupQueries(query) {
            guard let url = sohuAssociateURL(for: candidateQuery),
                  let results = try? await sohuAssociateResults(from: url) else { continue }
            if let matched = results.first(where: {
                ($0.type == nil || $0.type == 2) && acceptsNetworkTitle($0.content, for: query)
            }) { return [matched] }
            var variantIDs = Set<Int>()
            let variants = results.filter { ($0.type == nil || $0.type == 2) && VehicleModelIdentity.isEnergyVariant($0.content, of: query) && variantIDs.insert($0.modelID).inserted }
            if (2...3).contains(variants.count) { return variants }
        }
        return []
    }

    private func commonVariantInsight(_ variants: [SohuModelSearchResult], query: String, local: VehicleInsight, now: Date) async -> VehicleInsight? {
        var sheets: [VehicleSpecSheet] = []
        var urls: [String] = []
        for variant in variants {
            guard let url = URL(string: "https://db.auto.sohu.com/model_\(variant.modelID)"), let html = try? await htmlString(from: url) else { return nil }
            sheets.append(sohuSpecSheet(from: html, sourceName: "搜狐车型库（多版本对照）", sourceURL: url.absoluteString).sanitizedDimensions())
            urls.append(url.absoluteString)
        }
        func common(_ value: (VehicleSpecSheet) -> VehicleSpecValue<Int>?) -> VehicleSpecValue<Int>? {
            let values = sheets.compactMap(value)
            guard values.count == sheets.count, let first = values.first, values.allSatisfy({ $0.value == first.value }) else { return nil }
            return first
        }
        var result = local
        result.specSheet.lengthMm = common { $0.lengthMm }
        result.specSheet.widthMm = common { $0.widthMm }
        result.specSheet.heightMm = common { $0.heightMm }
        result.specSheet.wheelbaseMm = common { $0.wheelbaseMm }
        guard result.specSheet.hasReferenceDimensions else { return nil }
        result.origin = .network
        result.sourceName = "搜狐车型库（多版本对照）"
        result.sourceURL = urls.first
        result.referenceSourceURLs = urls
        result.fetchedAt = now
        result.confidence = .medium
        result.seriesName = query
        result.longSummary = "车系参考：已对照本次匹配到的 \(variants.count) 个能源版本，仅采用这些版本一致的尺寸；能源、续航和具体年款配置不据此推断。"
        return result
    }

    private func sohuAssociateResults(from url: URL) async throws -> [SohuModelSearchResult] {
        let (data, response) = try await httpClient.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode([SohuModelSearchResult].self, from: data)
    }

    private func sohuAssociateURL(for query: String) -> URL? {
        var components = URLComponents(string: "https://portal.auto.sohu.com/aggr/search/associate")
        components?.queryItems = [
            URLQueryItem(name: "keyword", value: query)
        ]
        return components?.url
    }

    private func htmlString(from url: URL) async throws -> String {
        let (data, response) = try await httpClient.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        return html
    }

    private func sohuSpecSheet(from html: String, sourceName: String, sourceURL: String?) -> VehicleSpecSheet {
        var sheet = VehicleSpecSheet()
        sheet.lengthMm = sohuDimension(in: html, cssClass: "length").map {
            VehicleSpecValue(value: $0, sourceName: sourceName, sourceURL: sourceURL, confidence: .medium, appliesTo: .series)
        }
        sheet.widthMm = sohuDimension(in: html, cssClass: "width").map {
            VehicleSpecValue(value: $0, sourceName: sourceName, sourceURL: sourceURL, confidence: .medium, appliesTo: .series)
        }
        sheet.heightMm = sohuDimension(in: html, cssClass: "height").map {
            VehicleSpecValue(value: $0, sourceName: sourceName, sourceURL: sourceURL, confidence: .medium, appliesTo: .series)
        }
        sheet.wheelbaseMm = sohuDimension(in: html, cssClass: "wheelbase").map {
            VehicleSpecValue(value: $0, sourceName: sourceName, sourceURL: sourceURL, confidence: .medium, appliesTo: .series)
        }
        sheet.seats = sohuSeats(in: html).map {
            VehicleSpecValue(value: $0, sourceName: sourceName, sourceURL: sourceURL, confidence: .medium, appliesTo: .series)
        }
        sheet.fuelConsumption = sohuFuelConsumption(in: html).map {
            VehicleSpecValue(value: $0, sourceName: sourceName, sourceURL: sourceURL, confidence: .medium, appliesTo: .series)
        }
        sheet.features = sohuFeatures(in: html, sourceName: sourceName)
        return sheet
    }

    private func sohuDimension(in html: String, cssClass: String) -> Int? {
        firstCapture(
            in: html,
            pattern: #"model-main-params-size--param\s+\#(cssClass)[\s\S]*?model-main-params-size--v">\s*(\d+)\s*<"#
        ).flatMap(Int.init)
    }

    private func sohuSeats(in html: String) -> Int? {
        firstCapture(in: html, pattern: #"参配概述[\s\S]*?(\d+)\s*座"#).flatMap(Int.init)
    }

    private func sohuFuelConsumption(in html: String) -> String? {
        firstCapture(
            in: html,
            pattern: #"<p class="model-main-params-item--name">\s*油耗\s*</p>\s*<p class="model-main-params-item--value">\s*([^<]+)\s*</p>"#
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sohuModelName(from html: String) -> String? {
        firstCapture(in: html, pattern: #""name"\s*:\s*"([^"]+)""#)
    }

    private func sohuFeatures(in html: String, sourceName: String) -> [VehicleFeature] {
        let candidates = [
            (["倒车影像", "倒车视频影像", "后视摄像头"], "倒车影像"),
            (["360影像", "360度影像", "360度全景影像", "全景影像"], "360影像"),
            (["倒车雷达", "驻车雷达"], "倒车雷达"),
            (["蓝牙", "蓝牙/车载电话"], "蓝牙"),
            (["CarPlay", "手机互联", "车机互联"], "CarPlay"),
            (["手机无线充电", "无线充电"], "手机无线充电"),
            (["电动天窗", "全景天窗", "天窗"], "天窗"),
            (["无钥匙进入", "无钥匙进入系统"], "无钥匙进入"),
            (["座椅加热"], "座椅加热"),
            (["定速巡航"], "定速巡航"),
            (["自适应巡航", "ACC"], "自适应巡航"),
            (["后排隐私玻璃"], "后排隐私玻璃"),
            (["电动尾门", "电动后尾门"], "电动尾门")
        ]
        var names: [String] = []
        for (tokens, name) in candidates where tokens.contains(where: { html.localizedCaseInsensitiveContains($0) }) {
            if !names.contains(name) {
                names.append(name)
            }
        }
        return names.map {
            VehicleFeature(name: $0, sourceName: sourceName, confidence: .medium, appliesTo: .series)
        }
    }

    private func firstCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range])
    }

    private func mergedFeatures(_ base: [VehicleFeature], with additions: [VehicleFeature]) -> [VehicleFeature] {
        var result = base
        for feature in additions where !result.contains(where: { $0.name == feature.name && $0.appliesTo == feature.appliesTo }) {
            result.append(feature)
        }
        return result
    }

    private func wikipediaInsight(for query: String, local: VehicleInsight, now: Date) async -> VehicleInsight? {
        guard let summaryURL = wikipediaSummaryURL(for: query),
              let summary = try? await wikipediaSummary(from: summaryURL),
              acceptsNetworkTitle(summary.title, for: query)
        else { return nil }

        var enriched = local
        enriched.origin = .network
        enriched.sourceName = "Wikipedia"
        enriched.sourceURL = summary.pageURL
        enriched.fetchedAt = now
        enriched.confidence = .medium
        enriched.seriesName = summary.title
        enriched.modelYear = explicitModelYear(in: summary.extract)
        enriched.modelYearConfidence = enriched.modelYear == nil ? .low : .medium
        enriched.longSummary = "车系介绍：\(summary.extract) 当前租赁车辆配置以平台返回为准：\(local.configurationSummary ?? "配置以平台返回为准")。下单前以平台确认页为准。"
        enriched.shortSummary = local.shortSummary

        if let specSheet = await wikidataSpecs(for: summary.title, sourceURL: summary.pageURL) {
            enriched.specSheet.lengthMm = specSheet.lengthMm
            enriched.specSheet.widthMm = specSheet.widthMm
            enriched.specSheet.heightMm = specSheet.heightMm
            enriched.specSheet.wheelbaseMm = specSheet.wheelbaseMm
            if enriched.specSheet.bodyStyle == nil {
                enriched.specSheet.bodyStyle = specSheet.bodyStyle
            }
        }
        return enriched
    }

    private func wikidataInsight(for query: String, local: VehicleInsight, now: Date) async -> VehicleInsight? {
        guard let entity = await wikidataEntity(for: query, sourceURL: nil) else { return nil }
        var enriched = local
        enriched.origin = .network
        enriched.sourceName = "Wikidata"
        enriched.sourceURL = entity.sourceURL
        enriched.fetchedAt = now
        enriched.confidence = .medium
        enriched.seriesName = entity.label
        enriched.modelYear = nil
        enriched.modelYearConfidence = .low
        let description = entity.description.map { "，\($0)" } ?? ""
        enriched.longSummary = "车系介绍：\(entity.label)\(description)。资料来自 Wikidata。当前租赁车辆配置以平台返回为准：\(local.configurationSummary ?? "配置以平台返回为准")。下单前以平台确认页为准。"
        enriched.shortSummary = local.shortSummary
        enriched.specSheet.lengthMm = entity.specSheet.lengthMm
        enriched.specSheet.widthMm = entity.specSheet.widthMm
        enriched.specSheet.heightMm = entity.specSheet.heightMm
        enriched.specSheet.wheelbaseMm = entity.specSheet.wheelbaseMm
        if enriched.specSheet.bodyStyle == nil {
            enriched.specSheet.bodyStyle = entity.specSheet.bodyStyle
        }
        return enriched
    }

    func acceptsNetworkTitle(_ title: String, for query: String) -> Bool {
        VehicleModelIdentity.matches(title, query: query)
    }

    private func wikipediaSummary(from url: URL) async throws -> WikipediaSummaryResponse {
        let (data, response) = try await httpClient.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(WikipediaSummaryResponse.self, from: data)
    }

    private func wikipediaSummaryURL(for query: String) -> URL? {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? query
        return URL(string: "https://zh.wikipedia.org/api/rest_v1/page/summary/\(encoded)")
    }

    private func wikidataSpecs(for title: String, sourceURL: String?) async -> VehicleSpecSheet? {
        await wikidataEntity(for: title, sourceURL: sourceURL)?.specSheet
    }

    private func wikidataEntity(for query: String, sourceURL: String?) async -> WikidataResolvedEntity? {
        guard let searchURL = wikidataSearchURL(for: query),
              let searchResponse = try? await wikidataSearch(from: searchURL),
              let result = searchResponse.search.first(where: { acceptsWikidataSearchResult($0, for: query) }),
              let entityURL = wikidataEntityURL(for: result.id),
              let entity = try? await wikidataEntity(from: entityURL, id: result.id)
        else { return nil }

        let label = localizedValue(entity.labels) ?? result.label
        let description = localizedValue(entity.descriptions) ?? result.description
        let resolvedSourceURL = sourceURL ?? "https://www.wikidata.org/wiki/\(result.id)"
        return WikidataResolvedEntity(
            label: label,
            description: description,
            sourceURL: resolvedSourceURL,
            specSheet: wikidataSpecSheet(from: entity, sourceURL: resolvedSourceURL)
        )
    }

    private func wikidataSearch(from url: URL) async throws -> WikidataSearchResponse {
        let (data, response) = try await httpClient.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(WikidataSearchResponse.self, from: data)
    }

    private func wikidataEntity(from url: URL, id: String) async throws -> WikidataEntity {
        let (data, response) = try await httpClient.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(WikidataEntityDataResponse.self, from: data)
        guard let entity = decoded.entities[id] ?? decoded.entities.values.first else {
            throw URLError(.cannotParseResponse)
        }
        return entity
    }

    private func wikidataSearchURL(for query: String) -> URL? {
        var components = URLComponents(string: "https://www.wikidata.org/w/api.php")
        components?.queryItems = [
            URLQueryItem(name: "action", value: "wbsearchentities"),
            URLQueryItem(name: "search", value: query),
            URLQueryItem(name: "language", value: "zh"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "limit", value: "3")
        ]
        return components?.url
    }

    private func wikidataEntityURL(for id: String) -> URL? {
        URL(string: "https://www.wikidata.org/wiki/Special:EntityData/\(id).json")
    }

    private func acceptsWikidataSearchResult(_ result: WikidataSearchResult, for query: String) -> Bool {
        let names = [result.label, result.match?.text].compactMap { $0 } + (result.aliases ?? [])
        return names.contains { candidate in
            return acceptsNetworkTitle(candidate, for: query)
        }
    }

    private func wikidataSpecSheet(from entity: WikidataEntity, sourceURL: String?) -> VehicleSpecSheet {
        let sourceName = "Wikidata"
        var sheet = VehicleSpecSheet()
        sheet.lengthMm = quantityClaim(entity.claims["P2043"]).map {
            VehicleSpecValue(value: $0, sourceName: sourceName, sourceURL: sourceURL, confidence: .medium, appliesTo: .series)
        }
        sheet.widthMm = quantityClaim(entity.claims["P2049"]).map {
            VehicleSpecValue(value: $0, sourceName: sourceName, sourceURL: sourceURL, confidence: .medium, appliesTo: .series)
        }
        sheet.heightMm = quantityClaim(entity.claims["P2048"]).map {
            VehicleSpecValue(value: $0, sourceName: sourceName, sourceURL: sourceURL, confidence: .medium, appliesTo: .series)
        }
        sheet.wheelbaseMm = quantityClaim(entity.claims["P3039"]).map {
            VehicleSpecValue(value: $0, sourceName: sourceName, sourceURL: sourceURL, confidence: .medium, appliesTo: .series)
        }
        if let description = localizedValue(entity.descriptions), description.localizedCaseInsensitiveContains("SUV") {
            sheet.bodyStyle = VehicleSpecValue(value: "SUV", sourceName: sourceName, sourceURL: sourceURL, confidence: .medium, appliesTo: .series)
        }
        return sheet
    }

    private func quantityClaim(_ claims: [WikidataClaim]?) -> Int? {
        claims?.compactMap { claim in
            guard let quantity = claim.mainsnak.datavalue?.quantity else { return nil }
            return vehicleDimensionMillimeters(amount: quantity.amount, unit: quantity.unit)
        }.first
    }

    private func localizedValue(_ values: [String: WikidataLanguageValue]) -> String? {
        for language in ["zh-hans", "zh-cn", "zh", "en"] {
            if let value = values[language]?.value, !value.isEmpty {
                return value
            }
        }
        return values.values.map(\.value).first { !$0.isEmpty }
    }

    private func explicitModelYear(in text: String) -> String? {
        guard let match = text.range(of: #"\d{4}款"#, options: .regularExpression) else { return nil }
        return String(text[match])
    }
}

private struct WikipediaSummaryResponse: Decodable {
    struct ContentURLs: Decodable {
        struct Desktop: Decodable {
            var page: String?
        }

        var desktop: Desktop?
    }

    var title: String
    var extract: String
    var contentURLs: ContentURLs?

    var pageURL: String? {
        contentURLs?.desktop?.page
    }

    enum CodingKeys: String, CodingKey {
        case title
        case extract
        case contentURLs = "content_urls"
    }
}

private struct SohuModelSearchResult: Decodable {
    struct ModelInfo: Decodable {
        var modelID: Int?

        enum CodingKeys: String, CodingKey {
            case modelID = "model_id"
        }
    }

    var id: Int
    var content: String
    var type: Int?
    var modelInfo: ModelInfo?

    var modelID: Int {
        modelInfo?.modelID ?? id
    }

    enum CodingKeys: String, CodingKey {
        case id
        case content
        case type
        case modelInfo = "model_info"
    }
}

private extension VehicleSpecSheet {
    var hasReferenceData: Bool {
        lengthMm != nil ||
            widthMm != nil ||
            heightMm != nil ||
            wheelbaseMm != nil ||
            fuelConsumption != nil ||
            seats != nil ||
            !features.isEmpty
    }
}

private struct WikidataResolvedEntity {
    var label: String
    var description: String?
    var sourceURL: String
    var specSheet: VehicleSpecSheet
}

private struct WikidataSearchResponse: Decodable {
    var search: [WikidataSearchResult]
}

private struct WikidataSearchResult: Decodable {
    struct Match: Decodable {
        var text: String?
    }

    var id: String
    var label: String
    var description: String?
    var aliases: [String]?
    var match: Match?
}

private struct WikidataEntityDataResponse: Decodable {
    var entities: [String: WikidataEntity]
}

private struct WikidataEntity: Decodable {
    var labels: [String: WikidataLanguageValue]
    var descriptions: [String: WikidataLanguageValue]
    var claims: [String: [WikidataClaim]]
}

private struct WikidataLanguageValue: Decodable {
    var value: String
}

private struct WikidataClaim: Decodable {
    var mainsnak: WikidataSnak
}

private struct WikidataSnak: Decodable {
    var datavalue: WikidataDataValue?
}

private struct WikidataDataValue: Decodable {
    var quantity: WikidataQuantity?

    enum CodingKeys: String, CodingKey {
        case value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        quantity = try? container.decode(WikidataQuantity.self, forKey: .value)
    }
}

private struct WikidataQuantity: Decodable {
    var amount: String
    var unit: String?
}

func vehicleDimensionMillimeters(amount: String, unit: String?) -> Int? {
    guard let number = Double(amount), number.isFinite, let unit else { return nil }
    let scale: Double
    switch unit.split(separator: "/").last {
    case "Q174789": scale = 1 // millimetre
    case "Q174728": scale = 10 // centimetre
    case "Q11573": scale = 1000 // metre
    default: return nil
    }
    let millimeters = number * scale
    guard (500...15000).contains(millimeters) else { return nil }
    return Int(millimeters.rounded())
}

private func normalizedNetworkKey(_ value: String) -> String {
    value.lowercased()
        .replacingOccurrences(of: #"[_\-]"#, with: " ", options: .regularExpression)
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
