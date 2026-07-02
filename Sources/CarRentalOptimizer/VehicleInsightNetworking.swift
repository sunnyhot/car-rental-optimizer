import CarRentalDomain
import Foundation

protocol VehicleInsightHTTPClient {
    func data(from url: URL) async throws -> (Data, URLResponse)
}

struct URLSessionVehicleInsightHTTPClient: VehicleInsightHTTPClient {
    private let session: URLSession

    init(timeoutInterval: TimeInterval = 5) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeoutInterval
        configuration.timeoutIntervalForResource = timeoutInterval
        self.session = URLSession(configuration: configuration)
    }

    func data(from url: URL) async throws -> (Data, URLResponse) {
        try await session.data(from: url)
    }
}

struct VehicleInsightNetworkProvider {
    var httpClient: VehicleInsightHTTPClient

    func networkInsight(for listing: RentalListing, now: Date = Date()) async -> VehicleInsight? {
        let local = VehicleInsightLocalInferencer.localInsight(for: listing, now: now)
        let query = VehicleInsightLocalInferencer.normalizedQuery(for: listing)
        guard !query.isEmpty else { return nil }

        if let summaryInsight = await wikipediaInsight(for: query, local: local, now: now) {
            return summaryInsight
        }

        return await wikidataInsight(for: query, local: local, now: now)
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
        let titleKey = normalizedNetworkKey(title)
        let queryKey = normalizedNetworkKey(query)
        let titleCompactKey = titleKey.replacingOccurrences(of: " ", with: "")
        let queryCompactKey = queryKey.replacingOccurrences(of: " ", with: "")
        guard !titleKey.isEmpty, !queryKey.isEmpty else { return false }
        if titleCompactKey == queryCompactKey { return true }
        if titleCompactKey.contains(queryCompactKey) || queryCompactKey.contains(titleCompactKey) { return true }

        let queryTokens = Set(queryKey.split(separator: " ").map(String.init))
        let titleTokens = Set(titleKey.split(separator: " ").map(String.init))
        guard !queryTokens.isEmpty else { return false }
        return queryTokens.isSubset(of: titleTokens)
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
        guard let quantity = claims?.compactMap({ $0.mainsnak.datavalue?.quantity }).first else { return nil }
        let amount = quantity.amount.replacingOccurrences(of: "+", with: "")
        guard let value = Double(amount) else { return nil }
        let rounded = Int(value.rounded())
        return rounded > 0 ? rounded : nil
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
}

private func normalizedNetworkKey(_ value: String) -> String {
    value.lowercased()
        .replacingOccurrences(of: #"[_\-]"#, with: " ", options: .regularExpression)
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
