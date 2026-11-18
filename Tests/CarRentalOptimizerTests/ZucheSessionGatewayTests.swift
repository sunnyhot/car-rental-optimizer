import Foundation
import Testing
@testable import CarRentalOptimizer

@Suite("CAR Inc gateway session isolation")
struct ZucheSessionGatewayTests {
    @Test func rejectedMobileSessionMustNotPoisonDesktopFallback() async throws {
        let fixture = try GatewaySessionFixture { request in
            if request.url?.host == "m.zuche.com" {
                return .rejected(setting: "anonymous-fixture")
            }
            return request.value(forHTTPHeaderField: "Cookie")?.contains("authenticated-fixture") == true
                ? .success() : .rejected()
        }
        defer { fixture.close() }
        let response: ZucheResponse<GatewayProbeValue> = try await fixture.client.postGatewayForm(uri: fixture.uri, payload: [:], cookieHeader: "fixture-present")
        #expect(response.code == 1)
        #expect(response.content?.value == 1)
        #expect(await fixture.jar.currentValue == "authenticated-fixture")
        #expect(await fixture.jar.acceptedValues.isEmpty)
        #expect(await fixture.jar.sentValues == ["authenticated-fixture", "authenticated-fixture"])
    }

    @Test func rejectedHTTPStatusMustNotPoisonDesktopFallback() async throws {
        let fixture = try GatewaySessionFixture { request in
            if request.url?.host == "m.zuche.com" {
                let rejected = GatewayStubReply.rejected(setting: "anonymous-fixture")
                return GatewayStubReply(status: 401, headers: rejected.headers, body: rejected.body)
            }
            return request.value(forHTTPHeaderField: "Cookie")?.contains("authenticated-fixture") == true
                ? .success() : .rejected()
        }
        defer { fixture.close() }
        let response: ZucheResponse<GatewayProbeValue> = try await fixture.client.postGatewayForm(uri: fixture.uri, payload: [:], cookieHeader: "fixture-present")
        #expect(response.code == 1)
        #expect(await fixture.jar.currentValue == "authenticated-fixture")
    }

