import CarRentalDomain
import Foundation

enum MonitorInputError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}

func validateMonitorInput(_ request: SearchRequest, vehicleQuery: String, now: Date) throws {
    if let issue = validateSearchPreflight(request, now: now).issues.first(where: { $0.severity == .blocking }) {
        throw MonitorInputError.invalid(issue.message)
    }
    guard !vehicleQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw MonitorInputError.invalid("请输入需要监控的车型，不使用任意车型作为降价替代。")
    }
}
