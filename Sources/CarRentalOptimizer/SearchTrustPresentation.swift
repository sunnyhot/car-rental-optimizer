import CarRentalDomain
import Foundation

enum SearchPreflightSeverity: Equatable {
    case warning
    case blocking
}

struct SearchPreflightIssue: Equatable, Identifiable {
    let id: String
    let severity: SearchPreflightSeverity
    let title: String
    let message: String
}

struct SearchPreflightResult: Equatable {
    let issues: [SearchPreflightIssue]

    var hasBlockingIssue: Bool {
        issues.contains { $0.severity == .blocking }
    }
}

func validateSearchPreflight(_ request: SearchRequest) -> SearchPreflightResult {
    var issues: [SearchPreflightIssue] = []
    let origin = request.originLabel.trimmingCharacters(in: .whitespacesAndNewlines)
    let vehicleQuery = request.vehicleQuery.trimmingCharacters(in: .whitespacesAndNewlines)

    if request.platforms.isEmpty {
        issues.append(SearchPreflightIssue(
            id: "platforms-empty",
            severity: .blocking,
            title: "请选择平台",
            message: "至少选择一嗨或神州中的一个平台后才能开始比较。"
        ))
    }

    if origin.isEmpty {
        issues.append(SearchPreflightIssue(
            id: "origin-empty",
            severity: .warning,
            title: "当前位置为空",
            message: "地址为空时平台查询可能无法开始，请输入出发地或使用定位。"
        ))
    }

    if AppDateRules.parseRequestDate(request.pickupAt) == nil || AppDateRules.parseRequestDate(request.returnAt) == nil {
        issues.append(SearchPreflightIssue(
            id: "date-format-invalid",
            severity: .blocking,
            title: "日期格式异常",
            message: "取还车日期需要是 yyyy-MM-dd 格式。"
        ))
    }

    if vehicleQuery.isEmpty {
        issues.append(SearchPreflightIssue(
            id: "vehicle-empty",
            severity: .warning,
            title: "未指定车型",
            message: "车型为空时会比较半径内可识别车型，不会按具体车型去重。"
        ))
    }

    if request.radiusKm >= 300 && vehicleQuery.count >= 6 {
        issues.append(SearchPreflightIssue(
            id: "specific-vehicle-wide-radius",
            severity: .warning,
            title: "搜索范围较大",
            message: "具体车型配合大半径会查询更多门店，结果可能更慢，也更容易遇到平台风控。"
        ))
    }

    return SearchPreflightResult(issues: issues)
}

struct SearchDiagnosticSummary: Equatable {
    let queriedPlatforms: [PlatformId]
    let successfulPlatforms: [PlatformId]
    let failedStatuses: [PlatformEvidenceStatus]
    let listingCount: Int
    let visibleResultCount: Int
    let routeEstimateStatus: String
    let notes: [String]

    static let empty = SearchDiagnosticSummary(
        queriedPlatforms: [],
        successfulPlatforms: [],
        failedStatuses: [],
        listingCount: 0,
        visibleResultCount: 0,
        routeEstimateStatus: "尚未估算路线",
        notes: []
    )

    static func make(
        evidenceResults: [PlatformEvidenceResult],
        recommendations: [Recommendation]
    ) -> SearchDiagnosticSummary {
        let queriedPlatforms = evidenceResults.map(\.platform)
        let successfulPlatforms = evidenceResults
            .filter { $0.status.kind == .ready }
            .map(\.platform)
        let failedStatuses = evidenceResults
            .map(\.status)
            .filter { $0.kind != .ready }
        let listingCount = evidenceResults.reduce(0) { $0 + $1.listings.count }
        let routeEstimateStatus = recommendations.isEmpty ? "未生成路线估算" : "路线估算已参与排序"
        let notes = failedStatuses.map { "\($0.platform.label)：\($0.message)" }

        return SearchDiagnosticSummary(
            queriedPlatforms: queriedPlatforms,
            successfulPlatforms: successfulPlatforms,
            failedStatuses: failedStatuses,
            listingCount: listingCount,
            visibleResultCount: recommendations.count,
            routeEstimateStatus: routeEstimateStatus,
            notes: notes
        )
    }
}

struct SearchRecoveryAction: Equatable, Identifiable {
    let id: String
    let title: String
    let message: String
    let systemImage: String
    let opensEhiLogin: Bool
    let opensPlatform: Bool

