import AppKit
import Foundation

struct AppVersion: Comparable, Equatable {
    private let components: [Int]

    init(_ rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutPrefix = trimmed.hasPrefix("v") || trimmed.hasPrefix("V")
            ? String(trimmed.dropFirst())
            : trimmed
        let numericPart = withoutPrefix.split(separator: "-", maxSplits: 1).first.map(String.init) ?? withoutPrefix
        components = numericPart
            .split(separator: ".")
            .map { Int($0) ?? 0 }
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let length = max(lhs.components.count, rhs.components.count)
        for index in 0..<length {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right {
                return left < right
            }
        }
        return false
    }
}

struct GitHubRelease: Decodable, Equatable {
    let tagName: String
    let name: String?
    let htmlURL: URL

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
    }

    var displayVersion: String {
        if tagName.hasPrefix("v") || tagName.hasPrefix("V") {
            return String(tagName.dropFirst())
        }
        return tagName
    }

    var packageURL: URL {
        URL(string: "https://github.com/sunnyhot/car-rental-optimizer/releases/download/\(tagName)/CarRentalOptimizer-\(tagName).zip")!
    }
}

protocol ReleaseFetching {
    func latestRelease() async throws -> GitHubRelease
}

protocol ReleaseDataLoading {
    func loadData(for request: URLRequest) async throws -> (Data, URLResponse)
}

protocol ReleaseArchiveDownloading {
    func downloadArchive(from url: URL) async throws -> URL
}

extension URLSession: ReleaseDataLoading {
    func loadData(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request)
    }
}

extension URLSession: ReleaseArchiveDownloading {
    func downloadArchive(from url: URL) async throws -> URL {
        var request = URLRequest(url: url)
        request.setValue("CarRentalOptimizer/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        let (temporaryURL, response) = try await download(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }
        return temporaryURL
    }
}

struct GitHubReleaseFetcher: ReleaseFetching {
    let latestReleaseURL: URL
    private let dataLoader: any ReleaseDataLoading

    init(
        latestReleaseURL: URL = URL(string: "https://github.com/sunnyhot/car-rental-optimizer/releases/latest")!,
        dataLoader: any ReleaseDataLoading = URLSession.shared
    ) {
        self.latestReleaseURL = latestReleaseURL
        self.dataLoader = dataLoader
    }

    func latestRelease() async throws -> GitHubRelease {
        var request = URLRequest(url: latestReleaseURL)
        request.httpMethod = "HEAD"
        request.setValue("CarRentalOptimizer/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        let (_, response) = try await dataLoader.loadData(for: request)
        try validateSuccess(response)

        let finalURL = response.url ?? latestReleaseURL
        guard let tagName = Self.releaseTag(from: finalURL) else {
            throw URLError(.cannotParseResponse)
        }

        return GitHubRelease(
            tagName: tagName,
            name: nil,
            htmlURL: finalURL
        )
    }

    private func validateSuccess(_ response: URLResponse) throws {
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }
    }

    static func releaseTag(from url: URL) -> String? {
        let pathComponents = url.pathComponents
        guard let tagIndex = pathComponents.firstIndex(of: "tag") else {
            return nil
        }
        let versionIndex = pathComponents.index(after: tagIndex)
        guard pathComponents.indices.contains(versionIndex) else {
            return nil
        }
        return pathComponents[versionIndex]
    }
}

protocol UpdateInstalling {
    func prepareAndLaunchInstaller(for release: GitHubRelease) async throws
}

enum UpdateInstallError: LocalizedError {
    case appBundleMissing
    case downloadedBundleInvalid(URL)
    case cannotWriteInstallerScript

    var errorDescription: String? {
        switch self {
        case .appBundleMissing:
            return "当前应用不是从 .app bundle 启动，无法自动替换安装。"
        case let .downloadedBundleInvalid(url):
            return "下载包中的应用结构无效：\(url.path)"
        case .cannotWriteInstallerScript:
            return "无法写入后台安装脚本。"
        }
    }
}

struct MacReleaseInstaller: UpdateInstalling {
    private let downloader: ReleaseArchiveDownloading
    private let fileManager: FileManager

    init(
        downloader: ReleaseArchiveDownloading = URLSession.shared,
        fileManager: FileManager = .default
    ) {
        self.downloader = downloader
        self.fileManager = fileManager
    }

    func prepareAndLaunchInstaller(for release: GitHubRelease) async throws {
        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent("CarRentalOptimizerUpdate-\(UUID().uuidString)", isDirectory: true)
        let archiveURL = try await downloader.downloadArchive(from: release.packageURL)

        do {
            try fileManager.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
            let archiveCopyURL = temporaryRoot.appendingPathComponent(release.packageURL.lastPathComponent)
            try fileManager.copyItem(at: archiveURL, to: archiveCopyURL)

            let extractionURL = temporaryRoot.appendingPathComponent("Extracted", isDirectory: true)
            try fileManager.createDirectory(at: extractionURL, withIntermediateDirectories: true)
            try runProcess("/usr/bin/ditto", arguments: ["-x", "-k", archiveCopyURL.path, extractionURL.path])

            let sourceAppURL = extractionURL.appendingPathComponent("\(AppInfo.appName).app", isDirectory: true)
            try validateAppBundle(at: sourceAppURL)
            try runProcess("/usr/bin/codesign", arguments: ["--verify", "--deep", "--strict", sourceAppURL.path])

            let destinationAppURL = try currentAppBundleURL()
            let scriptURL = try writeInstallerScript(in: temporaryRoot)
            try launchInstallerScript(
                scriptURL: scriptURL,
                sourceAppURL: sourceAppURL,
                destinationAppURL: destinationAppURL,
                temporaryRoot: temporaryRoot
            )
        } catch {
            try? fileManager.removeItem(at: temporaryRoot)
            throw error
        }
    }

