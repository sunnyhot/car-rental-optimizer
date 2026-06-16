import CarRentalDomain
import Foundation
import Testing
@testable import CarRentalOptimizer

@Suite("MonitorScheduler")
@MainActor
struct MonitorSchedulerTests {
    @Test("Due successful check appends snapshot and price drop event")
    func dueSuccessfulCheckAppendsSnapshotAndPriceDropEvent() async throws {
        let store = InMemoryMonitorStore()
        let monitor = makeMonitor(nextCheckAt: Date(timeIntervalSince1970: 100))
        try await store.saveMonitor(monitor)
        try await store.appendSnapshot(successSnapshot(id: "old", monitorID: monitor.id, price: 500, total: 560))
        let scheduler = MonitorScheduler(
            store: store,
            searchProvider: StubRentalSearchProvider(results: [readyResult(price: 450)]),
            mapService: EstimatedMapService(),
            notificationService: RecordingNotificationService(),
            now: { Date(timeIntervalSince1970: 200) },
            idGenerator: IncrementingIDGenerator()
        )

        try await scheduler.runDueChecks()

        let snapshots = try await store.snapshots(for: monitor.id)
        let events = try await store.events(for: monitor.id)
        #expect(snapshots.count == 2)
        #expect(snapshots.last?.platformRentalPrice == 450)
        #expect(events.count == 1)
        #expect(events.first?.kind == .priceDrop)
        #expect(events.first?.platformRentalDelta == -50)
    }

    @Test("Unchanged price does not create event")
    func unchangedPriceDoesNotCreateEvent() async throws {
        let store = InMemoryMonitorStore()
        let monitor = makeMonitor(nextCheckAt: Date(timeIntervalSince1970: 100))
        try await store.saveMonitor(monitor)
        try await store.appendSnapshot(successSnapshot(id: "old", monitorID: monitor.id, price: 500, total: 560))
        let scheduler = MonitorScheduler(
            store: store,
            searchProvider: StubRentalSearchProvider(results: [readyResult(price: 500)]),
            mapService: EstimatedMapService(),
            notificationService: RecordingNotificationService(),
            now: { Date(timeIntervalSince1970: 200) },
            idGenerator: IncrementingIDGenerator()
        )

        try await scheduler.runDueChecks()

        #expect(try await store.events(for: monitor.id).isEmpty)
    }

    @Test("Login required appends failure snapshot without event")
    func loginRequiredAppendsFailureSnapshotWithoutEvent() async throws {
        let store = InMemoryMonitorStore()
        let monitor = makeMonitor(nextCheckAt: Date(timeIntervalSince1970: 100))
        try await store.saveMonitor(monitor)
        let scheduler = MonitorScheduler(
            store: store,
            searchProvider: StubRentalSearchProvider(results: [
                PlatformEvidenceResult(
                    platform: .ehi,
                    status: PlatformEvidenceStatus(platform: .ehi, kind: .loginRequired, message: "一嗨需要登录。", sourceUrl: "https://booking.1hai.cn/"),
                    listings: []
                )
            ]),
            mapService: EstimatedMapService(),
            notificationService: RecordingNotificationService(),
            now: { Date(timeIntervalSince1970: 200) },
            idGenerator: IncrementingIDGenerator()
        )

        try await scheduler.runDueChecks()

        let snapshots = try await store.snapshots(for: monitor.id)
        #expect(snapshots.last?.status == .loginRequired)
        #expect(try await store.events(for: monitor.id).isEmpty)
    }

    @Test("Repeated equivalent failures create one attention event")
    func repeatedEquivalentFailuresCreateOneAttentionEvent() async throws {
        let store = InMemoryMonitorStore()
        let monitor = makeMonitor(nextCheckAt: Date(timeIntervalSince1970: 100))
        try await store.saveMonitor(monitor)
        try await store.appendSnapshot(failureSnapshot(id: "old-1", monitorID: monitor.id, status: .loginRequired, checkedAt: Date(timeIntervalSince1970: 50)))
        try await store.appendSnapshot(failureSnapshot(id: "old-2", monitorID: monitor.id, status: .loginRequired, checkedAt: Date(timeIntervalSince1970: 75)))
        let scheduler = MonitorScheduler(
            store: store,
            searchProvider: StubRentalSearchProvider(results: [
                PlatformEvidenceResult(
                    platform: .ehi,
                    status: PlatformEvidenceStatus(platform: .ehi, kind: .loginRequired, message: "一嗨需要登录。", sourceUrl: "https://booking.1hai.cn/"),
                    listings: []
                )
            ]),
            mapService: EstimatedMapService(),
            notificationService: RecordingNotificationService(),
            now: { Date(timeIntervalSince1970: 200) },
            idGenerator: IncrementingIDGenerator()
        )

        try await scheduler.runDueChecks()

        let events = try await store.events(for: monitor.id)
        #expect(events.count == 1)
        #expect(events.first?.kind == .repeatedFailure)
        #expect(events.first?.previousSnapshotID == "old-2")
        #expect(events.first?.currentSnapshotID == "snapshot-1")
    }

