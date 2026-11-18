import CarRentalDomain
import Combine
import Foundation

enum VehicleReferenceLoadState: Equatable {
    case pending, complete, partial, unavailable, deferred
}

@MainActor
final class VehicleReferenceBatchLoader: ObservableObject {
    @Published private(set) var states: [String: VehicleReferenceLoadState] = [:]
    @Published private(set) var revision = 0
    @Published private(set) var isLoading = false
    var onUpdate: ((String, VehicleInsight) -> Void)?
    private let service: VehicleInsightProviding
    private var references: [String: VehicleInsight] = [:]
    private var generation = 0
    private var task: Task<Void, Never>?

    init(service: VehicleInsightProviding) { self.service = service }
    deinit { task?.cancel() }

    static func key(for listing: RentalListing) -> String {
        VehicleInsightStore.normalizedCacheKey(VehicleInsightLocalInferencer.normalizedQuery(for: listing))
    }

    var totalCount: Int { states.count }
    var processedCount: Int { states.values.filter { $0 != .pending }.count }
    var completeCount: Int { states.values.filter { $0 == .complete }.count }
    var partialCount: Int { states.values.filter { $0 == .partial }.count }
    var missingCount: Int { states.values.filter { $0 == .unavailable }.count }
    var deferredCount: Int { states.values.filter { $0 == .deferred }.count }
    var retryAfter: Date? { references.values.compactMap(\.referenceRetryAfter).max() }
    var needsMoreData: Bool { partialCount + missingCount + deferredCount > 0 }

    func reference(for listing: RentalListing) -> VehicleInsight {
        guard let reference = references[Self.key(for: listing)] else { return service.localInsight(for: listing) }
        return mergeVehicleReference(reference, for: listing)
    }

    func dimensionSummary(for listing: RentalListing) -> String {
        let sheet = reference(for: listing).specSheet
        var values: [String] = []
        if let length = sheet.lengthMm { values.append("车长 \(length.value)mm") }
        if let wheelbase = sheet.wheelbaseMm { values.append("轴距 \(wheelbase.value)mm") }
        if !values.isEmpty { return values.joined(separator: " · ") + " · 车系参考" }
        if states[Self.key(for: listing)] == .deferred { return "资料源限流，尺寸等待重试" }
        return states[Self.key(for: listing)] == .pending ? "尺寸资料补全中…" : "暂无可验证尺寸资料"
    }

    func acceptReference(_ reference: VehicleInsight, for listing: RentalListing) {
        let key = Self.key(for: listing)
        guard states[key] != nil else { return }
        references[key] = reference
        states[key] = reference.specSheet.hasCompleteDimensions ? .complete : (reference.referenceRetryAfter != nil ? .deferred : (reference.specSheet.hasReferenceDimensions ? .partial : .unavailable))
        revision += 1
    }

    func cancel() {
        generation += 1
        task?.cancel()
        task = nil
        isLoading = false
    }

    func waitUntilFinished() async { await task?.value }

    func start(listings: [RentalListing], forceMissing: Bool = false) {
        cancel()
        let run = generation
        let previous = references
        references = [:]
        states = [:]
        var queue: [(String, RentalListing)] = []
        var seen = Set<String>()
        for listing in listings {
            let key = Self.key(for: listing)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            let cached = service.localInsight(for: listing)
            let local = forceMissing && !cached.specSheet.hasCompleteDimensions ? previous[key] ?? cached : cached
            references[key] = local
            if local.specSheet.hasCompleteDimensions && (forceMissing || local.cacheState != .stale) {
                states[key] = .complete
            } else {
                states[key] = .pending
                queue.append((key, listing))
            }
        }
        revision += 1
        guard !queue.isEmpty else { return }
        isLoading = true
        let service = service
        task = Task { [weak self] in
            await withTaskGroup(of: (String, VehicleInsight?).self) { group in
                var next = 0
                func addNext() {
                    guard !Task.isCancelled, next < queue.count else { return }
                    let item = queue[next]
                    next += 1
                    group.addTask { @MainActor in
                        guard !Task.isCancelled else { return (item.0, nil) }
                        let value = forceMissing ? await service.refreshInsight(for: item.1) : await service.insight(for: item.1)
                        return (item.0, value)
                    }
                }
                for _ in 0..<min(2, queue.count) { addNext() }
                while let (key, value) = await group.next() {
                    guard !Task.isCancelled, self?.generation == run else { group.cancelAll(); break }
                    if let value {
                        self?.references[key] = value
                        self?.states[key] = value.specSheet.hasCompleteDimensions ? .complete : (value.referenceRetryAfter != nil ? .deferred : (value.specSheet.hasReferenceDimensions ? .partial : .unavailable))
                        self?.revision += 1
                        self?.onUpdate?(key, value)
                    }
                    addNext()
                }
            }
            guard self?.generation == run else { return }
            self?.isLoading = false
            self?.task = nil
        }
    }
}

actor VehicleReferenceRequestGate {
    private let limit: Int
    private var active = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []
    init(limit: Int) { self.limit = max(1, limit) }
    func acquire() async {
        if active < limit { active += 1; return }
        await withCheckedContinuation { waiting.append($0) }
    }
    func release() {
        if waiting.isEmpty { active -= 1 } else { waiting.removeFirst().resume() }
    }
}
