/// Application-wide constants and version info.
///
/// Keep version numbers in sync with:
/// - Sources/CarRentalOptimizer/Resources/Info.plist (CFBundleShortVersionString, CFBundleVersion)
/// - appcast/appcast.xml (sparkle:shortVersionString, sparkle:version)
///
/// When bumping the version:
/// 1. Update `version` here
/// 2. Update `CFBundleShortVersionString` and increment `CFBundleVersion` in Info.plist
/// 3. Build, archive, generate_appcast, and publish
enum AppInfo {
    static let appName = "租车总成本比较"
    static let bundleIdentifier = "com.carrental.optimizer"
    static let version = "0.2.4"
    static let build = "5"
}
