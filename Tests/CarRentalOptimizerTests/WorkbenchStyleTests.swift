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

    @Test("Workbench style exposes command center color tokens")
    func workbenchStyleExposesCommandCenterColorTokens() throws {
        let source = try String(contentsOfFile: "Sources/CarRentalOptimizer/WorkbenchStyle.swift", encoding: .utf8)

        #expect(source.contains("static let commandBlue"))
        #expect(source.contains("static let signalTeal"))
        #expect(source.contains("static let routeGreen"))
        #expect(source.contains("static let amberAlert"))
        #expect(source.contains("static let criticalRed"))
        #expect(source.contains("static let consoleBase"))
        #expect(source.contains("static let panelSurface"))
        #expect(source.contains("static let elevatedSurface"))
    }

    @Test("Workbench style defines reusable surface and motion components")
    func workbenchStyleDefinesReusableSurfaceAndMotionComponents() throws {
        let source = try String(contentsOfFile: "Sources/CarRentalOptimizer/WorkbenchStyle.swift", encoding: .utf8)

        #expect(source.contains("enum WorkbenchRailTone"))
        #expect(source.contains("struct StatusLightRail"))
        #expect(source.contains("struct WorkbenchBackground"))
        #expect(source.contains("struct WorkbenchCard"))
        #expect(source.contains("struct TaskStatusTile"))
        #expect(source.contains("struct ActionStatusRow"))
        #expect(source.contains("struct WorkbenchSheetShell"))
        #expect(source.contains("accessibilityReduceMotion"))
        #expect(source.contains("commandCenterTransition"))
    }
}