    private func currentAppBundleURL() throws -> URL {
        let bundleURL = Bundle.main.bundleURL
        guard bundleURL.pathExtension == "app" else {
            throw UpdateInstallError.appBundleMissing
        }
        return bundleURL
    }

    private func validateAppBundle(at appURL: URL) throws {
        let executableURL = appURL.appendingPathComponent("Contents/MacOS/CarRentalOptimizer")
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: appURL.path, isDirectory: &isDirectory), isDirectory.boolValue,
              fileManager.isExecutableFile(atPath: executableURL.path) else {
            throw UpdateInstallError.downloadedBundleInvalid(appURL)
        }
    }

    private func writeInstallerScript(in directory: URL) throws -> URL {
        let scriptURL = directory.appendingPathComponent("install-update.sh")
        let script = """
        #!/bin/zsh
        set -euo pipefail

        APP_PID="$1"
        SOURCE_APP="$2"
        DEST_APP="$3"
        TMP_DIR="$4"

        for _ in {1..100}; do
          if ! kill -0 "$APP_PID" 2>/dev/null; then
            break
          fi
          sleep 0.2
        done

        if kill -0 "$APP_PID" 2>/dev/null; then
          kill "$APP_PID" 2>/dev/null || true
          sleep 0.5
        fi

        rm -rf "$DEST_APP"
        ditto "$SOURCE_APP" "$DEST_APP"
        xattr -cr "$DEST_APP" || true
        codesign --verify --deep --strict "$DEST_APP"
        open -n "$DEST_APP"
        rm -rf "$TMP_DIR"
        """

        guard let data = script.data(using: .utf8) else {
            throw UpdateInstallError.cannotWriteInstallerScript
        }
        try data.write(to: scriptURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        return scriptURL
    }

    private func launchInstallerScript(
        scriptURL: URL,
        sourceAppURL: URL,
        destinationAppURL: URL,
        temporaryRoot: URL
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            scriptURL.path,
            String(ProcessInfo.processInfo.processIdentifier),
            sourceAppURL.path,
            destinationAppURL.path,
            temporaryRoot.path,
        ]
        if let null = FileHandle(forWritingAtPath: "/dev/null") {
            process.standardOutput = null
            process.standardError = null
        }
        try process.run()
    }

    private func runProcess(_ executablePath: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        if let null = FileHandle(forWritingAtPath: "/dev/null") {
            process.standardOutput = null
            process.standardError = null
        }
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw URLError(.badServerResponse)
        }
    }
}

struct UpdateAlert: Identifiable, Equatable {
    enum Kind: String, Equatable {
        case updateAvailable
        case upToDate
        case failed
        case installFailed = "install-failed"
    }

    let kind: Kind
    let title: String
    let message: String
    let releaseURL: URL?

    var id: String {
        "\(kind.rawValue)-\(title)-\(releaseURL?.absoluteString ?? "")"
    }
}

@MainActor
final class UpdateChecker: ObservableObject {
    @Published private(set) var isChecking = false
    @Published private(set) var isInstalling = false
    @Published var alert: UpdateAlert?

    private let currentVersion: String
    private let releaseFetcher: ReleaseFetching
    private let installer: UpdateInstalling
    private let quitHandler: @MainActor () -> Void
    private var availableRelease: GitHubRelease?

    init(
        currentVersion: String = AppInfo.version,
        releaseFetcher: ReleaseFetching = GitHubReleaseFetcher(),
        installer: UpdateInstalling = MacReleaseInstaller(),
        quitHandler: @escaping @MainActor () -> Void = { NSApplication.shared.terminate(nil) }
    ) {
        self.currentVersion = currentVersion
        self.releaseFetcher = releaseFetcher
        self.installer = installer
        self.quitHandler = quitHandler
    }

    func checkForUpdates() async {
        guard !isChecking else { return }

        isChecking = true
        defer { isChecking = false }

        do {
            let release = try await releaseFetcher.latestRelease()
            if AppVersion(release.tagName) > AppVersion(currentVersion) {
                availableRelease = release
                alert = UpdateAlert(
                    kind: .updateAvailable,
                    title: "发现新版本 \(release.displayVersion)",
                    message: release.name ?? "可自动下载并重启安装。",
                    releaseURL: release.htmlURL
                )
            } else {
                availableRelease = nil
                alert = UpdateAlert(
                    kind: .upToDate,
                    title: "已是最新版本",
                    message: "当前版本 \(currentVersion) 已经是最新发布版本。",
                    releaseURL: release.htmlURL
                )
            }
        } catch {
            availableRelease = nil
            alert = UpdateAlert(
                kind: .failed,
                title: "检查更新失败",
                message: "无法读取 GitHub Release：\(error.localizedDescription)",
                releaseURL: nil
            )
        }
    }

    func installAvailableUpdate() async {
        guard !isInstalling, let release = availableRelease else { return }

        isInstalling = true
        alert = nil
        defer { isInstalling = false }

        do {
            try await installer.prepareAndLaunchInstaller(for: release)
            quitHandler()
        } catch {
            alert = UpdateAlert(
                kind: .installFailed,
                title: "自动升级失败",
                message: "无法自动安装 \(release.displayVersion)：\(error.localizedDescription)",
                releaseURL: release.htmlURL
            )
        }
    }

    func openReleasePage(_ url: URL?) {
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }
}
