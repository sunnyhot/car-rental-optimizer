import Foundation

/// The server's confirmation-page amount for the requested default booking options.
/// Not an amount already paid, and never reconstructed by adding fee rows.
public struct ConfirmedRentalQuote: Codable, Equatable {
    public let payableTotal: Double
    public let items: [ConfirmedRentalFee]
    public let checkedAt: Date
    public let sourceURL: String
    public let scope: String

    public init(payableTotal: Double, items: [ConfirmedRentalFee], checkedAt: Date, sourceURL: String, scope: String) {
        self.payableTotal = payableTotal
        self.items = items
        self.checkedAt = checkedAt
        self.sourceURL = sourceURL
        self.scope = scope
    }

    public var isValid: Bool { payableTotal.isFinite && payableTotal >= 0 }
}

public struct ConfirmedRentalFee: Codable, Equatable {
    public let name: String
    public let amount: Double?
    public let detail: String?

    public init(name: String, amount: Double?, detail: String? = nil) {
        self.name = name
        self.amount = amount
        self.detail = detail
    }
}
