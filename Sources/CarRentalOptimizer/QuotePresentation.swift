import CarRentalDomain
import Foundation

enum QuotePresentation {
    static func totalLabel(_ quote: Recommendation) -> String {
        quote.listing.hasCompleteRentalPrice ? "租车 + 到店估算" : "已知费用 + 到店估算"
    }

    static func totalValue(_ quote: Recommendation) -> String {
        (quote.listing.hasCompleteRentalPrice ? "约 " : "待补全 · ") + formatMoney(quote.bestTotal)
    }

    static func rentalLabel(_ quote: Recommendation) -> String {
        if quote.listing.confirmedQuote?.isValid == true { return "平台确认应付" }
        return quote.listing.hasCompleteRentalPrice ? "租车小计" : "已知租车费用"
    }

    static func feeText(_ amount: Double, listing: RentalListing) -> String {
        if listing.confirmedQuote?.isValid == true { return "见平台明细" }
        if amount == 0 && !listing.hasCompleteRentalPrice { return "未确认/未单列" }
        return formatMoney(amount)
    }

    static let scopeNotice = "仅比较已查门店；到店交通为估算，不含还车后接驳、油电及过路停车。登录核价仅反映确认页当前方案，优惠和保障变更后需重新查询。费用未完整时不代表最终应付价。"
}
