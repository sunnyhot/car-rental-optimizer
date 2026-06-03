import CarRentalDomain
import Foundation
import WebKit

protocol RentalSearchProviding {
    func search(request: SearchRequest) async -> [PlatformEvidenceResult]
}

@MainActor
final class LiveRentalSearchService: NSObject, RentalSearchProviding {
    private let zucheClient = ZucheAPIClient()
    private let ehiClient = EhiBridgeClient()

    func search(request: SearchRequest) async -> [PlatformEvidenceResult] {
        var results: [PlatformEvidenceResult] = []

        if request.platforms.contains(.carInc) {
            results.append(await zucheClient.search(request: request))
        }

        if request.platforms.contains(.ehi) {
            results.append(await ehiClient.search(request: request))
        }

        return request.platforms.compactMap { platform in
            results.first { $0.platform == platform }
        }
    }
}

struct SnapshotRentalSearchService: RentalSearchProviding {
    let snapshotProvider: PlatformSnapshotProviding

    func search(request: SearchRequest) async -> [PlatformEvidenceResult] {
        var results: [PlatformEvidenceResult] = []
        for platform in request.platforms {
            do {
                let snapshot = try await snapshotProvider.snapshot(for: platform)
                results.append(parsePlatformEvidence(
                    input: PlatformEvidenceInput(
                        platform: platform,
                        text: snapshot.text,
                        sourceUrl: snapshot.url
                    ),
                    request: request
                ))
            } catch {
                results.append(PlatformEvidenceResult(
                    platform: platform,
                    status: PlatformEvidenceStatus(
                        platform: platform,
                        kind: .parseFailed,
                        message: "\(platform.label)页面读取失败：\(error.localizedDescription)",
                        sourceUrl: officialPlatformURL(for: platform)
                    ),
                    listings: []
                ))
            }
        }
        return results
    }
}

// MARK: - Zuche

