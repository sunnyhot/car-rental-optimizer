import CarRentalDomain
import Foundation

protocol MonitorIDGenerating {
    func nextID(prefix: String) -> String
}

struct UUIDMonitorIDGenerator: MonitorIDGenerating {
    func nextID(prefix: String) -> String {
        "\(prefix)-\(UUID().uuidString)"
    }
}

@MainActor
final class MonitorScheduler {
    private let store: MonitorStoring
    private let searchProvider: RentalSearchProviding
    private let mapService: MapService
    private let notificationService: MonitorNotificationSending
    private let now: () -> Date
    private let idGenerator: MonitorIDGenerating
    private var runningMonitorIDs = Set<String>()

    init(
        store: MonitorStoring,
        searchProvider: RentalSearchProviding,
        mapService: MapService,
        notificationService: MonitorNotificationSending,
        now: @escaping () -> Date = Date.init,
        idGenerator: MonitorIDGenerating = UUIDMonitorIDGenerator()
    ) {
        self.store = store
        self.searchProvider = searchProvider
        self.mapService = mapService
        self.notificationService = notificationService
        self.now = now
        self.idGenerator = idGenerator
    }

    func runDueChecks(limit: Int = 2) async throws {
        let currentTime = now()
        let monitors = try await store.listMonitors()
        let dueMonitors = monitors
            .filter { $0.status == .active || $0.status == .needsAttention }
            .filter { ($0.nextCheckAt ?? $0.createdAt) <= currentTime }
            .prefix(limit)

        for monitor in dueMonitors where !runningMonitorIDs.contains(monitor.id) {
            runningMonitorIDs.insert(monitor.id)
            defer { runningMonitorIDs.remove(monitor.id) }
            try await runCheck(for: monitor, at: currentTime)
        }
    }

    private func runCheck(for monitor: PriceMonitor, at checkedAt: Date) async throws {
        if let pickupAt = AppDateRules.parseRequestDate(monitor.request.pickupAt),
           monitor.status.shouldPauseAfterPickup(now: checkedAt, pickupAt: pickupAt)
        {
            try await store.markMonitorStatus(id: monitor.id, status: .expired, updatedAt: checkedAt)
            try await store.appendEvent(PriceMonitorEvent(
                id: idGenerator.nextID(prefix: "event"),
                monitorID: monitor.id,
                occurredAt: checkedAt,
                kind: .pausedAfterPickup,
                message: "取车时间已过，监控已自动暂停。"
            ))
            return
        }

        try await store.markMonitorStatus(id: monitor.id, status: .checking, updatedAt: checkedAt)
        let evidenceResults = await searchProvider.search(request: monitor.request)
        let listings = evidenceResults.flatMap(\.listings)
        let snapshot: PriceSnapshot

        if listings.isEmpty {
            snapshot = failureSnapshot(for: monitor, evidenceResults: evidenceResults, checkedAt: checkedAt)
        } else {
            let recommendations = await rankRentalListings(request: monitor.request, listings: listings, mapService: mapService)
            if let selected = selectMonitoredRecommendationWithExplanation(
                from: recommendations,
                signature: monitor.targetListingSignature,
                targetVehicleQuery: monitor.targetVehicleQuery,
                targetPlatform: monitor.targetPlatform
            ) {
                snapshot = successSnapshot(
                    for: monitor,
                    recommendation: selected.recommendation,
                    matchSummary: selected.summary,
                    checkedAt: checkedAt
                )
            } else {
                snapshot = PriceSnapshot(
                    id: idGenerator.nextID(prefix: "snapshot"),
                    monitorID: monitor.id,
                    checkedAt: checkedAt,
                    status: .noMatch,
                    message: "本次查询没有找到匹配的监控车型。"
                )
            }
        }

        let previousSnapshots = try await store.snapshots(for: monitor.id)
        try await store.appendSnapshot(snapshot)
        for event in makeMonitorLifecycleEvents(
            monitor: monitor,
            previousSnapshots: previousSnapshots,
            currentSnapshot: snapshot,
            checkedAt: checkedAt,
            id: { idGenerator.nextID(prefix: "event") }
        ) {
            try await store.appendEvent(event)
        }
        if let event = makePriceDropEvent(
            monitor: monitor,
            previousSnapshots: previousSnapshots,
            currentSnapshot: snapshot,
            checkedAt: checkedAt
        ) {
            try await store.appendEvent(event)
            await notificationService.sendPriceDropNotification(monitor: monitor, event: event)
        }

        var updated = monitor
        updated.status = snapshot.status == .successful ? .active : .needsAttention
        updated.lastCheckedAt = checkedAt
        if let pickupAt = AppDateRules.parseRequestDate(monitor.request.pickupAt) {
            updated.nextCheckAt = monitor.frequency.nextCheck(after: checkedAt, pickupAt: pickupAt)
            if updated.nextCheckAt == nil {
                updated.status = .expired
            }
        }
        updated.updatedAt = checkedAt
        try await store.saveMonitor(updated)
    }

