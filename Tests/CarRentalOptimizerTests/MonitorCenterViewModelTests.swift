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

    private func makeMonitor(id: String) -> PriceMonitor {
        PriceMonitor(
            id: id,
            name: "瑞虎8",
            request: AppDefaults.searchRequest,
            targetVehicleQuery: "瑞虎8",
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func makeRecommendation() -> Recommendation {
        let store = Store(id: "store-1", platform: .ehi, name: "一嗨通州店", city: "北京", address: "通州", location: AppDefaults.searchRequest.origin, distanceKm: 2, hours: "08:00-22:00")
        let listing = RentalListing(id: "listing-1", platform: .ehi, store: store, vehicleName: "奇瑞 瑞虎8", vehicleClass: "SUV", basePrice: 360, platformFees: 0, insuranceFees: 0, oneWayFee: 0, sourceUrl: "https://booking.1hai.cn/", dataCompleteness: 0.9)
        return buildRecommendation(listing: listing, match: VehicleMatch(kind: .exact, score: 1, label: "精确匹配"), taxiRoute: RouteEstimate(mode: .taxi, cost: 30, durationMinutes: 20, distanceKm: 2, summary: "打车"), transitRoute: RouteEstimate(mode: .transit, cost: 6, durationMinutes: 40, distanceKm: 2, summary: "公交"))
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