private final class ZucheAPIClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(request: SearchRequest) async -> PlatformEvidenceResult {
        do {
            let cities: ZucheCityListContent = try await postGateway(uri: "/action/carrctapi/order/cityList/v1", payload: [:])
            guard let city = selectCity(from: cities.allCities, request: request) else {
                return status(.unavailable, "神州没有识别到当前位置对应的可租城市。")
            }

            let deptList: ZucheDeptListContent = try await postGateway(
                uri: "/action/carrctapi/order/deptList/v1",
                payload: ["cityId": city.cityId, "entrance": 1, "pickupFlag": 1]
            )
            let stores = flattenDepartments(deptList)
            guard !stores.isEmpty else {
                return status(.unavailable, "神州当前城市没有返回可用取车点。")
            }

            let candidates = candidateStores(stores, request: request)
            guard !candidates.isEmpty else {
                return status(.unavailable, "神州在当前范围内没有可用取车点。")
            }

            let pickupTime = platformDateTime(request.pickupAt)
            let returnTime = platformDateTime(request.returnAt)
            let hasVehicleQuery = !request.vehicleQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            var listingsByKey: [String: RentalListing] = [:]

            for candidate in candidates {
                let chooseCar: ZucheChooseCarContent = try await postGateway(
                    uri: "/resource/carrctapi/order/chooseCar/v3",
                    payload: [
                        "pickupCityId": city.cityId,
                        "pickupTime": pickupTime,
                        "returnCityId": city.cityId,
                        "returnTime": returnTime,
                        "entrance": 1,
                        "userChooseLat": String(candidate.location.lat),
                        "userChooseLon": String(candidate.location.lng),
                        "holidaysWaitingFlag": 0,
                    ]
                )

                for dept in chooseCar.deptHangModels {
                    guard let store = makeStore(from: dept, request: request) else { continue }
                    if hasVehicleQuery {
                        guard store.distanceKm <= request.radiusKm else { continue }
                    } else {
                        guard store.id == candidate.id else { continue }
                    }

                    for model in dept.models where model.bookFlag != false && model.havePriceFlag != false {
                        guard let dailyPrice = model.price else { continue }
                        let listing = RentalListing(
                            id: "car-inc-\(store.id)-\(model.modelId)",
                            platform: .carInc,
                            store: store,
                            vehicleName: model.modelName,
                            vehicleClass: model.modelDesc,
                            basePrice: dailyPrice * Double(rentalDays(request)),
                            platformFees: 0,
                            insuranceFees: 0,
                            oneWayFee: 0,
                            sourceUrl: "https://m.zuche.com/#/rent/list",
                            dataCompleteness: 0.88,
                            warnings: [.partialPrice]
                        )
                        let key = "\(store.id)-\(model.modelName)"
                        if let old = listingsByKey[key], old.basePrice <= listing.basePrice {
                            continue
                        }
                        listingsByKey[key] = listing
                    }
                }
            }

            let listings = Array(listingsByKey.values)
            guard !listings.isEmpty else {
                return status(.unavailable, "神州真实接口返回成功，但当前条件没有可订车型。")
            }

            return PlatformEvidenceResult(
                platform: .carInc,
                status: PlatformEvidenceStatus(
                    platform: .carInc,
                    kind: .ready,
                    message: "已从神州 API 读取 \(listings.count) 个真实候选车型。",
                    sourceUrl: "https://m.zuche.com/"
                ),
                listings: listings
            )
        } catch {
            return status(.parseFailed, "神州 API 查询失败：\(error.localizedDescription)")
        }
    }

    private func postGateway<Response: Decodable>(uri: String, payload: [String: Any]) async throws -> Response {
        let envelope: ZucheResponse<Response> = try await postForm(
            url: URL(string: "https://m.zuche.com/api/gw.do?uri=\(uri)")!,
            payload: payload,
            referer: "https://m.zuche.com/"
        )
        guard envelope.code == 1 || envelope.status == "SUCCESS", let content = envelope.content else {
            throw PlatformAPIError.message(envelope.msg ?? "神州接口返回异常")
        }
        return content
    }

    private func postForm<Response: Decodable>(url: URL, payload: [String: Any], referer: String) async throws -> ZucheResponse<Response> {
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        let json = String(data: data, encoding: .utf8) ?? "{}"
        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "data", value: json)]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(referer, forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148", forHTTPHeaderField: "User-Agent")

        let (responseData, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw PlatformAPIError.message("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        return try JSONDecoder().decode(ZucheResponse<Response>.self, from: responseData)
    }

    private func selectCity(from cities: [ZucheCity], request: SearchRequest) -> ZucheCity? {
        let label = request.originLabel
        if let exact = cities.first(where: { label.contains($0.cityName) }) {
            return exact
        }

        return cities
            .compactMap { city -> (ZucheCity, Double)? in
                guard let point = city.location else { return nil }
                return (city, distanceKmBetween(from: request.origin, to: point))
            }
            .min { $0.1 < $1.1 }?
            .0
    }

    private func flattenDepartments(_ content: ZucheDeptListContent) -> [ZucheDept] {
        content.districtList.flatMap(\.deptList).filter { $0.inventoryAbleFlag != false }
    }

    private func candidateStores(_ stores: [ZucheDept], request: SearchRequest) -> [Store] {
        let sorted = stores.compactMap { makeStore(from: $0, request: request) }.sorted { $0.distanceKm < $1.distanceKm }
        let hasVehicleQuery = !request.vehicleQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasVehicleQuery ? sorted.filter { $0.distanceKm <= request.radiusKm } : Array(sorted.prefix(1))
    }

    private func makeStore(from dept: ZucheDept, request: SearchRequest) -> Store? {
        guard let location = dept.location else { return nil }
        return Store(
            id: String(dept.deptId),
            platform: .carInc,
            name: dept.deptName,
            city: request.originLabel.contains("北京") ? "北京" : "",
            address: dept.deptAddress,
            location: location,
            distanceKm: distanceKmBetween(from: request.origin, to: location),
            hours: dept.workTime
        )
    }

    private func makeStore(from dept: ZucheDeptModels, request: SearchRequest) -> Store? {
        guard let location = dept.location else { return nil }
        return Store(
            id: String(dept.deptId),
            platform: .carInc,
            name: dept.deptName,
            city: request.originLabel.contains("北京") ? "北京" : "",
            address: dept.deptAddress,
            location: location,
            distanceKm: distanceKmBetween(from: request.origin, to: location),
            hours: dept.workTime
        )
    }

    private func status(_ kind: PlatformEvidenceStatusKind, _ message: String) -> PlatformEvidenceResult {
        PlatformEvidenceResult(
            platform: .carInc,
            status: PlatformEvidenceStatus(platform: .carInc, kind: kind, message: message, sourceUrl: "https://m.zuche.com/"),
            listings: []
        )
    }
}

// MARK: - Ehi

@MainActor
private final class EhiBridgeClient: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<Void, Never>?

    func search(request: SearchRequest) async -> PlatformEvidenceResult {
        do {
            let webView = try await readyWebView()
            let payload = try JSONEncoder().encode(EhiBridgeRequest(request: request))
            let json = String(data: payload, encoding: .utf8) ?? "{}"
            let result = try await webView.callAsyncJavaScript(ehiSearchScript(json: json), arguments: [:], in: nil, contentWorld: .page)
            guard let resultString = result as? String else {
                return status(.parseFailed, "一嗨 API 桥接返回了无法识别的数据。")
            }
            let decoded = try JSONDecoder().decode(EhiBridgeResponse.self, from: Data(resultString.utf8))
            let kind = PlatformEvidenceStatusKind(rawValue: decoded.statusKind) ?? .parseFailed
            let listings = decoded.listings.map { $0.domainListing(request: request) }
            return PlatformEvidenceResult(
                platform: .ehi,
                status: PlatformEvidenceStatus(platform: .ehi, kind: kind, message: decoded.message, sourceUrl: decoded.sourceUrl),
                listings: listings
            )
        } catch {
            return status(.parseFailed, "一嗨 API 查询失败：\(error.localizedDescription)")
        }
    }

    private func readyWebView() async throws -> WKWebView {
        if let webView, let currentURL = webView.url, currentURL.host == "booking.1hai.cn", currentURL.path == "/order/firstStep" {
            return webView
        }

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        webView.navigationDelegate = self
        self.webView = webView

        await withCheckedContinuation { continuation in
            self.continuation = continuation
            webView.load(URLRequest(url: URL(string: "https://booking.1hai.cn/order/firstStep")!))
        }
        return webView
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume()
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        continuation?.resume()
        continuation = nil
    }

    private func status(_ kind: PlatformEvidenceStatusKind, _ message: String) -> PlatformEvidenceResult {
        PlatformEvidenceResult(
            platform: .ehi,
            status: PlatformEvidenceStatus(platform: .ehi, kind: kind, message: message, sourceUrl: "https://booking.1hai.cn/order/firstStep"),
            listings: []
        )
    }

    private func ehiSearchScript(json: String) -> String {
        """
        const request = \(json);
        const sourceUrl = 'https://booking.1hai.cn/order/firstStep';
        for (let i = 0; i < 50 && !window.webpackChunkbooking; i += 1) {
          await new Promise(resolve => setTimeout(resolve, 100));
        }
        if (!window.webpackChunkbooking) {
          return JSON.stringify({
            statusKind: 'parse-failed',
            message: '一嗨 API 页面脚本未加载完成，请稍后重试。',
            sourceUrl,
            listings: []
          });
        }
        const reqId = Math.floor(Math.random() * 1000000000);
        let requireFn;
        window.webpackChunkbooking.push([[reqId], {}, function(r) { requireFn = r; }]);
        const http = requireFn(4211).A;
        const util = requireFn(2780).A;
        const days = Math.max(1, Math.ceil((Date.parse(request.returnAt + 'T10:00:00+08:00') - Date.parse(request.pickupAt + 'T10:00:00+08:00')) / 86400000));
        const hasVehicleQuery = (request.vehicleQuery || '').trim().length > 0;
        const toTime = (date) => date.includes(' ') ? date : date + ' 10:00';
        const num = (value) => {
          if (value === null || value === undefined) return null;
          const n = Number(String(value).replace(/[^0-9.]/g, ''));
          return Number.isFinite(n) ? n : null;
        };
        const distanceKm = (a, b) => {
          const rad = Math.PI / 180;
          const dLat = (b.lat - a.lat) * rad;
          const dLng = (b.lng - a.lng) * rad;
          const lat1 = a.lat * rad;
          const lat2 = b.lat * rad;
          const h = Math.sin(dLat / 2) ** 2 + Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2;
          return 6371 * 2 * Math.asin(Math.sqrt(h));
        };
        const cityListResp = await http.getEncrypt('/Address/City/List', {});
        const cities = (cityListResp.data && cityListResp.data.result) || [];
        const origin = { lat: request.origin.lat, lng: request.origin.lng };
        let city = cities.find(c => (request.originLabel || '').includes(c.city));
        if (!city) {
          city = cities
            .filter(c => num(c.defaultLocation) !== null || (num(c.cityLat) !== null && num(c.cityLon) !== null))
            .map(c => ({ city: c, distance: distanceKm(origin, { lat: num(c.cityLat) || origin.lat, lng: num(c.cityLon) || origin.lng }) }))
            .sort((a, b) => a.distance - b.distance)[0]?.city;
        }
        if (!city) {
          return JSON.stringify({ statusKind: 'unavailable', message: '一嗨没有识别到当前位置对应的可租城市。', sourceUrl, listings: [] });
        }
        const storeResp = await http.getEncrypt('/Address/ReservationBooking/List', { cityId: city.cityId, operationTime: toTime(request.pickupAt) });
        const groups = (storeResp.data && storeResp.data.result) || [];
        const stores = [];
        for (const group of groups) {
          for (const district of (group.stores || [])) {
            for (const store of (district.stores || [])) {
              if (store.stores) {
                for (const nested of store.stores) stores.push(nested);
              } else {
                stores.push(store);
              }
            }
          }
        }
        const storeCandidates = stores
          .map(s => ({
            raw: s,
            id: String(s.id || s.managerId),
            name: s.name || s.shortName || '一嗨门店',
            address: s.address || s.pickupAddress || '',
            lat: num(s.amapPickupLatitude) || num(s.pickupLatitude),
            lng: num(s.amapPickupLongitude) || num(s.pickupLongitude),
            hours: ((s.fromTime || '').slice(11,16) || '以平台为准') + '-' + ((s.toTime || '').slice(11,16) || '')
          }))
          .filter(s => Number.isFinite(s.lat) && Number.isFinite(s.lng))
          .map(s => ({ ...s, distanceKm: distanceKm(origin, { lat: s.lat, lng: s.lng }) }))
          .sort((a, b) => a.distanceKm - b.distanceKm);
        const candidates = hasVehicleQuery ? storeCandidates.filter(s => s.distanceKm <= request.radiusKm) : storeCandidates.slice(0, 1);
        if (!candidates.length) {
          return JSON.stringify({ statusKind: 'unavailable', message: '一嗨在当前范围内没有可用取车点。', sourceUrl, listings: [] });
        }
        const listingsByKey = {};
        for (const store of candidates) {
          const payload = {
            stockType: 1,
            whereFilter: null,
            pickupDto: { cityId: city.cityId, storeId: Number(store.id), operationTime: toTime(request.pickupAt), isService: false },
            pickupAddressDto: null,
            returnDto: { cityId: city.cityId, storeId: Number(store.id), operationTime: toTime(request.returnAt), isService: false },
            returnAddressDto: null,
            requestContext: {
              platform: util.getGD('platform'),
              platformSource: null,
              operatorId: null,
              userId: null,
              channelId: null,
              enterpriseId: null,
              optionTag: { isRecalculation: false, isChargeFee: false, choose: 3, isEnterprise: true, moduleIds: null }
            }
          };
          try {
            const verifyResp = await http.postEncrypt('/Verify/Step1', '', payload);
            const verify = verifyResp.data || verifyResp;
            if (!verify.isSuccess) continue;
            const stockResp = await http.postEncrypt('/Stock/Step2', '', payload);
            if (stockResp.code === 401 || stockResp.status === 401) {
              return JSON.stringify({
                statusKind: 'login-required',
                message: `一嗨城市和门店 API 可匿名读取，但库存报价 /Stock/Step2 返回 401；请登录一嗨后重试。已识别 ${stores.length} 个门店。`,
                sourceUrl,
                listings: []
              });
            }
            const result = (stockResp.data && stockResp.data.result) || stockResp.result || {};
            const cars = (result.bookingAvailableCarTypes || []).concat(result.unAvailableCarTypes || []);
            for (const item of cars) {
              const car = item.carType || item;
              const daily = num(item.baseAvgAmount) || num(item.avgAmount) || num(item.baseAmount) || num(item.price);
              if (!daily || !car.name) continue;
              const key = `${store.id}-${car.name}`;
              const listing = {
                id: `ehi-${store.id}-${car.id || car.carTypeId || car.name}`,
                storeId: store.id,
                storeName: store.name,
                city: city.city,
                address: store.address,
                lat: store.lat,
                lng: store.lng,
                distanceKm: store.distanceKm,
                hours: store.hours,
                vehicleName: car.name,
                vehicleClass: [car.gearName, car.structureName, car.maxPassenger ? `${car.maxPassenger}座` : ''].filter(Boolean).join(' | '),
                basePrice: daily * days,
                platformFees: 0,
                insuranceFees: 0,
                oneWayFee: 0,
                sourceUrl,
                dataCompleteness: 0.88
              };
              if (!listingsByKey[key] || listingsByKey[key].basePrice > listing.basePrice) listingsByKey[key] = listing;
            }
          } catch (error) {
            if (String(error && error.message || '').includes('401')) {
              return JSON.stringify({ statusKind: 'login-required', message: '一嗨库存报价接口返回 401，请登录一嗨后重试。', sourceUrl, listings: [] });
            }
          }
        }
        const listings = Object.values(listingsByKey);
        return JSON.stringify({
          statusKind: listings.length ? 'ready' : 'unavailable',
          message: listings.length ? `已从一嗨 API 读取 ${listings.length} 个真实候选车型。` : '一嗨真实接口返回成功，但当前条件没有可订车型。',
          sourceUrl,
          listings
        });
        """
    }
}

