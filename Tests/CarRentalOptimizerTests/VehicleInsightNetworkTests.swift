import CarRentalDomain
import Foundation
import Testing
@testable import CarRentalOptimizer

@Suite("Vehicle insight networking")
struct VehicleInsightNetworkTests {
    @Test("Wikipedia summary enriches local insight without claiming model year")
    func wikipediaSummaryEnrichesLocalInsightWithoutClaimingModelYear() async {
        let listing = makeNetworkListing(vehicleName: "大众 朗逸", vehicleClass: "1.5L | 三厢 5座 | 蓝牙")
        let client = StubVehicleInsightHTTPClient(responses: [
            "https://zh.wikipedia.org/api/rest_v1/page/summary/%E5%A4%A7%E4%BC%97%20%E6%9C%97%E9%80%B8": wikipediaSummaryJSON(
                title: "大众朗逸",
                extract: "大众朗逸是上汽大众生产的一款紧凑型轿车，主要面向中国市场。",
                pageURL: "https://zh.wikipedia.org/wiki/%E5%A4%A7%E4%BC%97%E6%9C%97%E9%80%B8"
            ),
            wikidataSearchURL("大众朗逸"): wikidataSearchJSON(
                id: "Q1",
                label: "大众朗逸",
                description: "紧凑型轿车",
                aliases: ["大众 朗逸"],
                matchText: "大众朗逸"
            ),
            wikidataEntityURL("Q1"): wikidataEntityJSON(
                id: "Q1",
                label: "大众朗逸",
                description: "紧凑型轿车",
                length: 4670,
                width: 1806,
                height: 1474,
                wheelbase: 2688
            )
        ])
        let provider = VehicleInsightNetworkProvider(httpClient: client)

        let insight = await provider.networkInsight(for: listing, now: networkDate("2026-07-02 17:14"))

        #expect(insight?.origin == .network)
        #expect(insight?.sourceName == "Wikipedia")
        #expect(insight?.seriesName == "大众朗逸")
        #expect(insight?.modelYear == nil)
        #expect(insight?.modelYearConfidence == .low)
        #expect(insight?.specSheet.lengthMm?.value == 4670)
        #expect(insight?.specSheet.lengthMm?.appliesTo == .series)
        #expect(insight?.specSheet.wheelbaseMm?.value == 2688)
        #expect(insight?.specSheet.features.map(\.name) == ["蓝牙"])
        #expect(insight?.longSummary.contains("车系介绍：大众朗逸是上汽大众生产的一款紧凑型轿车") == true)
        #expect(insight?.longSummary.contains("当前租赁车辆配置以平台返回为准") == true)
    }

    @Test("Wikidata alias search enriches when Wikipedia summary is unavailable")
    func wikidataAliasSearchEnrichesWhenWikipediaSummaryIsUnavailable() async {
        let listing = makeNetworkListing(vehicleName: "日产劲客", vehicleClass: "SUV 5座")
        let client = StubVehicleInsightHTTPClient(responses: [
            wikidataSearchURL("日产劲客"): wikidataSearchJSON(
                id: "Q26186522",
                label: "Nissan Kicks",
                description: "subcompact crossover SUV",
                aliases: ["日产劲客", "劲客"],
                matchText: "日产劲客"
            ),
            wikidataEntityURL("Q26186522"): wikidataEntityJSON(
                id: "Q26186522",
                label: "日产劲客",
                description: "车型",
                length: 4295,
                width: 1760,
                height: 1590,
                wheelbase: 2610
            )
        ])
        let provider = VehicleInsightNetworkProvider(httpClient: client)

        let insight = await provider.networkInsight(for: listing, now: networkDate("2026-07-02 20:30"))

        #expect(insight?.origin == .network)
        #expect(insight?.sourceName == "Wikidata")
        #expect(insight?.seriesName == "日产劲客")
        #expect(insight?.specSheet.lengthMm?.value == 4295)
        #expect(insight?.specSheet.widthMm?.value == 1760)
        #expect(insight?.specSheet.heightMm?.value == 1590)
        #expect(insight?.specSheet.wheelbaseMm?.value == 2610)
        #expect(insight?.specSheet.seats?.value == 5)
        #expect(insight?.longSummary.contains("车系介绍：日产劲客") == true)
    }

