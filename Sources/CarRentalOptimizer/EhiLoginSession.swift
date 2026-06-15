import Foundation
import WebKit

enum EhiLoginSession {
    static let loginURL = URL(string: "https://booking.1hai.cn/order/firstStep")!
    static let didChangeNotification = Notification.Name("EhiLoginSessionDidChange")
    static let captchaValidationObserverMessageName = "ehiCaptchaValidationError"

    static func makeLoginRequest(now: Date = Date()) -> URLRequest {
        var request = URLRequest(
            url: freshLoginURL(now: now),
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 60
        )
        request.httpShouldHandleCookies = true
        return request
    }

    static func containsCaptchaValidationError(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.contains("验证码校验异常")
            || normalized.contains("请刷新页面后重试")
            || normalized.localizedCaseInsensitiveContains("captcha")
                && normalized.localizedCaseInsensitiveContains("refresh")
    }

    static func makeCaptchaValidationObserverScript(
        messageName: String = captchaValidationObserverMessageName
    ) -> WKUserScript {
        WKUserScript(
            source: captchaValidationObserverSource(messageName: messageName),
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
    }

    static func captchaValidationObserverSource(
        messageName: String = captchaValidationObserverMessageName
    ) -> String {
        """
        (() => {
          const messageName = \(javaScriptStringLiteral(messageName));
          const containsCaptchaValidationError = (value) => {
            const normalized = String(value || '').trim();
            const lowercased = normalized.toLowerCase();
            return normalized.includes('验证码校验异常')
              || normalized.includes('请刷新页面后重试')
              || (lowercased.includes('captcha') && lowercased.includes('refresh'));
          };
          let posted = false;
          const notifyIfNeeded = () => {
            if (posted) return;
            const text = document.body ? (document.body.innerText || document.body.textContent || '') : '';
            if (!containsCaptchaValidationError(text)) return;
            const handlers = window.webkit && window.webkit.messageHandlers;
            if (!handlers || !handlers[messageName]) return;
            posted = true;
            handlers[messageName].postMessage(String(text).trim());
          };
          const observeBody = () => {
            if (!document.body) return;
            notifyIfNeeded();
            if (window.__carRentalEhiCaptchaObserver) {
              window.__carRentalEhiCaptchaObserver.disconnect();
            }
            window.__carRentalEhiCaptchaObserver = new MutationObserver(notifyIfNeeded);
            window.__carRentalEhiCaptchaObserver.observe(document.body, {
              childList: true,
              subtree: true,
              characterData: true
            });
          };
          if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', observeBody, { once: true });
          } else {
            observeBody();
          }
        })();
        """
    }

    static func isEhiWebsiteDataRecordName(_ displayName: String) -> Bool {
        let lowercased = displayName.lowercased()
        return lowercased.contains("1hai.cn")
            || lowercased.contains("1hai")
            || lowercased.contains("ehicar")
    }

    static func resetLoginChallengeData(
        dataStore: WKWebsiteDataStore = .default(),
        completion: @escaping () -> Void
    ) {
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        let finishAfterCookieCleanup = {
            deleteEhiCookies(from: dataStore.httpCookieStore, completion: completion)
        }

        dataStore.fetchDataRecords(ofTypes: dataTypes) { records in
            let ehiRecords = records.filter { isEhiWebsiteDataRecordName($0.displayName) }
            guard !ehiRecords.isEmpty else {
                finishAfterCookieCleanup()
                return
            }
            dataStore.removeData(ofTypes: dataTypes, for: ehiRecords) {
                finishAfterCookieCleanup()
            }
        }
    }

    static func notifyDidChange(center: NotificationCenter = .default) {
        center.post(name: didChangeNotification, object: nil)
    }

    private static func freshLoginURL(now: Date) -> URL {
        var components = URLComponents(url: loginURL, resolvingAgainstBaseURL: false)
        var queryItems = components?.queryItems ?? []
        queryItems.removeAll { $0.name == "_loginRefresh" }
        queryItems.append(URLQueryItem(name: "_loginRefresh", value: "\(Int(now.timeIntervalSince1970 * 1000))"))
        components?.queryItems = queryItems
        return components?.url ?? loginURL
    }

    private static func javaScriptStringLiteral(_ value: String) -> String {
        guard
            let data = try? JSONEncoder().encode(value),
            let encoded = String(data: data, encoding: .utf8)
        else {
            return "\"\""
        }
        return encoded
    }

    private static func deleteEhiCookies(from store: WKHTTPCookieStore, completion: @escaping () -> Void) {
        store.getAllCookies { cookies in
            let ehiCookies = cookies.filter(EhiCookieVault.isEhiCookie)
            guard !ehiCookies.isEmpty else {
                DispatchQueue.main.async(execute: completion)
                return
            }

            let group = DispatchGroup()
            for cookie in ehiCookies {
                group.enter()
                store.delete(cookie) {
                    group.leave()
                }
            }
            group.notify(queue: .main, execute: completion)
        }
    }
}
