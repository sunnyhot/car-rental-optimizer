import CarRentalDomain
import Foundation
import JavaScriptCore
import Testing
@testable import CarRentalOptimizer

@Suite("Live rental search service")
struct LiveRentalSearchServiceTests {
    @Test("Date-only pickup today uses a future platform time and keeps return hour aligned")
    func dateOnlyPickupTodayUsesFuturePlatformTime() {
        let now = date("2026-06-03 15:45")

        let range = platformQueryTimeRange(
            pickupDate: "2026-06-03",
            returnDate: "2026-06-04",
            now: now
        )

        #expect(range.pickupTime == "2026-06-03 18:00")
        #expect(range.returnTime == "2026-06-04 18:00")
    }

    @Test("Future date-only pickup keeps the standard platform hour")
    func futureDateOnlyPickupKeepsStandardPlatformHour() {
        let now = date("2026-06-03 15:45")

        let range = platformQueryTimeRange(
            pickupDate: "2026-06-05",
            returnDate: "2026-06-06",
            now: now
        )

        #expect(range.pickupTime == "2026-06-05 10:00")
        #expect(range.returnTime == "2026-06-06 10:00")
    }

    @Test("Explicit platform times are preserved")
    func explicitPlatformTimesArePreserved() {
        let now = date("2026-06-03 15:45")

        let range = platformQueryTimeRange(
            pickupDate: "2026-06-03 19:30",
            returnDate: "2026-06-04 20:30",
            now: now
        )

        #expect(range.pickupTime == "2026-06-03 19:30")
        #expect(range.returnTime == "2026-06-04 20:30")
    }

    @Test("eHi bridge decodes obfuscated price digits used by official stock API")
    func ehiBridgeDecodesObfuscatedPriceDigits() {
        let script = makeEhiSearchScript(json: "{}")

        #expect(script.contains("charCodeAt(0)"))
        #expect(script.contains("57345"))
        #expect(script.contains("57354"))
        #expect(script.contains("code - 57345"))
    }

    @Test("eHi stock quote tries personal anonymous payload before login fallback")
    func ehiStockQuoteTriesPersonalAnonymousPayloadBeforeLoginFallback() {
        let script = makeEhiSearchScript(json: "{}")

        #expect(script.contains("const stockPayloads = ["))
        #expect(script.contains("label: '个人匿名'"))
        #expect(script.contains("label: '默认上下文'"))
        #expect(script.contains("isEnterprise: false"))
        #expect(script.contains("isEnterprise: true"))
        #expect(script.contains("stock401Count += quoteResult.stock401Count || 0"))
        #expect(!script.contains("quote401Labels.length === attemptedQuoteCount"))
    }

    @Test("eHi stock 401 only requests login after all stock attempts are rejected")
    func ehiStock401OnlyRequestsLoginAfterAllStockAttemptsAreRejected() {
        let script = makeEhiSearchScript(json: "{}")

        #expect(script.contains("const stock401SkipMessage = (store, label) =>"))
        #expect(script.contains("let stockAttemptCount = 0"))
        #expect(script.contains("let stock401Count = 0"))
        #expect(script.contains("storeStock401Count += 1"))
        #expect(script.contains("if (!listings.length && stockAttemptCount > 0 && stock401Count === stockAttemptCount)"))
        #expect(script.contains("一嗨库存报价 /Stock/Step2 均返回 401"))
        #expect(script.contains("请先登录一嗨后重试"))
        #expect(script.contains("if (code === 401) {"))
        #expect(script.contains("if (message.includes('401')) {"))
        #expect(!script.contains("loginRequiredFromStock401"))
        #expect(!script.contains("return { loginRequired:"))
        #expect(!script.contains("quote401Labels.push(label)"))
    }

    @Test("Platform timeout returns a typed failure instead of waiting forever")
    func platformTimeoutReturnsTypedFailureInsteadOfWaitingForever() async {
        let result = await platformResultWithTimeout(
            platform: .ehi,
            timeoutSeconds: 0.01
        ) {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            return PlatformEvidenceResult(
                platform: .ehi,
                status: PlatformEvidenceStatus(platform: .ehi, kind: .ready, message: "不应采用取消后的结果。", sourceUrl: "https://booking.1hai.cn/"),
                listings: []
            )
        }

        #expect(result.platform == .ehi)
        #expect(result.status.kind == .parseFailed)
        #expect(result.status.message.contains("超时"))
        #expect(result.listings.isEmpty)
    }

