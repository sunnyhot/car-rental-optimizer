import CarRentalDomain
import Foundation

actor JSONMonitorStore: MonitorStoring {
    private let files: MonitorStoreFiles
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(directory: URL) {
        self.files = MonitorStoreFiles(directory: directory)
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    static func live() throws -> JSONMonitorStore {
        try JSONMonitorStore(directory: MonitorStoreFiles.applicationSupportDirectory())
    }

    func listMonitors() async throws -> [PriceMonitor] {
        try readPayload(from: files.monitorsURL, as: PriceMonitor.self).sorted { $0.createdAt < $1.createdAt }
    }

    func saveMonitor(_ monitor: PriceMonitor) async throws {
        var monitors = try await listMonitors()
        if let index = monitors.firstIndex(where: { $0.id == monitor.id }) {
            monitors[index] = monitor
        } else {
            monitors.append(monitor)
        }
        try writePayload(monitors, to: files.monitorsURL)
    }

    func deleteMonitor(id: String) async throws {
        let monitors = try await listMonitors().filter { $0.id != id }
        let snapshots = try readPayload(from: files.snapshotsURL, as: PriceSnapshot.self).filter { $0.monitorID != id }
        let events = try readPayload(from: files.eventsURL, as: PriceMonitorEvent.self).filter { $0.monitorID != id }
        try writePayload(monitors, to: files.monitorsURL)
        try writePayload(snapshots, to: files.snapshotsURL)
        try writePayload(events, to: files.eventsURL)
    }

    func appendSnapshot(_ snapshot: PriceSnapshot) async throws {
        var snapshots = try readPayload(from: files.snapshotsURL, as: PriceSnapshot.self)
        snapshots.append(snapshot)
        try writePayload(snapshots, to: files.snapshotsURL)
    }

    func snapshots(for monitorID: String) async throws -> [PriceSnapshot] {
        try readPayload(from: files.snapshotsURL, as: PriceSnapshot.self)
            .filter { $0.monitorID == monitorID }
            .sorted { $0.checkedAt < $1.checkedAt }
    }

    func appendEvent(_ event: PriceMonitorEvent) async throws {
        var events = try readPayload(from: files.eventsURL, as: PriceMonitorEvent.self)
        events.append(event)
        try writePayload(events, to: files.eventsURL)
    }

    func events(for monitorID: String) async throws -> [PriceMonitorEvent] {
        try readPayload(from: files.eventsURL, as: PriceMonitorEvent.self)
            .filter { $0.monitorID == monitorID }
            .sorted { $0.occurredAt < $1.occurredAt }
    }

    func markMonitorStatus(id: String, status: PriceMonitorStatus, updatedAt: Date) async throws {
        var monitors = try await listMonitors()
        guard let index = monitors.firstIndex(where: { $0.id == id }) else {
            throw MonitorStoreError.monitorNotFound(id)
        }
        monitors[index].status = status
        monitors[index].updatedAt = updatedAt
        try writePayload(monitors, to: files.monitorsURL)
    }

    private func readPayload<Value: Codable>(from url: URL, as type: Value.Type) throws -> [Value] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(VersionedMonitorPayload<Value>.self, from: data).values
        } catch {
            throw MonitorStoreError.corruptFile(url)
        }
    }

    private func writePayload<Value: Codable>(_ values: [Value], to url: URL) throws {
        try FileManager.default.createDirectory(at: files.directory, withIntermediateDirectories: true)
        let data = try encoder.encode(VersionedMonitorPayload(values: values))
        let temporaryURL = url.appendingPathExtension("tmp-\(UUID().uuidString)")
        try data.write(to: temporaryURL, options: .atomic)
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporaryURL)
        } else {
            try FileManager.default.moveItem(at: temporaryURL, to: url)
        }
    }
}
