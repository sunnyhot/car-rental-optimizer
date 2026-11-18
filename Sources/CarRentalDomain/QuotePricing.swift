import Foundation

public extension RentalListing {
    /// Unknown fees are not zero. Legacy numeric fields remain storage-compatible.
    var hasCompleteRentalPrice: Bool {
        if let confirmedQuote { return confirmedQuote.isValid }
        return dataCompleteness >= 0.9 && !warnings.contains(.partialPrice)
            && !warnings.contains(.loginRequired) && !warnings.contains(.captchaRequired)
            && [basePrice, platformFees, insuranceFees, oneWayFee].allSatisfy { $0.isFinite && $0 >= 0 }
    }
}
