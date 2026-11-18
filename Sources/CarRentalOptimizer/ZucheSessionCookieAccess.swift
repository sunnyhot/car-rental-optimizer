import Foundation

/// Explicit test seam: synthetic cookie access must replace both reading and writing,
/// so gateway regression tests never reach the real WebKit store or session files.
struct ZucheSessionCookieAccess {
    let header: (URL) async -> String?
    let accept: ([HTTPCookie], URL) async -> Void
}

func canAdoptZucheSessionCookies(httpStatus: Int, code: Int?, status: String?) -> Bool {
    let normalizedStatus = status?.uppercased()
    guard (200..<300).contains(httpStatus), code != 5, normalizedStatus != "NOT_LOGIN" else { return false }
    return code == 1 || normalizedStatus == "SUCCESS"
}


/// Authentication metadata is independent of the quote payload's schema.
struct ZucheSessionResponseMetadata: Decodable {
    let code: Int?
    let status: String?
    let contentStatus: Int?
    private enum CodingKeys: String, CodingKey { case code, status, content }
    private enum ContentKeys: String, CodingKey { case status }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        code = try? values.decode(Int.self, forKey: .code)
        status = try? values.decode(String.self, forKey: .status)
        if let content = try? values.nestedContainer(keyedBy: ContentKeys.self, forKey: .content) {
            contentStatus = try? content.decode(Int.self, forKey: .status)
        } else { contentStatus = nil }
    }
}
