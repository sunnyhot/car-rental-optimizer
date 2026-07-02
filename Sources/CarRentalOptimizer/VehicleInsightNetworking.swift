import CarRentalDomain
import Foundation

protocol VehicleInsightHTTPClient {
    func data(from url: URL) async throws -> (Data, URLResponse)
}

struct URLSessionVehicleInsightHTTPClient: VehicleInsightHTTPClient {
    func data(from url: URL) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(from: url)
    }
}

struct VehicleInsightNetworkProvider {
    var httpClient: VehicleInsightHTTPClient

    func networkInsight(for listing: RentalListing, now: Date = Date()) async -> VehicleInsight? {
        let local = VehicleInsightLocalInferencer.localInsight(for: listing, now: now)
        let query = VehicleInsightLocalInferencer.normalizedQuery(for: listing)
        guard !query.isEmpty,
              let summaryURL = wikipediaSummaryURL(for: query),
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
        guard let url = wikidataURL(for: title) else { return nil }
        guard let (data, response) = try? await httpClient.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let response = try? JSONDecoder().decode(WikidataSpecResponse.self, from: data),
              let binding = response.results.bindings.first
        else { return nil }

        let sourceName = "Wikidata"
        var sheet = VehicleSpecSheet()
        sheet.lengthMm = binding.length.intValue.map {
            VehicleSpecValue(value: $0, sourceName: sourceName, sourceURL: sourceURL, confidence: .medium, appliesTo: .series)
        }
        sheet.widthMm = binding.width.intValue.map {
            VehicleSpecValue(value: $0, sourceName: sourceName, sourceURL: sourceURL, confidence: .medium, appliesTo: .series)
        }
        sheet.heightMm = binding.height.intValue.map {
            VehicleSpecValue(value: $0, sourceName: sourceName, sourceURL: sourceURL, confidence: .medium, appliesTo: .series)
        }
        sheet.wheelbaseMm = binding.wheelbase.intValue.map {
            VehicleSpecValue(value: $0, sourceName: sourceName, sourceURL: sourceURL, confidence: .medium, appliesTo: .series)
        }
        return sheet
    }

    private func wikidataURL(for title: String) -> URL? {
        URL(string: "https://query.wikidata.org/sparql?format=json&query=SELECT%20%3Flength%20%3Fwidth%20%3Fheight%20%3Fwheelbase%20WHERE%20%7B%20%7D")
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

private struct WikidataSpecResponse: Decodable {
    struct Results: Decodable {
        var bindings: [Binding]
    }

    struct Binding: Decodable {
        var length: Literal
        var width: Literal
        var height: Literal
        var wheelbase: Literal
    }

    struct Literal: Decodable {
        var value: String

        var intValue: Int? {
            guard let doubleValue = Double(value) else { return nil }
            let roundedValue = Int(doubleValue.rounded())
            return roundedValue > 0 ? roundedValue : nil
        }
    }

    var results: Results
}

private func normalizedNetworkKey(_ value: String) -> String {
    value.lowercased()
        .replacingOccurrences(of: #"[_\-]"#, with: " ", options: .regularExpression)
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