    @Test("Successful check after failures creates recovery event")
    func successfulCheckAfterFailuresCreatesRecoveryEvent() async throws {
        let store = InMemoryMonitorStore()
        let monitor = makeMonitor(nextCheckAt: Date(timeIntervalSince1970: 100))
        try await store.saveMonitor(monitor)
        try await store.appendSnapshot(failureSnapshot(id: "old-failure", monitorID: monitor.id, status: .captchaRequired, checkedAt: Date(timeIntervalSince1970: 75)))
        let scheduler = MonitorScheduler(
            store: store,
            searchProvider: StubRentalSearchProvider(results: [readyResult(price: 450)]),
            mapService: EstimatedMapService(),
            notificationService: RecordingNotificationService(),
            now: { Date(timeIntervalSince1970: 200) },
            idGenerator: IncrementingIDGenerator()
        )

        try await scheduler.runDueChecks()

        let events = try await store.events(for: monitor.id)
        #expect(events.count == 1)
        #expect(events.first?.kind == .recovered)
        #expect(events.first?.previousSnapshotID == "old-failure")
        #expect(events.first?.currentSnapshotID == "snapshot-1")
    }

    private func makeMonitor(nextCheckAt: Date) -> PriceMonitor {
        PriceMonitor(
            id: "monitor-1",
            name: "瑞虎8",
            request: AppDefaults.searchRequest,
            targetVehicleQuery: "瑞虎8",
            frequency: .fixed1Hour,
            alertRule: .defaultRule,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            nextCheckAt: nextCheckAt
        )
    }

    private func readyResult(price: Double) -> PlatformEvidenceResult {
        PlatformEvidenceResult(
            platform: .ehi,
            status: PlatformEvidenceStatus(platform: .ehi, kind: .ready, message: "ready", sourceUrl: "https://booking.1hai.cn/"),
            listings: [RentalListing(
                id: "listing-\(Int(price))",
                platform: .ehi,
                store: Store(id: "store-1", platform: .ehi, name: "一嗨通州店", city: "北京", address: "通州", location: AppDefaults.searchRequest.origin, distanceKm: 2, hours: "08:00-22:00"),
                vehicleName: "奇瑞 瑞虎8",
                vehicleClass: "SUV",
                basePrice: price,
                platformFees: 0,
                insuranceFees: 0,
                oneWayFee: 0,
                sourceUrl: "https://booking.1hai.cn/",
                dataCompleteness: 0.9
            )]
        )
    }

    private func successSnapshot(id: String, monitorID: String, price: Double, total: Double) -> PriceSnapshot {
        PriceSnapshot(id: id, monitorID: monitorID, checkedAt: Date(timeIntervalSince1970: 50), status: .successful, platformRentalPrice: price, recommendationTotalCost: total, platform: .ehi, storeName: "一嗨通州店", vehicleName: "奇瑞 瑞虎8", message: "success")
    }

    private func failureSnapshot(id: String, monitorID: String, status: PriceSnapshotStatus, checkedAt: Date) -> PriceSnapshot {
        PriceSnapshot(id: id, monitorID: monitorID, checkedAt: checkedAt, status: status, platform: .ehi, message: "failure")
    }
}

private actor InMemoryMonitorStore: MonitorStoring {
    private var monitors: [PriceMonitor] = []
    private var snapshotsByMonitor: [String: [PriceSnapshot]] = [:]
    private var eventsByMonitor: [String: [PriceMonitorEvent]] = [:]

    func listMonitors() async throws -> [PriceMonitor] { monitors }

    func saveMonitor(_ monitor: PriceMonitor) async throws {
        if let index = monitors.firstIndex(where: { $0.id == monitor.id }) {
            monitors[index] = monitor
        } else {
            monitors.append(monitor)
        }
    }

    func deleteMonitor(id: String) async throws {
        monitors.removeAll { $0.id == id }
    }

    func appendSnapshot(_ snapshot: PriceSnapshot) async throws {
        snapshotsByMonitor[snapshot.monitorID, default: []].append(snapshot)
    }

    func snapshots(for monitorID: String) async throws -> [PriceSnapshot] {
        snapshotsByMonitor[monitorID, default: []]
    }

    func appendEvent(_ event: PriceMonitorEvent) async throws {
        eventsByMonitor[event.monitorID, default: []].append(event)
    }

    func events(for monitorID: String) async throws -> [PriceMonitorEvent] {
        eventsByMonitor[monitorID, default: []]
    }

    func markMonitorStatus(id: String, status: PriceMonitorStatus, updatedAt: Date) async throws {
        guard let index = monitors.firstIndex(where: { $0.id == id }) else { return }
        monitors[index].status = status
        monitors[index].updatedAt = updatedAt
    }
}

private struct StubRentalSearchProvider: RentalSearchProviding {
    let results: [PlatformEvidenceResult]

    func search(request: SearchRequest) async -> [PlatformEvidenceResult] {
        results
    }
}

private final class RecordingNotificationService: MonitorNotificationSending {
    private(set) var sentEvents: [PriceMonitorEvent] = []

    func sendPriceDropNotification(monitor: PriceMonitor, event: PriceMonitorEvent) async {
        sentEvents.append(event)
    }
}

private struct IncrementingIDGenerator: MonitorIDGenerating {
    private final class Box { var value = 0 }
    private let box = Box()

    func nextID(prefix: String) -> String {
        box.value += 1
        return "\(prefix)-\(box.value)"
    }
}
