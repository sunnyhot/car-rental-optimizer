import CarRentalDomain
import Foundation
import SwiftUI

@MainActor
final class MonitorCenterViewModel: ObservableObject {
    @Published private(set) var monitors: [PriceMonitor] = []
    @Published private(set) var selectedSnapshots: [PriceSnapshot] = []
    @Published private(set) var selectedEvents: [PriceMonitorEvent] = []
    @Published var selectedMonitorID: String?
    @Published var storageErrorMessage: String?
    @Published var backgroundMonitoringEnabled = false

    private let store: MonitorStoring
    private let scheduler: MonitorScheduler?
    private let now: () -> Date
    private let idGenerator: MonitorIDGenerating
    private var schedulerTask: Task<Void, Never>?

    init(
        store: MonitorStoring,
        scheduler: MonitorScheduler?,
        now: @escaping () -> Date = Date.init,
        idGenerator: MonitorIDGenerating = UUIDMonitorIDGenerator()
    ) {
        self.store = store
        self.scheduler = scheduler
        self.now = now
        self.idGenerator = idGenerator
    }

    var selectedMonitor: PriceMonitor? {
        guard let selectedMonitorID else { return monitors.first }
        return monitors.first { $0.id == selectedMonitorID }
    }

    var selectedTrend: PriceTrendSummary {
        PriceTrendSummary(snapshots: selectedSnapshots)
    }

    func reload() async throws {
        monitors = try await store.listMonitors()
        if selectedMonitorID == nil {
            selectedMonitorID = monitors.first?.id
        }
        try await reloadSelection()
    }

    func reloadSelection() async throws {
        guard let id = selectedMonitorID ?? monitors.first?.id else {
            selectedSnapshots = []
            selectedEvents = []
            return
        }
        selectedSnapshots = try await store.snapshots(for: id)
        selectedEvents = try await store.events(for: id)
    }

    func createMonitor(
        from recommendation: Recommendation,
        request: SearchRequest,
        frequency: MonitoringFrequency,
        alertRule: PriceDropRule,
        systemNotificationsEnabled: Bool
    ) async throws {
        let currentTime = now()
        let monitorID = idGenerator.nextID(prefix: "monitor")
        let pickupAt = AppDateRules.parseRequestDate(request.pickupAt)
        let monitor = PriceMonitor(
            id: monitorID,
            name: "\(recommendation.listing.vehicleName) \(request.pickupAt)",
            request: request,
            targetVehicleQuery: recommendation.listing.vehicleName,
            targetPlatform: recommendation.listing.platform,
            targetListingSignature: ListingSignature(recommendation: recommendation),
            frequency: frequency,
            alertRule: alertRule,
            systemNotificationsEnabled: systemNotificationsEnabled,
            createdAt: currentTime,
            updatedAt: currentTime,
            lastCheckedAt: currentTime,
            nextCheckAt: pickupAt.flatMap { frequency.nextCheck(after: currentTime, pickupAt: $0) }
        )
        let snapshot = PriceSnapshot(
            id: idGenerator.nextID(prefix: "snapshot"),
            monitorID: monitorID,
            checkedAt: currentTime,
            status: .successful,
            platformRentalPrice: recommendation.rentalTotal,
            recommendationTotalCost: recommendation.bestTotal,
            platform: recommendation.listing.platform,
            storeName: recommendation.listing.store.name,
            vehicleName: recommendation.listing.vehicleName,
            dataCompleteness: recommendation.listing.dataCompleteness,
            warnings: recommendation.warnings,
            sourceURL: recommendation.listing.sourceUrl,
            message: "创建监控时记录的历史快照。"
        )
        try await store.saveMonitor(monitor)
        try await store.appendSnapshot(snapshot)
        selectedMonitorID = monitorID
        try await reload()
    }

    func saveManualMonitor(
        name: String,
        request: SearchRequest,
        targetVehicleQuery: String,
        frequency: MonitoringFrequency,
        alertRule: PriceDropRule,
        systemNotificationsEnabled: Bool
    ) async throws {
        let currentTime = now()
        let monitor = PriceMonitor(
            id: idGenerator.nextID(prefix: "monitor"),
            name: name,
            request: request,
            targetVehicleQuery: targetVehicleQuery,
            frequency: frequency,
            alertRule: alertRule,
            systemNotificationsEnabled: systemNotificationsEnabled,
            createdAt: currentTime,
            updatedAt: currentTime,
            nextCheckAt: currentTime
        )
        try await store.saveMonitor(monitor)
        selectedMonitorID = monitor.id
        try await reload()
    }

    func pauseMonitor(id: String) async throws {
        try await store.markMonitorStatus(id: id, status: .paused, updatedAt: now())
        try await reload()
    }

    func resumeMonitor(id: String) async throws {
        try await store.markMonitorStatus(id: id, status: .active, updatedAt: now())
        try await reload()
    }

    func runDueChecks() async {
        do {
            try await scheduler?.runDueChecks()
            try await reload()
        } catch {
            storageErrorMessage = error.localizedDescription
        }
    }

    func setBackgroundMonitoringEnabled(_ enabled: Bool) {
        guard backgroundMonitoringEnabled != enabled else { return }
        backgroundMonitoringEnabled = enabled

        if enabled {
            startSchedulerLoop()
        } else {
            stopSchedulerLoop()
        }
    }

    func stopSchedulerLoopForExplicitQuit() {
        backgroundMonitoringEnabled = false
        stopSchedulerLoop()
    }

    private func startSchedulerLoop() {
        guard schedulerTask == nil else { return }
        schedulerTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.runDueChecks()
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
        }
    }

    private func stopSchedulerLoop() {
        schedulerTask?.cancel()
        schedulerTask = nil
    }
}
