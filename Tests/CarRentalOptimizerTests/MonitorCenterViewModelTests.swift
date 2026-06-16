import CarRentalDomain
import Foundation
import Testing
@testable import CarRentalOptimizer

@Suite("MonitorCenterViewModel")
@MainActor
struct MonitorCenterViewModelTests {
    @Test("Create monitor from recommendation saves monitor and first snapshot")
    func createMonitorFromRecommendationSavesMonitorAndFirstSnapshot() async throws {
        let store = InMemoryMonitorStore()
        let viewModel = MonitorCenterViewModel(store: store, scheduler: nil, now: { Date(timeIntervalSince1970: 100) }, idGenerator: FixedIDGenerator())
        let recommendation = makeRecommendation()

        try await viewModel.createMonitor(from: recommendation, request: AppDefaults.searchRequest, frequency: .smart, alertRule: .defaultRule, systemNotificationsEnabled: false)

        #expect(viewModel.monitors.count == 1)
        #expect(viewModel.selectedMonitorID == "monitor-fixed")
        #expect(try await store.snapshots(for: "monitor-fixed").count == 1)
        #expect(try await store.snapshots(for: "monitor-fixed").first?.platformRentalPrice == recommendation.rentalTotal)
    }

    @Test("Pause and resume update monitor status")
    func pauseAndResumeUpdateMonitorStatus() async throws {
        let store = InMemoryMonitorStore()
        let monitor = makeMonitor(id: "monitor-1")
        try await store.saveMonitor(monitor)
        let viewModel = MonitorCenterViewModel(store: store, scheduler: nil, now: { Date(timeIntervalSince1970: 100) }, idGenerator: FixedIDGenerator())
        try await viewModel.reload()

        try await viewModel.pauseMonitor(id: monitor.id)
        #expect(viewModel.monitors.first?.status == .paused)

        try await viewModel.resumeMonitor(id: monitor.id)
        #expect(viewModel.monitors.first?.status == .active)
    }

    @Test("Background monitoring preference toggles without changing monitors")
    func backgroundMonitoringPreferenceTogglesWithoutChangingMonitors() async throws {
        let store = InMemoryMonitorStore()
        let monitor = makeMonitor(id: "monitor-1")
        try await store.saveMonitor(monitor)
        let viewModel = MonitorCenterViewModel(store: store, scheduler: nil, now: { Date(timeIntervalSince1970: 100) }, idGenerator: FixedIDGenerator())
        try await viewModel.reload()

        viewModel.setBackgroundMonitoringEnabled(true)

        #expect(viewModel.backgroundMonitoringEnabled)
        #expect(viewModel.monitors.map(\.id) == ["monitor-1"])

        viewModel.setBackgroundMonitoringEnabled(false)

        #expect(!viewModel.backgroundMonitoringEnabled)
        #expect(viewModel.monitors.map(\.id) == ["monitor-1"])
    }

    @Test("Filter counts health summary and displayed monitors use cached monitor data")
    func filterCountsHealthSummaryAndDisplayedMonitorsUseCachedMonitorData() async throws {
        let store = InMemoryMonitorStore()
        let now = Date(timeIntervalSince1970: 200)
        let ordinary = makeMonitor(id: "ordinary", status: .active, nextCheckAt: Date(timeIntervalSince1970: 500))
        let attention = makeMonitor(id: "attention", status: .needsAttention, nextCheckAt: Date(timeIntervalSince1970: 100))
        let drop = makeMonitor(id: "drop", status: .active, nextCheckAt: Date(timeIntervalSince1970: 500))
        try await store.saveMonitor(ordinary)
        try await store.saveMonitor(attention)
        try await store.saveMonitor(drop)
        try await store.appendEvent(PriceMonitorEvent(id: "event-drop", monitorID: "drop", occurredAt: now, kind: .priceDrop, message: "drop"))
        let viewModel = MonitorCenterViewModel(store: store, scheduler: nil, now: { now }, idGenerator: FixedIDGenerator())

        try await viewModel.reload()

        #expect(viewModel.filterCount(for: .all) == 3)
        #expect(viewModel.filterCount(for: .active) == 2)
        #expect(viewModel.filterCount(for: .needsAttention) == 1)
        #expect(viewModel.healthSummary.totalCount == 3)
        #expect(viewModel.healthSummary.needsAttentionCount == 1)
        #expect(viewModel.healthSummary.recentPriceDropCount == 1)
        #expect(viewModel.displayedMonitors.map(\.id) == ["attention", "drop", "ordinary"])

        viewModel.filter = .needsAttention

        #expect(viewModel.displayedMonitors.map(\.id) == ["attention"])
    }