    @Test("eHi obfuscated price digits convert to usable numeric prices")
    func ehiObfuscatedPriceDigitsConvertToUsableNumericPrices() throws {
        let context = try #require(JSContext())
        let decodedPrice = context.evaluateScript(
            """
            const decodeObfuscatedDigits = (value) => String(value).split('').map(ch => {
              const code = ch.charCodeAt(0);
              return code >= 57345 && code <= 57354 ? String(code - 57345) : ch;
            }).join('');
            const num = (value) => {
              if (value === null || value === undefined || value === '') return null;
              const n = Number(decodeObfuscatedDigits(value).replace(/[^0-9.]/g, ''));
              return Number.isFinite(n) ? n : null;
            };
            num('\u{E002}\u{E003}\u{E004}.5');
            """
        )

        #expect(decodedPrice?.toDouble() == 123.5)
    }

    @Test("eHi blank vehicle query probes stores inside radius before reporting no cars")
    func ehiBlankVehicleQueryProbesStoresInsideRadiusBeforeReportingNoCars() {
        let script = makeEhiSearchScript(json: "{}")

        #expect(script.contains("blankStoreProbeLimit = 40"))
        #expect(script.contains("const blankStoreCandidates = storeCandidates.filter(s => s.distanceKm <= request.radiusKm)"))
        #expect(script.contains(": blankStoreCandidates.slice(0, blankStoreProbeLimit)"))
        #expect(script.contains("selectedBlankStoreId"))
        #expect(script.contains("!hasVehicleQuery && selectedBlankStoreId && store.id !== selectedBlankStoreId"))
        #expect(script.contains("半径 ${Math.round(request.radiusKm)}km"))
        #expect(!script.contains(": storeCandidates.slice(0, nearestStoreProbeLimit)"))
    }

    @Test("eHi specific vehicle query limits store probes to avoid bridge timeout")
    func ehiSpecificVehicleQueryLimitsStoreProbesToAvoidBridgeTimeout() {
        let script = makeEhiSearchScript(json: "{}")

        #expect(script.contains("const ehiCandidateCities ="))
        #expect(script.contains("const selectedStoreForCity = (cityPlan, cityStores) =>"))
        #expect(script.contains("isRailwayStationStore"))
        #expect(script.contains("cityPlan.isCurrentCity ? sortedStores[0]"))
        #expect(script.contains("每个城市最多探测 1 个候选门店"))
        #expect(!script.contains("vehicleStoreProbeLimit = 12"))
        #expect(!script.contains("storesInsideRadius.slice(0, vehicleStoreProbeLimit)"))
    }

    @Test("eHi vehicle query probes cities and stock quotes with bounded concurrency")
    func ehiVehicleQueryProbesCitiesAndStockQuotesWithBoundedConcurrency() {
        let script = makeEhiSearchScript(json: "{}")

        #expect(script.contains("const ehiProbeConcurrency = 3"))
        #expect(script.contains("const mapWithConcurrency = async (items, limit, worker) =>"))
        #expect(script.contains("const cityFetchResults = await mapWithConcurrency(storeCityPlans, ehiProbeConcurrency, fetchStoresForCity)"))
        #expect(script.contains("const quoteStore = async (store) =>"))
        #expect(script.contains("const quoteResults = hasVehicleQuery"))
        #expect(script.contains("? await mapWithConcurrency(candidates, ehiProbeConcurrency, quoteStore)"))
        #expect(!script.contains("for (const cityPlan of storeCityPlans) {"))
    }

    @Test("eHi bridge API calls have an in-page timeout")
    func ehiBridgeAPICallsHaveInPageTimeout() {
        let script = makeEhiSearchScript(json: "{}")

        #expect(script.contains("apiTimeoutMs = 6000"))
        #expect(script.contains("withAPITimeout"))
        #expect(script.contains("withAPITimeout(http.getEncrypt('/Address/City/List'"))
        #expect(script.contains("withAPITimeout(http.postEncrypt('/Verify/Step1'"))
        #expect(script.contains("withAPITimeout(http.postEncrypt('/Stock/Step2'"))
    }

    @Test("eHi bridge guards empty verify and stock responses")
    func ehiBridgeGuardsEmptyVerifyAndStockResponses() {
        let script = makeEhiSearchScript(json: "{}")

        #expect(script.contains("const hasResponseBody = (value) =>"))
        #expect(script.contains("const verify = responseBody(verifyResp)"))
        #expect(script.contains("校验接口没有返回内容"))
        #expect(script.contains("const code = stockResp?.code"))
        #expect(script.contains("报价接口没有返回内容"))
        #expect(!script.contains("verifyResp.data || verifyResp"))
        #expect(!script.contains("stockResp.code ?? stockResp.status"))
    }

