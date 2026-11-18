import Foundation
import WebKit

/// One persistent WebKit cookie store is the authority for both login pages and
/// authenticated quote requests. Restore once, then persist rotations, not old snapshots.
@MainActor
final class PlatformSessionPersistence: NSObject, WKHTTPCookieStoreObserver {
    static let shared = PlatformSessionPersistence(store: WKWebsiteDataStore.default().httpCookieStore)

    private struct CookieSnapshot: Equatable {
        let ehi: [PersistedEhiCookie]
        let zuche: [PersistedZucheCookie]
    }

    private let store: WKHTTPCookieStore
    private let ehiFile: URL
    private let zucheFile: URL
    private var initialization: Task<Void, Never>?
    private var reconciliationTask: Task<Void, Never>?
    private var lastSavedCookieSnapshot: CookieSnapshot?
    private var reconciliationFailureCount = 0
    private var reconciliationRetryDate: Date?
    private var lastReconciliationFailureRevision: Int?
    private var reconciliationGeneration = 0
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
            if started { startCookieReconciliation() }
        }
        initialization = task
        await task.value
        initialization = nil
    }

    nonisolated func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        Task { @MainActor [weak self] in await self?.reconcileCookieChanges() }
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
            let generation = reconciliationGeneration
            Task { @MainActor in
                var succeeded = true
                var snapshot: CookieSnapshot?
                while dirty {
                    dirty = false
                    snapshot = await currentCookieSnapshot()
                    if let snapshot {
                        let ehi = EhiCookieVault.save(snapshot.ehi, fileURL: ehiFile, allowEmpty: true)
                        let zuche = ZucheCookieVault.save(snapshot.zuche, fileURL: zucheFile, allowEmpty: true)
                        succeeded = succeeded && ehi && zuche
                    }
                }
                lastSaveSucceeded = succeeded
                if succeeded {
                    lastSavedCookieSnapshot = snapshot
                    if generation == reconciliationGeneration {
                        reconciliationFailureCount = 0
                        reconciliationRetryDate = nil
                        lastReconciliationFailureRevision = nil
                    }
                }
                saveRevision += 1
                let completed = waiters
                waiters = []
                saving = false
                for waiter in completed { waiter.resume(returning: succeeded) }
            }
        }
    }

    private func currentCookieSnapshot() async -> CookieSnapshot {
        let cookies = await withCheckedContinuation { continuation in
            store.getAllCookies { continuation.resume(returning: $0) }
        }
        return CookieSnapshot(
            ehi: EhiCookieVault.persistableCookies(from: cookies, now: Date()),
            zuche: ZucheCookieVault.persistableCookies(from: cookies, now: Date())
        )
    }

    private func startCookieReconciliation() {
        guard reconciliationTask == nil else { return }
        reconciliationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled, let self else { return }
                await self.reconcileCookieChanges()
            }
        }
    }

    private func reconcileCookieChanges() async {
        guard started else { return }
        if let reconciliationRetryDate, Date() < reconciliationRetryDate { return }
        let generation = reconciliationGeneration
        let snapshot = await currentCookieSnapshot()
        guard started, generation == reconciliationGeneration, snapshot != lastSavedCookieSnapshot else { return }
        let succeeded = await flush()
        guard generation == reconciliationGeneration else { return }
        if !succeeded, lastReconciliationFailureRevision != saveRevision {
            lastReconciliationFailureRevision = saveRevision
            reconciliationFailureCount = min(reconciliationFailureCount + 1, 6)
            let exponent = reconciliationFailureCount - 1
            let delay = min(30, TimeInterval(1 << exponent))
            reconciliationRetryDate = Date().addingTimeInterval(delay)
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
        reconciliationGeneration &+= 1
        reconciliationTask?.cancel()
        reconciliationTask = nil
        lastSavedCookieSnapshot = nil
        reconciliationFailureCount = 0
        reconciliationRetryDate = nil
        lastReconciliationFailureRevision = nil
    }
}
