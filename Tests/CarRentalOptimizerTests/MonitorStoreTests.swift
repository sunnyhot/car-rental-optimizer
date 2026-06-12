import CarRentalDomain
import Foundation
import Testing
@testable import CarRentalOptimizer

@Suite("JSONMonitorStore")
struct MonitorStoreTests {
    @Test("Store round trips monitors snapshots and events")
    func storeRoundTripsMonitorsSnapshotsAndEvents() async throws {
        let directory = temporaryDirectory()
        let store = JSONMonitorStore(directory: directory)
        let monitor = makeMonitor(id: "monitor-1")
        let snapshot = PriceSnapshot(id: "snapshot-1", monitorID: monitor.id, checkedAt: Date(timeIntervalSince1970: 100), status: .successful, platformRentalPrice: 400, recommendationTotalCost: 450, platform: .ehi, storeName: "通州店", vehicleName: "瑞虎8", message: "success")
        let event = PriceMonitorEvent(id: "event-1", monitorID: monitor.id, occurredAt: Date(timeIntervalSince1970: 200), kind: .priceDrop, previousSnapshotID: "snapshot-0", currentSnapshotID: snapshot.id, platformRentalDelta: -30, totalCostDelta: -20, message: "降价 ¥30")

        try await store.saveMonitor(monitor)
        try await store.appendSnapshot(snapshot)
        try await store.appendEvent(event)

        #expect(try await store.listMonitors() == [monitor])
        #expect(try await store.snapshots(for: monitor.id) == [snapshot])
        #expect(try await store.events(for: monitor.id) == [event])
    }

    @Test("Store updates monitor status without dropping snapshots")
    func storeUpdatesMonitorStatusWithoutDroppingSnapshots() async throws {
        let directory = temporaryDirectory()
        let store = JSONMonitorStore(directory: directory)
        let monitor = makeMonitor(id: "monitor-1")
        let snapshot = PriceSnapshot(id: "snapshot-1", monitorID: monitor.id, checkedAt: Date(timeIntervalSince1970: 100), status: .networkFailed, message: "network")

        try await store.saveMonitor(monitor)
        try await store.appendSnapshot(snapshot)
        try await store.markMonitorStatus(id: monitor.id, status: .needsAttention, updatedAt: Date(timeIntervalSince1970: 300))

        let updated = try await store.listMonitors().first
        #expect(updated?.status == .needsAttention)
        #expect(try await store.snapshots(for: monitor.id) == [snapshot])
    }

    @Test("Store surfaces corrupt JSON")
    func storeSurfacesCorruptJSON() async throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: directory.appendingPathComponent("monitors.json"))
        let store = JSONMonitorStore(directory: directory)

        do {
            _ = try await store.listMonitors()
            Issue.record("Expected corrupt JSON to throw")
        } catch MonitorStoreError.corruptFile(let url) {
            #expect(url.lastPathComponent == "monitors.json")
        }
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MonitorStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func makeMonitor(id: String) -> PriceMonitor {
        PriceMonitor(
            id: id,
            name: "瑞虎8 北京监控",
            request: AppDefaults.searchRequest,
            targetVehicleQuery: "瑞虎8",
            frequency: .smart,
            alertRule: .defaultRule,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}
