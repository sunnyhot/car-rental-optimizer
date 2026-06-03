import Testing
@testable import CarRentalOptimizer

@Suite("AppInfo")
struct AppInfoTests {
    @Test("Version is not empty")
    func versionNotEmpty() {
        #expect(!AppInfo.version.isEmpty)
    }

    @Test("App name matches product name")
    func appNameMatches() {
        #expect(AppInfo.appName == "租车比价助手")
    }

    @Test("Bundle identifier follows reverse DNS")
    func bundleIdentifierIsValid() {
        #expect(AppInfo.bundleIdentifier.contains("."))
        #expect(AppInfo.bundleIdentifier == "com.carrental.optimizer")
    }
}
