import Foundation
import Testing
@testable import CarRentalOptimizer

@Suite("Workbench style")
struct WorkbenchStyleTests {
    @Test("Workbench text colors use adaptive system colors for dark mode")
    func workbenchTextColorsUseAdaptiveSystemColorsForDarkMode() throws {
        let source = try String(contentsOfFile: "Sources/CarRentalOptimizer/WorkbenchStyle.swift", encoding: .utf8)

        #expect(source.contains("Color(nsColor: .labelColor)"))
        #expect(source.contains("Color(nsColor: .secondaryLabelColor)"))
        #expect(!source.contains("static let ink = Color(red: 0.10"))
        #expect(!source.contains("static let muted = Color(red: 0.39"))
    }
}