    @Test("eHi store-level empty responses are skipped instead of failing the whole platform")
    func ehiStoreLevelEmptyResponsesAreSkippedInsteadOfFailingTheWholePlatform() {
        let script = makeEhiSearchScript(json: "{}")

        #expect(script.contains("const storeSkips = []"))
        #expect(script.contains("storeSkips.push(`${store.name} ${label}: 校验接口没有返回内容`)"))
        #expect(script.contains("storeSkips.push(`${store.name} ${label}: 报价接口没有返回内容`)"))
        #expect(script.contains("storeSkips.push(`${store.name} ${label}: ${message}`)"))
        #expect(script.contains("候选门店暂不可报价"))
        #expect(!script.contains("queryErrors.push(`${store.name} ${label}: 校验接口没有返回内容`)"))
        #expect(!script.contains("queryErrors.push(`${store.name} ${label}: 报价接口没有返回内容`)"))
        #expect(!script.contains("queryErrors.push(`${store.name} ${label}: ${message}`)"))
    }

    @Test("eHi city matching recognizes English Beijing address from Apple location")
    func ehiCityMatchingRecognizesEnglishBeijingAddressFromAppleLocation() {
        let candidates = originCityCandidates(
            from: """
            Jingdong Group Quanqiu Headquarters Beijing No.2Park
            Beijing Tongzhou Beijing Economic and Technological Development Zone
            (Jinghai Road Subway Station West Entrance Exit A1 Pedestrian 120 Meters)
            """
        )
        let script = makeEhiSearchScript(json: "{}")

        #expect(candidates.contains("北京"))
        #expect(candidates.contains("通州"))
        #expect(script.contains("originCityCandidates"))
        #expect(script.contains("aliasMatchesCity"))
    }

    @Test("CAR Inc gateway prefers mobile host and keeps desktop fallback")
    func carIncGatewayPrefersMobileHostAndKeepsDesktopFallback() throws {
        let endpoints = zucheGatewayEndpoints(for: "/action/carrctapi/order/cityList/v1")

        #expect(endpoints.map { $0.url.host() } == ["m.zuche.com", "www.zuche.com"])
        #expect(endpoints.map(\.referer) == ["https://m.zuche.com/", "https://www.zuche.com/"])
        #expect(endpoints.allSatisfy { $0.url.absoluteString.contains("/api/gw.do?uri=/action/carrctapi/order/cityList/v1") })
    }

    @Test("CAR Inc gateway retries transport-level TLS and timeout errors on the alternate host")
    func carIncGatewayRetriesTransportLevelTLSAndTimeoutErrors() {
        #expect(isRetryableZucheTransportError(URLError(.secureConnectionFailed)))
        #expect(isRetryableZucheTransportError(URLError(.timedOut)))
        #expect(isRetryableZucheTransportError(URLError(.networkConnectionLost)))
        #expect(!isRetryableZucheTransportError(URLError(.userAuthenticationRequired)))
    }

    @Test("CAR Inc vehicle search plans one current city and one station city inside radius")
    func carIncVehicleSearchPlansOneCurrentCityAndOneStationCityInsideRadius() {
        let request = makeSearchRequest(
            originLabel: "北京市 通州区 京东总部",
            origin: GeoPoint(lat: 39.90, lng: 116.65),
            radiusKm: 160
        )
        let cities = [
            ZucheSearchCity(id: "beijing", name: "北京", location: GeoPoint(lat: 39.90, lng: 116.40)),
            ZucheSearchCity(id: "tianjin", name: "天津", location: GeoPoint(lat: 39.08, lng: 117.20)),
            ZucheSearchCity(id: "jinan", name: "济南", location: GeoPoint(lat: 36.65, lng: 117.12)),
        ]

        let candidates = zucheCandidateCities(from: cities, request: request)

        #expect(candidates.map(\.city.id) == ["beijing", "tianjin"])
        #expect(candidates.first?.isCurrentCity == true)
        #expect(candidates.dropFirst().allSatisfy { !$0.isCurrentCity })
    }