    @Test func expiredNestedStatusDoesNotOverwriteFallbackSession() async throws {
        let fixture = try GatewaySessionFixture { request in
            if request.url?.host == "m.zuche.com" {
                let headers = GatewayStubReply.rejected(setting: "anonymous-fixture").headers
                return GatewayStubReply(status: 200, headers: headers, body: #"{"code":1,"status":"SUCCESS","content":{"status":-910}}"#)
            }
            return request.value(forHTTPHeaderField: "Cookie")?.contains("authenticated-fixture") == true
                ? .success() : .rejected()
        }
        defer { fixture.close() }
        let response: ZucheResponse<GatewayProbeValue> = try await fixture.client.postGatewayForm(uri: fixture.uri, payload: [:], cookieHeader: "fixture-present")
        #expect(response.code == 1)
        #expect(await fixture.jar.currentValue == "authenticated-fixture")
    }

    @Test func aQuoteSchemaErrorDoesNotLoseAnAuthenticatedSessionRotation() async throws {
        let fixture = try GatewaySessionFixture { _ in
            GatewayStubReply(status: 200, headers: GatewayStubReply.success(setting: "rotated-fixture").headers, body: #"{"code":1,"status":"SUCCESS","content":{"unknownQuoteShape":true}}"#)
        }
        defer { fixture.close() }
        do {
            let _: ZucheResponse<GatewayProbeValue> = try await fixture.client.postGatewayForm(uri: fixture.uri, payload: [:], cookieHeader: "fixture-present")
            Issue.record("Unexpected quote shape must remain a parsing error")
        } catch {}
        #expect(await fixture.jar.currentValue == "rotated-fixture")
        #expect(await fixture.jar.acceptedValues == ["rotated-fixture"])
    }

    @Test func failedHTTPResponseCannotRewriteTheSession() async throws {
        let fixture = try GatewaySessionFixture { _ in
            GatewayStubReply(status: 500, headers: GatewayStubReply.rejected(setting: "anonymous-fixture").headers, body: "unavailable")
        }
        defer { fixture.close() }
        do {
            let _: ZucheResponse<GatewayProbeValue> = try await fixture.client.postGatewayForm(uri: fixture.uri, payload: [:], cookieHeader: "fixture-present")
            Issue.record("HTTP failure must not be reported as authenticated success")
        } catch {}
        #expect(await fixture.jar.currentValue == "authenticated-fixture")
        #expect(await fixture.jar.acceptedValues.isEmpty)
    }

    @Test func onlyUnambiguousSuccessfulResponsesCanRotateTheSession() {
        #expect(canAdoptZucheSessionCookies(httpStatus: 200, code: 1, status: "SUCCESS"))
        #expect(!canAdoptZucheSessionCookies(httpStatus: 200, code: 5, status: "SUCCESS"))
        #expect(!canAdoptZucheSessionCookies(httpStatus: 200, code: 1, status: "NOT_LOGIN"))
        #expect(!canAdoptZucheSessionCookies(httpStatus: 401, code: 1, status: "SUCCESS"))
        #expect(!canAdoptZucheSessionCookies(httpStatus: 500, code: nil, status: nil))
        #expect(!canAdoptZucheSessionCookies(httpStatus: 200, code: 2, status: "FAIL"))
    }

    @Test func successfulAuthenticatedResponseStillPersistsRotation() async throws {
        let fixture = try GatewaySessionFixture { _ in .success(setting: "rotated-fixture") }
        defer { fixture.close() }
        let response: ZucheResponse<GatewayProbeValue> = try await fixture.client.postGatewayForm(uri: fixture.uri, payload: [:], cookieHeader: "fixture-present")
        #expect(response.code == 1)
        #expect(await fixture.jar.currentValue == "rotated-fixture")
        #expect(await fixture.jar.acceptedValues == ["rotated-fixture"])
    }

    @Test func rejectingBothGatewaysMustStillReportNotLoggedIn() async throws {
        let fixture = try GatewaySessionFixture { _ in .rejected(setting: "anonymous-fixture") }
        defer { fixture.close() }
        let response: ZucheResponse<GatewayProbeValue> = try await fixture.client.postGatewayForm(uri: fixture.uri, payload: [:], cookieHeader: "fixture-present")
        #expect(response.code == 5)
        #expect(response.status == "NOT_LOGIN")
        #expect(response.content == nil)
        #expect(await fixture.jar.currentValue == "authenticated-fixture")
    }
}

private struct GatewayProbeValue: Decodable { let value: Int }

private struct GatewayStubReply {
    let status: Int
    let headers: [String: String]
    let body: String
    static func success(setting value: String? = nil) -> Self {
        Self(status: 200, headers: cookieHeader(value), body: #"{"code":1,"status":"SUCCESS","content":{"value":1}}"#)
    }
    static func rejected(setting value: String? = nil) -> Self {
        Self(status: 200, headers: cookieHeader(value), body: #"{"code":5,"status":"NOT_LOGIN","msg":"fixture rejection"}"#)
    }
    private static func cookieHeader(_ value: String?) -> [String: String] {
        value.map { ["Set-Cookie": "intranet-sessionid=\($0); Domain=.zuche.com; Path=/; Secure; HttpOnly"] } ?? [:]
    }
}

private actor GatewayFixtureCookieJar {
    private var cookie: HTTPCookie
    private(set) var acceptedValues: [String] = []
    private(set) var sentValues: [String] = []
    var currentValue: String { cookie.value }
    init() throws {
        cookie = try #require(HTTPCookie(properties: [.name: "intranet-sessionid", .value: "authenticated-fixture", .domain: ".zuche.com", .path: "/", .secure: "TRUE"]))
    }
    func header(for url: URL) -> String? {
        let applicable = cookiesForRequest([cookie], url: url)
        sentValues.append(contentsOf: applicable.map(\.value))
        return HTTPCookie.requestHeaderFields(with: applicable)["Cookie"]
    }
    func accept(_ updates: [HTTPCookie], from url: URL) {
        for update in updates where cookieIdentity(update) == cookieIdentity(cookie) {
            cookie = update
            acceptedValues.append(update.value)
        }
    }
}

private final class GatewayStubRegistry: @unchecked Sendable {
    static let shared = GatewayStubRegistry()
    private let lock = NSLock()
    private var handlers: [String: (URLRequest) -> GatewayStubReply] = [:]
    func put(_ uri: String, handler: @escaping (URLRequest) -> GatewayStubReply) {
        lock.lock(); defer { lock.unlock() }; handlers[uri] = handler
    }
    func remove(_ uri: String) { lock.lock(); defer { lock.unlock() }; handlers[uri] = nil }
    func get(_ uri: String) -> ((URLRequest) -> GatewayStubReply)? {
        lock.lock(); defer { lock.unlock() }; return handlers[uri]
    }
}

private final class GatewayStubProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url,
              let uri = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "uri" })?.value,
              let handler = GatewayStubRegistry.shared.get(uri) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL)); return
        }
        let reply = handler(request)
        guard let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: nil, headerFields: reply.headers) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private struct GatewaySessionFixture {
    let uri: String
    let jar: GatewayFixtureCookieJar
    let session: URLSession
    let client: ZucheAPIClient
    init(handler: @escaping (URLRequest) -> GatewayStubReply) throws {
        uri = "/fixture/session-" + UUID().uuidString
        let jar = try GatewayFixtureCookieJar()
        self.jar = jar
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GatewayStubProtocol.self]
        configuration.httpCookieStorage = nil
        session = URLSession(configuration: configuration)
        client = ZucheAPIClient(session: session, cookieAccess: ZucheSessionCookieAccess(
            header: { await jar.header(for: $0) },
            accept: { await jar.accept($0, from: $1) }
        ))
        GatewayStubRegistry.shared.put(uri, handler: handler)
    }
    func close() {
        session.invalidateAndCancel()
        GatewayStubRegistry.shared.remove(uri)
    }
}
