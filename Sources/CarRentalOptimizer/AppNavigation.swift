import SwiftUI

enum AppWorkspace: String, CaseIterable, Identifiable {
    case comparison
    case monitoring

    var id: String { rawValue }

    var title: String {
        switch self {
        case .comparison: return "比价工作台"
        case .monitoring: return "价格监控"
        }
    }

    var systemImage: String {
        switch self {
        case .comparison: return "point.3.connected.trianglepath.dotted"
        case .monitoring: return "chart.xyaxis.line"
        }
    }
}

@MainActor
final class AppNavigationModel: ObservableObject {
    @Published var selectedWorkspace: AppWorkspace = .comparison

    func showComparison() {
        selectedWorkspace = .comparison
    }

    func showMonitoring() {
        selectedWorkspace = .monitoring
    }
}
