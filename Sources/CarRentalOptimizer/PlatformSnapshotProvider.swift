import CarRentalDomain
import Foundation

struct PlatformPageSnapshot: Equatable {
    let platform: PlatformId
    let title: String
    let url: String
    let text: String
}

@MainActor
protocol PlatformSnapshotProviding: AnyObject {
    func snapshot(for platform: PlatformId) async throws -> PlatformPageSnapshot
}

@MainActor
final class EmptyPlatformSnapshotProvider: PlatformSnapshotProviding {
    func snapshot(for platform: PlatformId) async throws -> PlatformPageSnapshot {
        PlatformPageSnapshot(
            platform: platform,
            title: platform.label,
            url: officialPlatformURL(for: platform),
            text: ""
        )
    }
}
