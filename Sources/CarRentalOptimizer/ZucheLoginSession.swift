import Foundation

enum ZucheLoginSession {
    static let officialLoginURL = URL(string: "https://passport.zuche.com/memberManage/xtoploginMember.do?act=loginSys")!
    static let smsLoginURL = URL(string: "https://m.zuche.com/html5/version652/user/login.html")!
    static let passwordLoginURL = URL(string: "https://m.zuche.com/html5/newversion/user/login.html")!
    static let loginURL = officialLoginURL
    static let desktopUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    static let mobileUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1"
}

enum ZucheLoginMode: String, CaseIterable, Identifiable, Equatable {
    case official
    case sms
    case password

    var id: String { rawValue }

    var title: String {
        switch self {
        case .official:
            return "官网登录"
        case .sms:
            return "短信登录"
        case .password:
            return "密码登录"
        }
    }

    var url: URL {
        switch self {
        case .official:
            return ZucheLoginSession.officialLoginURL
        case .sms:
            return ZucheLoginSession.smsLoginURL
        case .password:
            return ZucheLoginSession.passwordLoginURL
        }
    }

    var userAgent: String {
        switch self {
        case .official:
            return ZucheLoginSession.desktopUserAgent
        case .sms, .password:
            return ZucheLoginSession.mobileUserAgent
        }
    }
}