    private func successSnapshot(
        for monitor: PriceMonitor,
        recommendation: Recommendation,
        matchSummary: String,
        checkedAt: Date
    ) -> PriceSnapshot {
        PriceSnapshot(
            id: idGenerator.nextID(prefix: "snapshot"),
            monitorID: monitor.id,
            checkedAt: checkedAt,
            status: .successful,
            platformRentalPrice: recommendation.rentalTotal,
            recommendationTotalCost: recommendation.bestTotal,
            platform: recommendation.listing.platform,
            storeName: recommendation.listing.store.name,
            vehicleName: recommendation.listing.vehicleName,
            dataCompleteness: recommendation.listing.dataCompleteness,
            warnings: recommendation.warnings,
            sourceURL: recommendation.listing.sourceUrl,
            message: "已记录本次官方报价。\(matchSummary)"
        )
    }

    private func failureSnapshot(
        for monitor: PriceMonitor,
        evidenceResults: [PlatformEvidenceResult],
        checkedAt: Date
    ) -> PriceSnapshot {
        let status = evidenceResults.map(\.status).first ?? PlatformEvidenceStatus(
            platform: .ehi,
            kind: .parseFailed,
            message: "平台查询失败。",
            sourceUrl: officialPlatformURL(for: .ehi)
        )
        return PriceSnapshot(
            id: idGenerator.nextID(prefix: "snapshot"),
            monitorID: monitor.id,
            checkedAt: checkedAt,
            status: snapshotStatus(from: status.kind),
            platform: status.platform,
            sourceURL: status.sourceUrl,
            message: status.message
        )
    }

    private func snapshotStatus(from kind: PlatformEvidenceStatusKind) -> PriceSnapshotStatus {
        switch kind {
        case .waitingForEvidence:
            return .networkFailed
        case .ready:
            return .noCar
        case .unavailable:
            return .unavailable
        case .loginRequired:
            return .loginRequired
        case .captchaRequired:
            return .captchaRequired
        case .parseFailed:
            return .parseFailed
        }
    }

    private func makePriceDropEvent(
        monitor: PriceMonitor,
        previousSnapshots: [PriceSnapshot],
        currentSnapshot: PriceSnapshot,
        checkedAt: Date
    ) -> PriceMonitorEvent? {
        guard currentSnapshot.status == .successful,
              let currentPrice = currentSnapshot.platformRentalPrice,
              let previous = previousSnapshots.reversed().first(where: { $0.status == .successful && $0.platformRentalPrice != nil }),
              let previousPrice = previous.platformRentalPrice,
              monitor.alertRule.isSatisfied(previous: previousPrice, current: currentPrice)
        else { return nil }

        let rentalDelta = currentPrice - previousPrice
        let totalDelta = currentSnapshot.recommendationTotalCost.flatMap { currentTotal in
            previous.recommendationTotalCost.map { currentTotal - $0 }
        }
        return PriceMonitorEvent(
            id: idGenerator.nextID(prefix: "event"),
            monitorID: monitor.id,
            occurredAt: checkedAt,
            kind: .priceDrop,
            previousSnapshotID: previous.id,
            currentSnapshotID: currentSnapshot.id,
            platformRentalDelta: rentalDelta,
            totalCostDelta: totalDelta,
            message: "监控价格下降 \(formatMoney(abs(rentalDelta)))，请打开详情复查实时价格。"
        )
    }
}
