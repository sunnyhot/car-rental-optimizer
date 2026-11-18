import Foundation

/// Explicitly enabled during local troubleshooting. Never logs cookies or response bodies.
func traceLiveSearch(_ message: @autoclosure () -> String) {
    guard ProcessInfo.processInfo.environment["CAR_RENTAL_LIVE_PROBE"] == "1" else { return }
    print("LIVE_SEARCH \(message())")
}