    static func actions(for status: PlatformEvidenceStatus) -> [SearchRecoveryAction] {
        switch status.kind {
        case .loginRequired:
            if status.platform == .ehi {
                return [
                    SearchRecoveryAction(
                        id: "ehi-login",
                        title: "登录一嗨",
                        message: "登录后会复用本机保存的 1hai session，再重试同一查询。",
                        systemImage: "person.badge.key.fill",
                        opensEhiLogin: true,
                        opensPlatform: false
                    ),
                    retrySameRequest,
                ]
            }
            if status.platform == .carInc {
                return [
                    SearchRecoveryAction(
                        id: "carinc-login",
                        title: "登录神州",
                        message: "登录后会复用神州官方页面的 session，再重试同一查询补全基础服务费。",
                        systemImage: "person.badge.key.fill",
                        opensEhiLogin: false,
                        opensPlatform: false
                    ),
                    retrySameRequest,
                ]
            }
            return [openPlatform, retrySameRequest]
        case .captchaRequired:
            return [
                SearchRecoveryAction(
                    id: "refresh-login",
                    title: "刷新验证页",
                    message: "平台要求验证码或安全验证，刷新登录页后再重试。",
                    systemImage: "shield.lefthalf.filled",
                    opensEhiLogin: status.platform == .ehi,
                    opensPlatform: status.platform != .ehi
                ),
                retrySameRequest,
            ]
        case .parseFailed:
            return [retryLater, openPlatform]
        case .unavailable:
            return [
                SearchRecoveryAction(
                    id: "adjust-conditions",
                    title: "调整条件",
                    message: "可放宽车型、扩大半径或更换取还车日期后重新比较。",
                    systemImage: "slider.horizontal.3",
                    opensEhiLogin: false,
                    opensPlatform: false
                ),
                retryLater,
            ]
        case .waitingForEvidence:
            return [retrySameRequest]
        case .ready:
            return []
        }
    }

    private static let retrySameRequest = SearchRecoveryAction(
        id: "retry-same-request",
        title: "重试本次查询",
        message: "保留当前条件并重新调用平台接口。",
        systemImage: "arrow.clockwise",
        opensEhiLogin: false,
        opensPlatform: false
    )

    private static let retryLater = SearchRecoveryAction(
        id: "retry-later",
        title: "稍后重试",
        message: "平台接口或字段可能临时变化，稍后重试可确认是否恢复。",
        systemImage: "clock.arrow.circlepath",
        opensEhiLogin: false,
        opensPlatform: false
    )

    private static let openPlatform = SearchRecoveryAction(
        id: "open-platform",
        title: "打开原始平台",
        message: "在官方页面复核实时可订价格和门店状态。",
        systemImage: "arrow.up.right.square",
        opensEhiLogin: false,
        opensPlatform: true
    )
}

enum QuoteCredibilityLevel: Equatable {
    case complete
    case reviewRecommended
    case blocked
}

struct QuoteCredibility: Equatable {
    let level: QuoteCredibilityLevel
    let title: String
    let message: String
    let systemImage: String

    static func make(for recommendation: Recommendation) -> QuoteCredibility {
        let warnings = recommendation.warnings

        if warnings.contains(.loginRequired) || warnings.contains(.captchaRequired) {
            return QuoteCredibility(
                level: .blocked,
                title: "平台验证受限",
                message: "平台要求登录或验证后才能确认完整报价。",
                systemImage: "person.crop.circle.badge.exclamationmark"
            )
        }

        if warnings.contains(.partialPrice) {
            return QuoteCredibility(
                level: .reviewRecommended,
                title: "部分费用待复核",
                message: "平台未完整返回服务费、保险或异店还车费，下单前请打开原始平台复核。",
                systemImage: "exclamationmark.circle.fill"
            )
        }

        if warnings.contains(.mapCostMissing) {
            return QuoteCredibility(
                level: .reviewRecommended,
                title: "路线估算缺失",
                message: "交通成本暂不可用，当前排序主要参考租车价格。",
                systemImage: "map.fill"
            )
        }

        if warnings.contains(.crossCityPickup) {
            return QuoteCredibility(
                level: .reviewRecommended,
                title: "跨城/异店风险",
                message: "跨城或异店方案需要额外复核门店营业时间、交通衔接和平台费用。",
                systemImage: "arrow.triangle.swap"
            )
        }

        if recommendation.listing.dataCompleteness < 0.9 {
            return QuoteCredibility(
                level: .reviewRecommended,
                title: "报价完整度偏低",
                message: "平台返回字段不够完整，下单前请复核总价。",
                systemImage: "doc.text.magnifyingglass"
            )
        }

        return QuoteCredibility(
            level: .complete,
            title: "完整报价",
            message: "平台返回的价格字段较完整，仍建议下单前复核实时可订价格。",
            systemImage: "checkmark.seal.fill"
        )
    }
}

struct RetainedResultsNotice: Equatable {
    let title: String
    let message: String
    let lastSuccessfulSearchAt: Date

    static func make(lastSuccessfulSearchAt: Date) -> RetainedResultsNotice {
        RetainedResultsNotice(
            title: "显示上次成功结果",
            message: "本次查询未完成，当前候选来自上次成功查询，请复核时间和平台实时价格。",
            lastSuccessfulSearchAt: lastSuccessfulSearchAt
        )
    }
}
