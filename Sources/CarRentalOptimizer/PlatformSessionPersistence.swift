import Foundation
import WebKit

/// One persistent WebKit cookie store is the authority for both login pages and
/// authenticated quote requests. Restore once, then persist rotations, not old snapshots.
@MainActor
final class PlatformSessionPersistence: NSObject, WKHTTPCookieStoreObserver {
    static let shared = PlatformSessionPersistence(store: WKWebsiteDataStore.default().httpCookieStore)
    private let store: WKHTTPCookieStore
    private let ehiFile: URL
    private let zucheFile: URL
    private var initialization: Task<Void, Never>?
    private var started = false
    private var dirty = false
    private var saving = false
    private var waiters: [CheckedContinuation<Bool, Never>] = []
    private(set) var saveRevision = 0
    private(set) var lastSaveSucceeded: Bool?

    init(store: WKHTTPCookieStore, ehiFile: URL = EhiCookieVault.defaultCookieFileURL, zucheFile: URL = ZucheCookieVault.defaultCookieFileURL) {
        self.store = store
        self.ehiFile = ehiFile
        self.zucheFile = zucheFile
    }

    func start() async {
        if started { return }
        if let initialization { await initialization.value; return }
        let task = Task { @MainActor in
            await EhiCookieVault.restore(into: store, fileURL: ehiFile)
            await ZucheCookieVault.restore(into: store, fileURL: zucheFile)
            store.add(self)
            started = true
            _ = await flush()
        }
        initialization = task
        await task.value
        initialization = nil
    }

    nonisolated func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        Task { @MainActor [weak self] in _ = await self?.flush() }
    }

    @discardableResult
    func flush() async -> Bool {
        if !started {
            if let initialization { await initialization.value }
            guard started else { return true }
        }
        return await withCheckedContinuation { continuation in
            dirty = true
            waiters.append(continuation)
            guard !saving else { return }
            saving = true
            Task { @MainActor in
                var succeeded = true
                while dirty {
                    dirty = false
                    let ehi = await EhiCookieVault.save(from: store, fileURL: ehiFile, allowEmpty: true)
                    let zuche = await ZucheCookieVault.save(from: store, fileURL: zucheFile, allowEmpty: true)
                    succeeded = succeeded && ehi && zuche
                }
                lastSaveSucceeded = succeeded
                saveRevision += 1
                let completed = waiters
                waiters = []
                saving = false
                for waiter in completed { waiter.resume(returning: succeeded) }
            }
        }
    }

    func applyAuthenticatedResponseCookies(_ cookies: [HTTPCookie], for url: URL) async {
        await start()
        let current = await withCheckedContinuation { continuation in store.getAllCookies { continuation.resume(returning: $0) } }
        var changed = false
        for cookie in cookies where ZucheCookieVault.isZucheCookie(cookie) && cookieMatchesRequest(cookie, url: url, checkExpiration: false, checkPath: false) {
            if let expiry = cookie.expiresDate, expiry <= Date() {
                for existing in current where cookieIdentity(existing) == cookieIdentity(cookie) {
                    await withCheckedContinuation { continuation in store.delete(existing) { continuation.resume() } }
                    changed = true
                }
            } else {
                await withCheckedContinuation { continuation in store.setCookie(cookie) { continuation.resume() } }
                changed = true
            }
        }
        if changed { _ = await flush() }
    }

    func stop() {
        if started { store.remove(self) }
        started = false
    }
}