// MARK: - Shared Models

private struct ZucheResponse<Content: Decodable>: Decodable {
    let code: Int?
    let status: String?
    let msg: String?
    let content: Content?
}

private struct ZucheCityListContent: Decodable {
    let allCities: [ZucheCity]
}

private struct ZucheCity: Decodable {
    let cityId: String
    let cityName: String
    let cityLat: String?
    let cityLon: String?

    var location: GeoPoint? {
        guard let lat = Double(cityLat ?? ""), let lng = Double(cityLon ?? "") else { return nil }
        return GeoPoint(lat: lat, lng: lng)
    }
}

private struct ZucheDeptListContent: Decodable {
    let districtList: [ZucheDistrict]
}

private struct ZucheDistrict: Decodable {
    let deptList: [ZucheDept]
}

private struct ZucheDept: Decodable {
    let deptName: String
    let deptAddress: String
    let deptLon: String
    let deptLat: String
    let workTime: String
    let deptId: Int
    let inventoryAbleFlag: Bool?

    var location: GeoPoint? {
        guard let lat = Double(deptLat), let lng = Double(deptLon) else { return nil }
        return GeoPoint(lat: lat, lng: lng)
    }
}

private struct ZucheChooseCarContent: Decodable {
    let deptHangModels: [ZucheDeptModels]
}

