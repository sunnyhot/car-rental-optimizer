import Foundation

struct VehicleReferenceRateLimitError: LocalizedError {
    let retryAfter: Date
    var errorDescription: String? { "车型资料源限流，请稍后重试。" }
}

actor VehicleReferenceRequestPacer {
    private let minimumInterval: TimeInterval
    private var nextRequest = Date.distantPast
    private var cooldown: Date?

    init(minimumInterval: TimeInterval = 1) { self.minimumInterval = max(0, minimumInterval) }

    func waitForPermit() async throws {
        while true {
            try Task.checkCancellation()
            let now = Date()
            if let cooldown, cooldown > now { throw VehicleReferenceRateLimitError(retryAfter: cooldown) }
            let wait = nextRequest.timeIntervalSince(now)
            if wait <= 0 { nextRequest = now.addingTimeInterval(minimumInterval); return }
            try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        }
    }

    func registerRateLimit(until date: Date) {
        cooldown = max(cooldown ?? .distantPast, date)
    }

    func retryAfterDate() -> Date? {
        guard let cooldown, cooldown > Date() else { return nil }
        return cooldown
    }
}

func vehicleReferenceRetryDate(_ header: String?, now: Date = Date()) -> Date {
    if let header, let seconds = Double(header), seconds.isFinite, seconds >= 0 {
        return now.addingTimeInterval(max(1, seconds))
    }
    if let header {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
        if let date = formatter.date(from: header), date > now { return date }
    }
    return now.addingTimeInterval(60)
}
