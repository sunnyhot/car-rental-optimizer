import Foundation
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

    @Test("Native Info plist version matches AppInfo")
    func nativeInfoPlistVersionMatchesAppInfo() throws {
        let plist = try loadNativeInfoPlist()

        #expect(plist["CFBundleShortVersionString"] as? String == AppInfo.version)
        #expect(plist["CFBundleVersion"] as? String == AppInfo.build)
    }
}

private enum AppInfoTestError: Error {
    case projectRootNotFound
    case invalidInfoPlist
}

private func loadNativeInfoPlist(filePath: String = #filePath) throws -> [String: Any] {
    var directory = URL(fileURLWithPath: filePath).deletingLastPathComponent()

    while directory.path != "/" {
        let plistURL = directory
            .appendingPathComponent("native", isDirectory: true)
            .appendingPathComponent("Info.plist")
        if FileManager.default.fileExists(atPath: plistURL.path) {
            let data = try Data(contentsOf: plistURL)
            guard let plist = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [String: Any] else {
                throw AppInfoTestError.invalidInfoPlist
            }
            return plist
        }
        directory.deleteLastPathComponent()
    }

    throw AppInfoTestError.projectRootNotFound
}
