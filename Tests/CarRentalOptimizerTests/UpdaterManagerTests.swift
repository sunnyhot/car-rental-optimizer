import Testing
@testable import CarRentalOptimizer

@Suite("AppInfo version consistency")
struct AppInfoVersionTests {
    @Test("Version matches semver pattern")
    func versionMatchesSemver() {
        // Semver: MAJOR.MINOR.PATCH
        let parts = AppInfo.version.split(separator: ".")
        #expect(parts.count == 3)
        for part in parts {
            #expect(UInt(part) != nil, "Version component '\(part)' is not a valid number")
        }
    }

    @Test("Build number is a positive integer")
    func buildNumberIsValid() {
        #expect(UInt(AppInfo.build) != nil)
        #expect(UInt(AppInfo.build)! > 0)
    }

    @Test("Bundle identifier is reverse DNS")
    func bundleIdentifierIsValid() {
        #expect(AppInfo.bundleIdentifier.contains("."))
        #expect(AppInfo.bundleIdentifier == "com.carrental.optimizer")
    }

    @Test("App name is not empty")
    func appNameIsNotEmpty() {
        #expect(!AppInfo.appName.isEmpty)
    }
}
