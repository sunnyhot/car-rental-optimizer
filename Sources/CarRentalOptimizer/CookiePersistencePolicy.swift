import Foundation

func cookieIdentity(_ cookie: HTTPCookie) -> String {
    "\(cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased())|\(cookie.path)|\(cookie.name)"
}

func missingSessionCookies(saved: [HTTPCookie], current: [HTTPCookie], now: Date = Date()) -> [HTTPCookie] {
    let existing = Set(current.filter { $0.expiresDate.map { $0 > now } ?? true }.map(cookieIdentity))
    return saved.filter { ($0.expiresDate.map { $0 > now } ?? true) && !existing.contains(cookieIdentity($0)) }
}

func cookieMatchesRequest(_ cookie: HTTPCookie, url: URL, now: Date = Date(), checkExpiration: Bool = true, checkPath: Bool = true) -> Bool {
    guard let host = url.host?.lowercased() else { return false }
    let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
    guard host == domain || (cookie.domain.hasPrefix(".") && host.hasSuffix("." + domain)) else { return false }
    if cookie.isSecure && url.scheme?.lowercased() != "https" { return false }
    if checkExpiration, let expiry = cookie.expiresDate, expiry <= now { return false }
    if !checkPath { return true }
    let path = url.path.isEmpty ? "/" : url.path
    let cookiePath = cookie.path.isEmpty ? "/" : cookie.path
    return path == cookiePath || path.hasPrefix(cookiePath.hasSuffix("/") ? cookiePath : cookiePath + "/")
}

func cookiesForRequest(_ cookies: [HTTPCookie], url: URL, now: Date = Date()) -> [HTTPCookie] {
    cookies.filter { cookieMatchesRequest($0, url: url, now: now) }.sorted {
        if $0.path.count != $1.path.count { return $0.path.count > $1.path.count }
        return $0.domain.count > $1.domain.count
    }
}
