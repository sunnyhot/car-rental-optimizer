import Foundation

struct ZucheRateLimitError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

func isZucheRateLimitMessage(_ message: String) -> Bool {
    let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines)
    return normalized.contains("访问频繁") || normalized.contains("请求过于频繁")
}

actor ZucheRequestThrottle {
    private let minimumInterval: TimeInterval
    private var nextAllowedAt = Date.distantPast

    init(minimumInterval: TimeInterval) {
        self.minimumInterval = max(0, minimumInterval)
    }

    func waitForPermit() async throws {
        while true {
            try Task.checkCancellation()
            let now = Date()
            let wait = nextAllowedAt.timeIntervalSince(now)
            if wait <= 0 {
                nextAllowedAt = now.addingTimeInterval(minimumInterval)
                return
            }
            try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        }
    }

    func registerRateLimit(cooldown: TimeInterval) {
        let deadline = Date().addingTimeInterval(max(0, cooldown))
        if deadline > nextAllowedAt {
            nextAllowedAt = deadline
        }
    }
}

func withZucheRateLimitRetry<T>(
    throttle: ZucheRequestThrottle,
    maxAttempts: Int = 3,
    baseCooldown: TimeInterval = 0.75,
    operation: () async throws -> T
) async throws -> T {
    precondition(maxAttempts > 0)
    var attempt = 1

    while true {
        try await throttle.waitForPermit()
        do {
            return try await operation()
        } catch let error as ZucheRateLimitError {
            guard attempt < maxAttempts else { throw error }
            await throttle.registerRateLimit(cooldown: baseCooldown * Double(attempt))
            attempt += 1
        }
    }
}
