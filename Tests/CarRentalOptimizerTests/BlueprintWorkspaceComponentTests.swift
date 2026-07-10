import Foundation
import Testing

@Suite("Route Blueprint workspace components")
struct BlueprintWorkspaceComponentTests {
    @Test("Workspace component file exposes the approved focused primitives")
    func componentFileExposesApprovedPrimitives() throws {
        let source = try String(contentsOfFile: "Sources/CarRentalOptimizer/BlueprintWorkspaceComponents.swift", encoding: .utf8)

        #expect(source.contains("struct BlueprintSectionHeader"))
        #expect(source.contains("struct BlueprintMetricTile"))
        #expect(source.contains("struct BlueprintRouteStep"))
        #expect(source.contains("struct BlueprintRoutePath"))
        #expect(source.contains("struct BlueprintStatePanel"))
        #expect(source.contains("accessibilityReduceMotion"))
    }
}
