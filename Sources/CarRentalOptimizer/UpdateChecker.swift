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
}

protocol ReleaseFetching {
    func latestRelease() async throws -> GitHubRelease
}

protocol ReleaseDataLoading {
    func loadData(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: ReleaseDataLoading {
    func loadData(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request)
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

struct UpdateAlert: Identifiable, Equatable {
    enum Kind: String, Equatable {
        case updateAvailable
        case upToDate
        case failed
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
    @Published var alert: UpdateAlert?

    private let currentVersion: String
    private let releaseFetcher: ReleaseFetching

    init(
        currentVersion: String = AppInfo.version,
        releaseFetcher: ReleaseFetching = GitHubReleaseFetcher()
    ) {
        self.currentVersion = currentVersion
        self.releaseFetcher = releaseFetcher
    }

    func checkForUpdates() async {
        guard !isChecking else { return }

        isChecking = true
        defer { isChecking = false }

        do {
            let release = try await releaseFetcher.latestRelease()
            if AppVersion(release.tagName) > AppVersion(currentVersion) {
                alert = UpdateAlert(
                    kind: .updateAvailable,
                    title: "发现新版本 \(release.displayVersion)",
                    message: release.name ?? "有新的 GitHub Release 可以下载。",
                    releaseURL: release.htmlURL
                )
            } else {
                alert = UpdateAlert(
                    kind: .upToDate,
                    title: "已是最新版本",
                    message: "当前版本 \(currentVersion) 已经是最新发布版本。",
                    releaseURL: release.htmlURL
                )
            }
        } catch {
            alert = UpdateAlert(
                kind: .failed,
                title: "检查更新失败",
                message: "无法读取 GitHub Release：\(error.localizedDescription)",
                releaseURL: nil
            )
        }
    }

    func openReleasePage(_ url: URL?) {
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }
}
