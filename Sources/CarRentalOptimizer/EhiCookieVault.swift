import Foundation
import WebKit

struct PersistedEhiCookie: Codable, Equatable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let expiresDate: Date?
    let isSecure: Bool
    let isHTTPOnly: Bool

    init?(cookie: HTTPCookie, now: Date = Date()) {
        guard EhiCookieVault.isEhiCookie(cookie) else { return nil }
        if let expiresDate = cookie.expiresDate, expiresDate <= now {
            return nil
        }

        name = cookie.name
        value = cookie.value
        domain = cookie.domain
        path = cookie.path.isEmpty ? "/" : cookie.path
        expiresDate = cookie.expiresDate
        isSecure = cookie.isSecure
        isHTTPOnly = cookie.isHTTPOnly
    }

    func httpCookie(now: Date = Date()) -> HTTPCookie? {
        if let expiresDate, expiresDate <= now {
            return nil
        }

        var properties: [HTTPCookiePropertyKey: Any] = [
            .domain: domain,
            .path: path,
            .name: name,
            .value: value
        ]
        if let expiresDate {
            properties[.expires] = expiresDate
        }
        if isSecure {
            properties[.secure] = "TRUE"
        }
        if isHTTPOnly {
            properties[.httpOnlyAttribute] = "TRUE"
        }
        return HTTPCookie(properties: properties)
    }
}

enum EhiCookieVault {
    private static let directoryName = "CarRentalOptimizer"
    private static let fileName = "ehi-session-cookies.json"

    static var defaultCookieFileURL: URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return baseURL
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(fileName)
    }

    static func isEhiCookie(_ cookie: HTTPCookie) -> Bool {
        let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        return domain == "1hai.cn" || domain.hasSuffix(".1hai.cn")
    }

    static func persistableCookies(from cookies: [HTTPCookie], now: Date = Date()) -> [PersistedEhiCookie] {
        cookies
            .compactMap { PersistedEhiCookie(cookie: $0, now: now) }
            .sorted { lhs, rhs in
                if lhs.domain != rhs.domain { return lhs.domain < rhs.domain }
                if lhs.path != rhs.path { return lhs.path < rhs.path }
                return lhs.name < rhs.name
            }
    }

    static func restoredCookies(from cookies: [PersistedEhiCookie], now: Date = Date()) -> [HTTPCookie] {
        cookies.compactMap { $0.httpCookie(now: now) }
    }

    static func discardSavedSession(fileURL: URL = defaultCookieFileURL) {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }

    @MainActor
    static func restore(into store: WKHTTPCookieStore, fileURL: URL = defaultCookieFileURL) async {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard let persisted = try? JSONDecoder().decode([PersistedEhiCookie].self, from: data) else { return }

        for cookie in restoredCookies(from: persisted) {
            await store.setCookieAsync(cookie)
        }
    }

    @MainActor
    static func save(from store: WKHTTPCookieStore, fileURL: URL = defaultCookieFileURL) async {
        let cookies = await store.allCookiesAsync()
        let persisted = persistableCookies(from: cookies)
        guard !persisted.isEmpty else { return }

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(persisted)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            assertionFailure("Failed to persist eHi cookies: \(error.localizedDescription)")
        }
    }
}

private extension WKHTTPCookieStore {
    func allCookiesAsync() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }

    func setCookieAsync(_ cookie: HTTPCookie) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            setCookie(cookie) {
                continuation.resume()
            }
        }
    }
}

private extension HTTPCookiePropertyKey {
    static let httpOnlyAttribute = HTTPCookiePropertyKey("HttpOnly")
}
