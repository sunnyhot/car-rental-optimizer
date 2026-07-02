import Foundation

enum ZucheLoginSession {
    static let officialLoginURL = URL(string: "https://passport.zuche.com/memberManage/xtoploginMember.do?act=loginSys")!
    static let loginURL = officialLoginURL
    static let desktopUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
}
