import Testing
@testable import CarRentalOptimizer

@MainActor
@Suite("Comparison workspace")
struct ComparisonWorkspaceViewModelTests {
    @Test("Comparison requires two candidates and caps selection at four")
    func selectionLimits() {
        let model = ComparisonWorkspaceViewModel(vehicleInsightService: StubComparisonInsightService())
        let candidates = (1...5).map {
            makeComparisonRecommendation(id: "r\($0)", vehicleName: "车型\($0)", rentalTotal: Double(900 + $0), bestTotal: Double(930 + $0), distanceKm: Double($0))
        }

        model.toggle(candidates[0])
        model.beginComparison()
        #expect(!model.isComparing)

        // Add the next four; r1 stays selected and the cap rejects the fifth.
        candidates.dropFirst().forEach(model.toggle)
        #expect(model.selectedRecommendations.count == 4)
        #expect(model.selectedIDs == ["r1", "r2", "r3", "r4"])

        model.beginComparison()
        #expect(model.isComparing)
    }

    @Test("Removing down to one candidate exits comparison")
    func removalExitsComparison() {
        let model = ComparisonWorkspaceViewModel(vehicleInsightService: StubComparisonInsightService())
        let first = makeComparisonRecommendation(id: "a", vehicleName: "A", rentalTotal: 900, bestTotal: 930, distanceKm: 1)
        let second = makeComparisonRecommendation(id: "b", vehicleName: "B", rentalTotal: 950, bestTotal: 980, distanceKm: 2)
        model.toggle(first)
        model.toggle(second)
        model.beginComparison()

        model.remove(id: second.id)

        #expect(!model.isComparing)
        #expect(model.selectedIDs == [first.id])
    }

    @Test("Reconcile refreshes values without dropping filter-hidden candidates")
    func reconcileUsesFullResults() {
        let model = ComparisonWorkspaceViewModel(vehicleInsightService: StubComparisonInsightService())
        let old = makeComparisonRecommendation(id: "same", vehicleName: "车型", rentalTotal: 900, bestTotal: 930, distanceKm: 1)
        let refreshed = makeComparisonRecommendation(id: "same", vehicleName: "车型", rentalTotal: 850, bestTotal: 880, distanceKm: 1)
        model.toggle(old)

        model.reconcile(with: [refreshed])

        #expect(model.selectedRecommendations.first?.bestTotal == 880)
    }

    @Test("Local fallback is isolated to the selected candidate")
    func localFallbackState() async {
        let service = StubComparisonInsightService()
        service.returnedOrigin = .localInference
        let model = ComparisonWorkspaceViewModel(vehicleInsightService: service)
        let candidate = makeComparisonRecommendation(id: "fallback", vehicleName: "车型", rentalTotal: 900, bestTotal: 930, distanceKm: 1)

        model.toggle(candidate)
        try? await Task.sleep(nanoseconds: 10_000_000)

        guard case .fallback(let insight) = model.insightStates[candidate.id] else {
            Issue.record("Expected a per-column fallback state")
            return
        }
        #expect(insight.origin == .localInference)
    }

    @Test("New search reset clears selection and cancels comparison")
    func newSearchReset() {
        let model = ComparisonWorkspaceViewModel(vehicleInsightService: StubComparisonInsightService())
        model.toggle(makeComparisonRecommendation(id: "a", vehicleName: "A", rentalTotal: 900, bestTotal: 930, distanceKm: 1))

        model.resetForNewSearch()

        #expect(model.selectedRecommendations.isEmpty)
        #expect(model.insightStates.isEmpty)
        #expect(!model.isComparing)
        #expect(!model.onlyShowsDifferences)
    }

    @Test("A delayed insight response cannot restore a removed column")
    func removedCandidateIgnoresDelayedInsight() async {
        let service = StubComparisonInsightService()
        service.delayNanoseconds = 50_000_000
        let model = ComparisonWorkspaceViewModel(vehicleInsightService: service)
        let candidate = makeComparisonRecommendation(id: "delayed", vehicleName: "延迟车型", rentalTotal: 900, bestTotal: 930, distanceKm: 1)

        model.toggle(candidate)
        model.remove(id: candidate.id)
        try? await Task.sleep(nanoseconds: 80_000_000)

        #expect(model.insightStates[candidate.id] == nil)
        #expect(model.selectedRecommendations.isEmpty)
    }
}
