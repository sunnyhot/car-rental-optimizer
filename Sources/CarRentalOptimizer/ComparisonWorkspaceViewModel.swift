import CarRentalDomain
import Foundation
import SwiftUI

enum ComparisonInsightState: Equatable {
    case loading(VehicleInsight)
    case loaded(VehicleInsight)
    case fallback(VehicleInsight)

    var insight: VehicleInsight {
        switch self {
        case .loading(let insight), .loaded(let insight), .fallback(let insight):
            return insight
        }
    }
}

@MainActor
final class ComparisonWorkspaceViewModel: ObservableObject {
    static let maximumSelectionCount = 4

    @Published private(set) var selectedRecommendations: [Recommendation] = []
    @Published private(set) var isComparing = false
    @Published var onlyShowsDifferences = false
    @Published private(set) var insightStates: [String: ComparisonInsightState] = [:]

    private let vehicleInsightService: VehicleInsightProviding
    private var insightTasks: [String: Task<Void, Never>] = [:]

    init(vehicleInsightService: VehicleInsightProviding = VehicleInsightService()) {
        self.vehicleInsightService = vehicleInsightService
    }

    var selectedIDs: [String] {
        selectedRecommendations.map(\.id)
    }

    var canBeginComparison: Bool {
        selectedRecommendations.count >= 2
    }

    var hasReachedMaximum: Bool {
        selectedRecommendations.count >= Self.maximumSelectionCount
    }

    func isSelected(_ id: String) -> Bool {
        selectedRecommendations.contains { $0.id == id }
    }

    func canSelect(_ id: String) -> Bool {
        isSelected(id) || !hasReachedMaximum
    }

    func toggle(_ recommendation: Recommendation) {
        if isSelected(recommendation.id) {
            remove(id: recommendation.id)
            return
        }
        guard !hasReachedMaximum else { return }
        selectedRecommendations.append(recommendation)
        loadInsight(for: recommendation)
    }

    func remove(id: String) {
        selectedRecommendations.removeAll { $0.id == id }
        insightTasks.removeValue(forKey: id)?.cancel()
        insightStates.removeValue(forKey: id)
        if selectedRecommendations.count < 2 {
            isComparing = false
        }
    }

    func beginComparison() {
        guard canBeginComparison else { return }
        isComparing = true
    }

    func exitComparison() {
        isComparing = false
    }

    func resetForNewSearch() {
        insightTasks.values.forEach { $0.cancel() }
        insightTasks.removeAll()
        selectedRecommendations.removeAll()
        insightStates.removeAll()
        isComparing = false
        onlyShowsDifferences = false
    }

    func reconcile(with results: [Recommendation]) {
        let byID = Dictionary(uniqueKeysWithValues: results.map { ($0.id, $0) })
        let retained = selectedRecommendations.compactMap { byID[$0.id] }
        let removedIDs = Set(selectedIDs).subtracting(retained.map(\.id))
        removedIDs.forEach { id in
            insightTasks.removeValue(forKey: id)?.cancel()
            insightStates.removeValue(forKey: id)
        }
        selectedRecommendations = retained
        if selectedRecommendations.count < 2 {
            isComparing = false
        }
    }

    func retryInsight(for recommendation: Recommendation) {
        guard isSelected(recommendation.id) else { return }
        insightTasks.removeValue(forKey: recommendation.id)?.cancel()
        loadInsight(for: recommendation)
    }

    private func loadInsight(for recommendation: Recommendation) {
        let local = vehicleInsightService.localInsight(for: recommendation.listing)
        insightStates[recommendation.id] = .loading(local)
        let service = vehicleInsightService
        insightTasks[recommendation.id] = Task { [weak self, recommendation, service] in
            let insight = await service.insight(for: recommendation.listing)
            guard !Task.isCancelled, let self, self.isSelected(recommendation.id) else { return }
            self.insightStates[recommendation.id] = insight.origin == .network
                ? .loaded(insight)
                : .fallback(insight)
            self.insightTasks.removeValue(forKey: recommendation.id)
        }
    }
}