private struct ZucheDeptModels: Decodable {
    let deptName: String
    let lon: String
    let lat: String
    let deptAddress: String
    let workTime: String
    let deptId: Int
    let models: [ZucheModel]

    var location: GeoPoint? {
        guard let lat = Double(lat), let lng = Double(lon) else { return nil }
        return GeoPoint(lat: lat, lng: lng)
    }
}

private struct ZucheModel: Decodable {
    let packagePrice: String?
    let lowPrice: Double?
    let modelId: Int
    let havePriceFlag: Bool?
    let modelName: String
    let modelDesc: String
    let bookFlag: Bool?

    var price: Double? {
        lowPrice ?? Double(packagePrice ?? "")
    }
}

private struct EhiBridgeRequest: Encodable {
    let origin: GeoPoint
    let originLabel: String
    let pickupAt: String
    let returnAt: String
    let radiusKm: Double
    let vehicleQuery: String

    init(request: SearchRequest) {
        origin = request.origin
        originLabel = request.originLabel
        pickupAt = request.pickupAt
        returnAt = request.returnAt
        radiusKm = request.radiusKm
        vehicleQuery = request.vehicleQuery
    }
}

private struct EhiBridgeResponse: Decodable {
    let statusKind: String
    let message: String
    let sourceUrl: String
    let listings: [EhiBridgeListing]
}