    @Test("CAR Inc vehicle search caps planned cities to avoid platform timeout")
    func carIncVehicleSearchCapsPlannedCitiesToAvoidPlatformTimeout() {
        let request = makeSearchRequest(
            originLabel: "北京市 通州区 京东总部",
            origin: GeoPoint(lat: 39.90, lng: 116.65),
            radiusKm: 500
        )
        let cities = [
            ZucheSearchCity(id: "beijing", name: "北京", location: GeoPoint(lat: 39.90, lng: 116.40)),
            ZucheSearchCity(id: "langfang", name: "廊坊", location: GeoPoint(lat: 39.54, lng: 116.68)),
            ZucheSearchCity(id: "tianjin", name: "天津", location: GeoPoint(lat: 39.08, lng: 117.20)),
            ZucheSearchCity(id: "baoding", name: "保定", location: GeoPoint(lat: 38.87, lng: 115.46)),
            ZucheSearchCity(id: "jinan", name: "济南", location: GeoPoint(lat: 36.65, lng: 117.12)),
            ZucheSearchCity(id: "qingdao", name: "青岛", location: GeoPoint(lat: 36.07, lng: 120.38)),
        ]

        let candidates = zucheCandidateCities(from: cities, request: request)
        let planned = plannedZucheCities(
            from: candidates,
            hasVehicleQuery: true,
            maxVehicleCityCount: 3
        )

        #expect(candidates.count > planned.count)
        #expect(planned.map(\.city.id) == ["beijing", "langfang", "tianjin"])
    }

    @Test("CAR Inc specific vehicle query filters listings before confirmation fee enrichment")
    func carIncSpecificVehicleQueryFiltersListingsBeforeConfirmationFeeEnrichment() {
        let listings = [
            makeListing(id: "tiggo8", storeId: "nearest", vehicleName: "奇瑞瑞虎8", distanceKm: 0.4),
            makeListing(id: "haval", storeId: "nearest", vehicleName: "哈弗H6", distanceKm: 0.4),
            makeListing(id: "lavida", storeId: "nearest", vehicleName: "大众朗逸", distanceKm: 0.4),
        ]

        let filtered = zucheListingsMatchingVehicleQuery(listings, vehicleQuery: "瑞虎8")

        #expect(filtered.map(\.id) == ["tiggo8"])
    }

    @Test("CAR Inc store picker uses nearest current store and station-only stores outside current city")
    func carIncStorePickerUsesNearestCurrentStoreAndStationOnlyStoresOutsideCurrentCity() throws {
        let current = zucheSelectedStore(
            from: [
                makeStore(id: "far-station", name: "北京南站店", city: "北京", distanceKm: 18),
                makeStore(id: "nearest", name: "北京通州万达店", city: "北京", distanceKm: 2),
            ],
            cityName: "北京",
            isCurrentCity: true
        )

        let other = zucheSelectedStore(
            from: [
                makeStore(id: "downtown", name: "天津和平路店", city: "天津", distanceKm: 115),
                makeStore(id: "station", name: "天津南站高铁店", city: "天津", distanceKm: 123),
                makeStore(id: "airport", name: "天津滨海机场店", city: "天津", distanceKm: 130),
            ],
            cityName: "天津",
            isCurrentCity: false
        )

        #expect(try #require(current).id == "nearest")
        #expect(try #require(other).id == "station")
        #expect(zucheSelectedStore(
            from: [makeStore(id: "downtown", name: "廊坊万达店", city: "廊坊", distanceKm: 70)],
            cityName: "廊坊",
            isCurrentCity: false
        ) == nil)
    }

    @Test("CAR Inc confirmation fee parser uses official base service fee and ignores preparation fee")
    func carIncConfirmationFeeParserUsesOfficialBaseServiceFeeAndIgnoresPreparationFee() throws {
        let json = """
        {
          "feeInfos": {
            "baseFeeInfo": [
              {"itemName": "车辆租赁及服务费", "itemPrice": "188"},
              {"itemName": "基础服务费", "itemDesc": "¥50*2天=¥100", "itemPrice": "100"},
              {"itemName": "车辆整备费", "itemPrice": "20"}
            ]
          },
          "bottomInfo": {"totalPrice": "308"}
        }
        """
        let content = try JSONDecoder().decode(ZucheConfirmOrderContent.self, from: Data(json.utf8))

        #expect(zucheActualBaseServiceFee(from: content) == 100)
    }

    @Test("CAR Inc confirmation fee parser accepts higher per-car service fee from official response")
    func carIncConfirmationFeeParserAcceptsHigherPerCarServiceFeeFromOfficialResponse() throws {
        let json = """
        {
          "feeInfos": {
            "baseFeeInfo": [
              {"itemName": "基础服务费", "itemDesc": "¥80*2天=¥160"}
            ]
          }
        }
        """
        let content = try JSONDecoder().decode(ZucheConfirmOrderContent.self, from: Data(json.utf8))

        #expect(zucheActualBaseServiceFee(from: content) == 160)
    }

    @Test("CAR Inc listings use logged-in confirmation data instead of hardcoded service fees")
    func carIncListingsUseLoggedInConfirmationDataInsteadOfHardcodedServiceFees() throws {
        let source = try liveRentalSearchServiceSource()

        #expect(source.contains("/action/carrctapi/order/confirmOrderInfo/v4"))
        #expect(source.contains("WKWebsiteDataStore.default().httpCookieStore"))
        #expect(source.contains("await ZucheCookieVault.restore(into: store)"))
        #expect(source.contains("zucheActualBaseServiceFee(from: content)"))
        #expect(!source.contains("estimatedZucheMandatoryFees"))
        #expect(!source.contains("zucheBaseServiceFeePerDay"))
    }

    @Test("Blank vehicle query keeps all vehicles from nearest priced store only")
    func blankVehicleQueryKeepsAllVehiclesFromNearestPricedStoreOnly() {
        let sparseNearest = StoreListingsBatch(
            distanceKm: 0.3,
            listings: [
                makeListing(id: "nearest-lavida", storeId: "nearest", vehicleName: "大众朗逸", basePrice: 175, distanceKm: 0.3),
                makeListing(id: "nearest-kruze", storeId: "nearest", vehicleName: "雪佛兰科鲁泽", basePrice: 178, distanceKm: 0.3),
            ]
        )
        let richerNearby = StoreListingsBatch(
            distanceKm: 4.7,
            listings: [
                makeListing(id: "nearby-lavida", storeId: "nearby", vehicleName: "大众朗逸", basePrice: 168, distanceKm: 4.7),
                makeListing(id: "nearby-camry", storeId: "nearby", vehicleName: "丰田凯美瑞", basePrice: 198, distanceKm: 4.7),
                makeListing(id: "nearby-a6", storeId: "nearby", vehicleName: "奥迪A6L", basePrice: 408, distanceKm: 4.7),
            ]
        )

        let selected = blankVehicleCandidateListings(from: [richerNearby, sparseNearest], minimumVehicleCount: 4)

        #expect(Set(selected.map(\.vehicleName)) == ["大众朗逸", "雪佛兰科鲁泽"])
        #expect(selected.first { $0.vehicleName == "大众朗逸" }?.id == "nearest-lavida")
    }
}