    @Test("Irrelevant Wikipedia title is rejected")
    func irrelevantWikipediaTitleIsRejected() async {
        let listing = makeNetworkListing(vehicleName: "小鹏 MONA", vehicleClass: "纯电 51kWh | 三厢 5座")
        let client = StubVehicleInsightHTTPClient(responses: [
            "https://zh.wikipedia.org/api/rest_v1/page/summary/%E5%B0%8F%E9%B9%8F%20MONA": wikipediaSummaryJSON(
                title: "小鹏汽车",
                extract: "小鹏汽车是一家中国电动汽车公司。",
                pageURL: "https://zh.wikipedia.org/wiki/%E5%B0%8F%E9%B9%8F%E6%B1%BD%E8%BD%A6"
            )
        ])
        let provider = VehicleInsightNetworkProvider(httpClient: client)

        let insight = await provider.networkInsight(for: listing, now: networkDate("2026-07-02 17:14"))

        #expect(insight == nil)
    }
}

private struct StubVehicleInsightHTTPClient: VehicleInsightHTTPClient {
    let responses: [String: String]

    func data(from url: URL) async throws -> (Data, URLResponse) {
        guard let body = responses[url.absoluteString] else {
            throw URLError(.resourceUnavailable)
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }
}

private func wikipediaSummaryJSON(title: String, extract: String, pageURL: String) -> String {
    """
    {
      "title": "\(title)",
      "extract": "\(extract)",
      "content_urls": {
        "desktop": {
          "page": "\(pageURL)"
        }
      }
    }
    """
}

private func wikidataSearchURL(_ query: String) -> String {
    var components = URLComponents(string: "https://www.wikidata.org/w/api.php")!
    components.queryItems = [
        URLQueryItem(name: "action", value: "wbsearchentities"),
        URLQueryItem(name: "search", value: query),
        URLQueryItem(name: "language", value: "zh"),
        URLQueryItem(name: "format", value: "json"),
        URLQueryItem(name: "limit", value: "3")
    ]
    return components.url!.absoluteString
}

private func wikidataEntityURL(_ id: String) -> String {
    "https://www.wikidata.org/wiki/Special:EntityData/\(id).json"
}

private func wikidataSearchJSON(
    id: String,
    label: String,
    description: String,
    aliases: [String],
    matchText: String
) -> String {
    let aliasJSON = aliases.map { "\"\($0)\"" }.joined(separator: ", ")
    return """
    {
      "search": [
        {
          "id": "\(id)",
          "label": "\(label)",
          "description": "\(description)",
          "aliases": [\(aliasJSON)],
          "match": {
            "type": "alias",
            "language": "zh",
            "text": "\(matchText)"
          }
        }
      ],
      "success": 1
    }
    """
}

private func wikidataEntityJSON(
    id: String,
    label: String,
    description: String,
    length: Int,
    width: Int,
    height: Int,
    wheelbase: Int
) -> String {
    """
    {
      "entities": {
        "\(id)": {
          "labels": {
            "zh-hans": { "language": "zh-hans", "value": "\(label)" },
            "en": { "language": "en", "value": "\(label)" }
          },
          "descriptions": {
            "zh-hans": { "language": "zh-hans", "value": "\(description)" },
            "en": { "language": "en", "value": "\(description)" }
          },
          "claims": {
            "P2043": [\(wikidataQuantityClaim(length))],
            "P2049": [\(wikidataQuantityClaim(width))],
            "P2048": [\(wikidataQuantityClaim(height))],
            "P3039": [\(wikidataQuantityClaim(wheelbase))]
          }
        }
      }
    }
    """
}

private func wikidataQuantityClaim(_ value: Int) -> String {
    """
    {
      "mainsnak": {
        "datavalue": {
          "value": {
            "amount": "+\(value)",
            "unit": "http://www.wikidata.org/entity/Q174789"
          }
        }
      }
    }
    """
}

private func makeNetworkListing(vehicleName: String, vehicleClass: String) -> RentalListing {
    RentalListing(
        id: UUID().uuidString,
        platform: .ehi,
        store: Store(
            id: "network-store",
            platform: .ehi,
            name: "联网测试门店",
            city: "北京",
            address: "北京市通州区",
            location: GeoPoint(lat: 39.91, lng: 116.65),
            distanceKm: 0.86,
            hours: "08:00-22:00"
        ),
        vehicleName: vehicleName,
        vehicleClass: vehicleClass,
        basePrice: 70,
        platformFees: 0,
        insuranceFees: 0,
        oneWayFee: 0,
        sourceUrl: "https://booking.1hai.cn/",
        dataCompleteness: 1
    )
}

private func networkDate(_ value: String) -> Date {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
    return formatter.date(from: value)!
}
