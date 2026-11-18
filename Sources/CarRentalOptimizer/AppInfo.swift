import Foundation

/// Application-wide constants and version info.
///
/// Keep version numbers in sync with:
/// - native/Info.plist (CFBundleShortVersionString, CFBundleVersion)
/// - appcast/appcast.xml (sparkle:shortVersionString, sparkle:version)
///
/// When bumping the version:
/// 1. Update `version` here
/// 2. Update `CFBundleShortVersionString` and increment `CFBundleVersion` in Info.plist
/// 3. Build, archive, generate_appcast, and publish
enum AppInfo {
    /// Isolated UI validation: no startup location requests or saved monitor reads.
    static var isUIValidation: Bool { ProcessInfo.processInfo.arguments.contains("--ui-validation") }
    static let appName = "租车比价助手"
    static let bundleIdentifier = "com.carrental.optimizer"
    static let version = "0.9.28"
    static let build = "67"
}
