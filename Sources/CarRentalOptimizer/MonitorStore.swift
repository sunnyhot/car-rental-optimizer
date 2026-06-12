import CarRentalDomain
import Foundation

protocol MonitorStoring {
    func listMonitors() async throws -> [PriceMonitor]
    func saveMonitor(_ monitor: PriceMonitor) async throws
    func deleteMonitor(id: String) async throws
    func appendSnapshot(_ snapshot: PriceSnapshot) async throws
    func snapshots(for monitorID: String) async throws -> [PriceSnapshot]
    func appendEvent(_ event: PriceMonitorEvent) async throws
    func events(for monitorID: String) async throws -> [PriceMonitorEvent]
    func markMonitorStatus(id: String, status: PriceMonitorStatus, updatedAt: Date) async throws
}

enum MonitorStoreError: Error, Equatable {
    case corruptFile(URL)
    case monitorNotFound(String)
}

struct MonitorStoreFiles {
    let directory: URL

    var monitorsURL: URL { directory.appendingPathComponent("monitors.json") }
    var snapshotsURL: URL { directory.appendingPathComponent("price-snapshots.json") }
    var eventsURL: URL { directory.appendingPathComponent("monitor-events.json") }

    static func applicationSupportDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appendingPathComponent("CarRentalOptimizer", isDirectory: true)
    }
}

struct VersionedMonitorPayload<Value: Codable>: Codable {
    var version: Int
    var values: [Value]

    init(version: Int = 1, values: [Value]) {
        self.version = version
        self.values = values
    }
}