private struct EhiBridgeListing: Decodable {
    let id: String
    let storeId: String
    let storeName: String
    let city: String
    let address: String
    let lat: Double
    let lng: Double
    let distanceKm: Double
    let hours: String
    let vehicleName: String
    let vehicleClass: String
    let basePrice: Double
    let platformFees: Double
    let insuranceFees: Double
    let oneWayFee: Double
    let sourceUrl: String
    let dataCompleteness: Double

    func domainListing(request: SearchRequest) -> RentalListing {
        let store = Store(
            id: storeId,
            platform: .ehi,
            name: storeName,
            city: city,
            address: address,
            location: GeoPoint(lat: lat, lng: lng),
            distanceKm: distanceKm,
            hours: hours
        )
        return RentalListing(
            id: id,
            platform: .ehi,
            store: store,
            vehicleName: vehicleName,
            vehicleClass: vehicleClass,
            basePrice: basePrice,
            platformFees: platformFees,
            insuranceFees: insuranceFees,
            oneWayFee: oneWayFee,
            sourceUrl: sourceUrl,
            dataCompleteness: dataCompleteness,
            warnings: [.partialPrice]
        )
    }
}

private enum PlatformAPIError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message):
            return message
        }
    }
}

private func platformDateTime(_ date: String) -> String {
    date.contains(" ") ? date : "\(date) 10:00"
}

private func rentalDays(_ request: SearchRequest) -> Int {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
    guard let pickup = formatter.date(from: request.pickupAt),
          let returnDate = formatter.date(from: request.returnAt)
    else { return 1 }
    let days = Calendar(identifier: .gregorian).dateComponents([.day], from: pickup, to: returnDate).day ?? 1
    return max(1, days)
}
