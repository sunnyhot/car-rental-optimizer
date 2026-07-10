import Testing
@testable import CarRentalOptimizer

@Suite("Comparison presentation")
struct ComparisonPresentationTests {
    @Test("Matrix uses the approved section order and preserves the core total row")
    func approvedSectionOrder() {
        let candidates = [
            makeComparisonRecommendation(id: "a", vehicleName: "宋 Pro", rentalTotal: 1200, bestTotal: 1286, distanceKm: 1.2),
            makeComparisonRecommendation(id: "b", vehicleName: "途观 L", rentalTotal: 1350, bestTotal: 1438, distanceKm: 0.8),
        ]

        let sections = ComparisonPresentation.sections(candidates: candidates, insightStates: [:], onlyDifferences: false)

        #expect(sections.map(\.id) == [.summary, .cost, .route, .vehicle, .trust])
        #expect(sections.flatMap(\.rows).contains { $0.id == "best-total" && $0.isCore })
    }

    @Test("Cost distance and completeness advantages are independent")
    func independentAdvantages() {
        let candidates = [
            makeComparisonRecommendation(id: "cheap", vehicleName: "便宜车", rentalTotal: 900, bestTotal: 930, distanceKm: 3, dataCompleteness: 0.80),
            makeComparisonRecommendation(id: "near", vehicleName: "近门店", rentalTotal: 950, bestTotal: 980, distanceKm: 1, dataCompleteness: 0.99),
        ]

        let rows = ComparisonPresentation.sections(candidates: candidates, insightStates: [:], onlyDifferences: false).flatMap(\.rows)

        #expect(rows.first { $0.id == "best-total" }?.cells.first { $0.candidateID == "cheap" }?.tone == .advantage)
        #expect(rows.first { $0.id == "store-distance" }?.cells.first { $0.candidateID == "near" }?.tone == .advantage)
        #expect(rows.first { $0.id == "completeness" }?.cells.first { $0.candidateID == "near" }?.tone == .advantage)
    }

    @Test("Difference mode removes equal non-core rows and keeps total")
    func differenceMode() {
        let candidates = [
            makeComparisonRecommendation(id: "a", vehicleName: "A", rentalTotal: 900, bestTotal: 930, distanceKm: 1),
            makeComparisonRecommendation(id: "b", vehicleName: "B", rentalTotal: 900, bestTotal: 980, distanceKm: 1),
        ]

        let rows = ComparisonPresentation.sections(candidates: candidates, insightStates: [:], onlyDifferences: true).flatMap(\.rows)

        #expect(rows.contains { $0.id == "best-total" })
        #expect(!rows.contains { $0.id == "store-distance" })
    }

    @Test("Missing configuration is presented as unconfirmed")
    func missingConfigurationIsUnconfirmed() {
        let candidate = makeComparisonRecommendation(id: "a", vehicleName: "A", rentalTotal: 900, bestTotal: 930, distanceKm: 1)

        let rows = ComparisonPresentation.sections(candidates: [candidate], insightStates: [:], onlyDifferences: false).flatMap(\.rows)

        #expect(rows.first { $0.id == "vehicle-insight" }?.cells.first?.text == "未确认")
        #expect(rows.first { $0.id == "vehicle-insight" }?.cells.first?.tone == .unavailable)
    }
}
