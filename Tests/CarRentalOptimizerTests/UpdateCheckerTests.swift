import Foundation
import Testing
@testable import CarRentalOptimizer

@Suite("Update checking")
@MainActor
struct UpdateCheckerTests {
    @Test("Version comparison handles v prefix and multi-digit components")
    func versionComparisonHandlesPrefixAndMultiDigitComponents() {
        #expect(AppVersion("v0.10.0") > AppVersion("0.9.9"))
        #expect(AppVersion("1.0") == AppVersion("1.0.0"))
        #expect(AppVersion("0.5.2") > AppVersion("0.5.1"))
    }

    @Test("Checker reports newer GitHub release")
    func checkerReportsNewerRelease() async {
        let checker = UpdateChecker(
            currentVersion: "0.4.0",
            releaseFetcher: StubReleaseFetcher(release: GitHubRelease(
                tagName: "v0.5.2",
                name: "租车比价助手 v0.5.2",
                htmlURL: URL(string: "https://github.com/sunnyhot/car-rental-optimizer/releases/tag/v0.5.2")!
            )),
            installer: StubUpdateInstaller()
        )

        await checker.checkForUpdates()

        #expect(checker.isChecking == false)
        #expect(checker.alert?.kind == .updateAvailable)
        #expect(checker.alert?.title == "发现新版本 0.5.2")
        #expect(checker.alert?.releaseURL?.absoluteString.contains("v0.5.2") == true)
    }

    @Test("Release package URL uses the GitHub asset naming convention")
    func releasePackageURLUsesGitHubAssetNamingConvention() {
        let release = GitHubRelease(
            tagName: "v0.6.1",
            name: nil,
            htmlURL: URL(string: "https://github.com/sunnyhot/car-rental-optimizer/releases/tag/v0.6.1")!
        )

        #expect(release.packageURL.absoluteString == "https://github.com/sunnyhot/car-rental-optimizer/releases/download/v0.6.1/CarRentalOptimizer-v0.6.1.zip")
    }

    @Test("Checker installs the available release and requests app quit")
    func checkerInstallsAvailableReleaseAndRequestsAppQuit() async {
        let installer = StubUpdateInstaller()
        var quitRequested = false
        let checker = UpdateChecker(
            currentVersion: "0.6.0",
            releaseFetcher: StubReleaseFetcher(release: GitHubRelease(
                tagName: "v0.6.1",
                name: "租车比价助手 v0.6.1",
                htmlURL: URL(string: "https://github.com/sunnyhot/car-rental-optimizer/releases/tag/v0.6.1")!
            )),
            installer: installer,
            quitHandler: { quitRequested = true }
        )

        await checker.checkForUpdates()
        await checker.installAvailableUpdate()

        #expect(installer.installedReleases.map(\.tagName) == ["v0.6.1"])
        #expect(installer.installedReleases.first?.packageURL.absoluteString.contains("CarRentalOptimizer-v0.6.1.zip") == true)
        #expect(quitRequested)
        #expect(checker.isInstalling == false)
    }

    @Test("Checker reports automatic install failures without quitting")
    func checkerReportsAutomaticInstallFailuresWithoutQuitting() async {
        let installer = StubUpdateInstaller(error: URLError(.cannotWriteToFile))
        var quitRequested = false
        let checker = UpdateChecker(
            currentVersion: "0.6.0",
            releaseFetcher: StubReleaseFetcher(release: GitHubRelease(
                tagName: "v0.6.1",
                name: "租车比价助手 v0.6.1",
                htmlURL: URL(string: "https://github.com/sunnyhot/car-rental-optimizer/releases/tag/v0.6.1")!
            )),
            installer: installer,
            quitHandler: { quitRequested = true }
        )

        await checker.checkForUpdates()
        await checker.installAvailableUpdate()

        #expect(checker.alert?.kind == .installFailed)
        #expect(checker.alert?.title == "自动升级失败")
        #expect(checker.alert?.releaseURL?.absoluteString.contains("v0.6.1") == true)
        #expect(!quitRequested)
        #expect(checker.isInstalling == false)
    }