    @Test("Batch pause and resume operate on requested monitors")
    func batchPauseAndResumeOperateOnRequestedMonitors() async throws {
        let store = InMemoryMonitorStore()
        let first = makeMonitor(id: "first")
        let second = makeMonitor(id: "second")
        try await store.saveMonitor(first)
        try await store.saveMonitor(second)
        let viewModel = MonitorCenterViewModel(store: store, scheduler: nil, now: { Date(timeIntervalSince1970: 200) }, idGenerator: FixedIDGenerator())
        try await viewModel.reload()

        try await viewModel.pauseMonitors(ids: ["first", "second"])
        #expect(Set(viewModel.monitors.map(\.status)) == [.paused])
        #expect(viewModel.operationFeedbackMessage == "已暂停 2 个监控。")

        try await viewModel.resumeMonitors(ids: ["first"])
        #expect(viewModel.monitors.first { $0.id == "first" }?.status == .active)
        #expect(viewModel.monitors.first { $0.id == "second" }?.status == .paused)
        #expect(viewModel.operationFeedbackMessage == "已恢复 1 个监控。")
    }

    @Test("Run shown checks reports completion feedback")
    func runShownChecksReportsCompletionFeedback() async throws {
        let store = InMemoryMonitorStore()
        let monitor = makeMonitor(id: "monitor-1", nextCheckAt: Date(timeIntervalSince1970: 100))
        try await store.saveMonitor(monitor)
        let scheduler = MonitorScheduler(
            store: store,
            searchProvider: StubRentalSearchProvider(results: [readyResult(price: 450)]),
            mapService: EstimatedMapService(),
            notificationService: RecordingNotificationService(),
            now: { Date(timeIntervalSince1970: 200) },
            idGenerator: IncrementingIDGenerator()
        )
        let viewModel = MonitorCenterViewModel(store: store, scheduler: scheduler, now: { Date(timeIntervalSince1970: 200) }, idGenerator: FixedIDGenerator())
        try await viewModel.reload()

        await viewModel.runShownChecks()

        #expect(viewModel.operationFeedbackMessage == "已完成当前筛选的 1 个监控巡查。")
        #expect((try await store.snapshots(for: monitor.id)).last?.status == .successful)
    }

    private func makeMonitor(
        id: String,
        status: PriceMonitorStatus = .active,
        nextCheckAt: Date? = nil
    ) -> PriceMonitor {
        PriceMonitor(
            id: id,
            name: "瑞虎8",
            request: AppDefaults.searchRequest,
            targetVehicleQuery: "瑞虎8",
            frequency: .fixed1Hour,
            status: status,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            nextCheckAt: nextCheckAt
        )
    }

    private func makeRecommendation() -> Recommendation {
        let store = Store(id: "store-1", platform: .ehi, name: "一嗨通州店", city: "北京", address: "通州", location: AppDefaults.searchRequest.origin, distanceKm: 2, hours: "08:00-22:00")
        let listing = RentalListing(id: "listing-1", platform: .ehi, store: store, vehicleName: "奇瑞 瑞虎8", vehicleClass: "SUV", basePrice: 360, platformFees: 0, insuranceFees: 0, oneWayFee: 0, sourceUrl: "https://booking.1hai.cn/", dataCompleteness: 0.9)
        return buildRecommendation(listing: listing, match: VehicleMatch(kind: .exact, score: 1, label: "精确匹配"), taxiRoute: RouteEstimate(mode: .taxi, cost: 30, durationMinutes: 20, distanceKm: 2, summary: "打车"), transitRoute: RouteEstimate(mode: .transit, cost: 6, durationMinutes: 40, distanceKm: 2, summary: "公交"))
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

private struct FixedIDGenerator: MonitorIDGenerating {
    func nextID(prefix: String) -> String {
        "\(prefix)-fixed"
    }
}

private struct StubRentalSearchProvider: RentalSearchProviding {
    let results: [PlatformEvidenceResult]

    func search(request: SearchRequest) async -> [PlatformEvidenceResult] {
        results
    }
}

private final class RecordingNotificationService: MonitorNotificationSending {
    func sendPriceDropNotification(monitor: PriceMonitor, event: PriceMonitorEvent) async {}
}

private struct IncrementingIDGenerator: MonitorIDGenerating {
    private final class Box { var value = 0 }
    private let box = Box()

    func nextID(prefix: String) -> String {
        box.value += 1
        return "\(prefix)-\(box.value)"
    }
}