private func date(_ value: String) -> Date {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
    return formatter.date(from: value)!
}

private func makeListing(
    id: String,
    storeId: String,
    vehicleName: String = "大众朗逸",
    basePrice: Double = 100,
    distanceKm: Double
) -> RentalListing {
    RentalListing(
        id: id,
        platform: .carInc,
        store: Store(
            id: storeId,
            platform: .carInc,
            name: "\(storeId) store",
            city: "北京",
            address: "北京通州",
            location: GeoPoint(lat: 39.9 + distanceKm / 100, lng: 116.65),
            distanceKm: distanceKm,
            hours: "08:00-21:00"
        ),
        vehicleName: vehicleName,
        vehicleClass: "",
        basePrice: basePrice,
        platformFees: 0,
        insuranceFees: 0,
        oneWayFee: 0,
        sourceUrl: "https://m.zuche.com/",
        dataCompleteness: 0.88
    )
}

private func makeSearchRequest(
    originLabel: String,
    origin: GeoPoint,
    radiusKm: Double
) -> SearchRequest {
    SearchRequest(
        origin: origin,
        originLabel: originLabel,
        pickupAt: "2026-06-25",
        returnAt: "2026-06-26",
        returnMode: .sameStore,
        radiusKm: radiusKm,
        vehicleQuery: "瑞虎8",
        platforms: [.carInc]
    )
}

private func makeStore(
    id: String,
    name: String,
    city: String,
    distanceKm: Double
) -> Store {
    Store(
        id: id,
        platform: .carInc,
        name: name,
        city: city,
        address: name,
        location: GeoPoint(lat: 39.9 + distanceKm / 100, lng: 116.65),
        distanceKm: distanceKm,
        hours: "08:00-21:00"
    )
}

private func liveRentalSearchServiceSource() throws -> String {
    let testFile = URL(fileURLWithPath: #filePath)
    let repositoryRoot = testFile
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = repositoryRoot
        .appendingPathComponent("Sources/CarRentalOptimizer/LiveRentalSearchService.swift")
    return try String(contentsOf: sourceURL, encoding: .utf8)
}