    @Test("Checker reports current version up to date")
    func checkerReportsCurrentVersionUpToDate() async {
        let checker = UpdateChecker(
            currentVersion: "0.5.2",
            releaseFetcher: StubReleaseFetcher(release: GitHubRelease(
                tagName: "v0.5.2",
                name: "租车比价助手 v0.5.2",
                htmlURL: URL(string: "https://github.com/sunnyhot/car-rental-optimizer/releases/tag/v0.5.2")!
            )),
            installer: StubUpdateInstaller()
        )

        await checker.checkForUpdates()

        #expect(checker.alert?.kind == .upToDate)
        #expect(checker.alert?.title == "已是最新版本")
    }

    @Test("Checker reports fetch failures")
    func checkerReportsFetchFailures() async {
        let checker = UpdateChecker(
            currentVersion: "0.5.2",
            releaseFetcher: StubReleaseFetcher(error: URLError(.notConnectedToInternet)),
            installer: StubUpdateInstaller()
        )

        await checker.checkForUpdates()

        #expect(checker.alert?.kind == .failed)
        #expect(checker.alert?.title == "检查更新失败")
    }

    @Test("Fetcher reads latest release redirect without GitHub API")
    func fetcherReadsLatestReleaseRedirectWithoutGitHubAPI() async throws {
        let latestURL = URL(string: "https://github.com/sunnyhot/car-rental-optimizer/releases/latest")!
        let redirectedURL = URL(string: "https://github.com/sunnyhot/car-rental-optimizer/releases/tag/v0.5.3")!
        let dataLoader = StubReleaseDataLoader(results: [
            .success((Data(), httpResponse(url: redirectedURL, statusCode: 200))),
        ])
        let fetcher = GitHubReleaseFetcher(
            latestReleaseURL: latestURL,
            dataLoader: dataLoader
        )

        let release = try await fetcher.latestRelease()

        #expect(release.tagName == "v0.5.3")
        #expect(release.htmlURL == redirectedURL)
        #expect(dataLoader.requestedURLs == [latestURL])
        #expect(!dataLoader.requestedURLs.contains { $0.host == "api.github.com" })
    }

    @Test("Installer resolves app bundle from running application when executable lives outside bundle")
    func installerResolvesAppBundleFromRunningApplicationFallback() throws {
        let runtimeURL = URL(fileURLWithPath: "/Users/me/Library/Application Support/CarRentalOptimizer/runtime", isDirectory: true)
        let installedAppURL = URL(fileURLWithPath: "/Applications/租车比价助手.app", isDirectory: true)
        let resolver = CurrentAppBundleResolver(
            mainBundleURL: runtimeURL,
            runningApplicationBundleURL: installedAppURL
        )

        #expect(try resolver.currentAppBundleURL() == installedAppURL)
    }
}

private struct StubReleaseFetcher: ReleaseFetching {
    let release: GitHubRelease?
    let error: Error?

    init(release: GitHubRelease) {
        self.release = release
        self.error = nil
    }

    init(error: Error) {
        self.release = nil
        self.error = error
    }

    func latestRelease() async throws -> GitHubRelease {
        if let error {
            throw error
        }
        return release!
    }
}

private final class StubReleaseDataLoader: ReleaseDataLoading {
    private var results: [Result<(Data, URLResponse), Error>]
    private(set) var requestedURLs: [URL] = []

    init(results: [Result<(Data, URLResponse), Error>]) {
        self.results = results
    }

    func loadData(for request: URLRequest) async throws -> (Data, URLResponse) {
        if let url = request.url {
            requestedURLs.append(url)
        }
        guard !results.isEmpty else {
            throw URLError(.badServerResponse)
        }
        return try results.removeFirst().get()
    }
}

private final class StubUpdateInstaller: UpdateInstalling {
    private let error: Error?
    private(set) var installedReleases: [GitHubRelease] = []

    init(error: Error? = nil) {
        self.error = error
    }

    func prepareAndLaunchInstaller(for release: GitHubRelease) async throws {
        if let error {
            throw error
        }
        installedReleases.append(release)
    }
}

private func httpResponse(url: URL, statusCode: Int) -> HTTPURLResponse {
    HTTPURLResponse(
        url: url,
        statusCode: statusCode,
        httpVersion: "HTTP/1.1",
        headerFields: nil
    )!
}
