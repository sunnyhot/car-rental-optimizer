import CarRentalDomain
import Foundation

enum ComparisonSectionID: String, CaseIterable, Identifiable {
    case summary, cost, route, vehicle, trust
    var id: String { rawValue }

    var title: String {
        switch self {
        case .summary: return "决策摘要"
        case .cost: return "费用"
        case .route: return "门店与路线"
        case .vehicle: return "车型"
        case .trust: return "可信度与风险"
        }
    }
}

enum ComparisonCellTone: Equatable {
    case standard, advantage, warning, unavailable
}

struct ComparisonCell: Equatable, Identifiable {
    let candidateID: String
    let text: String
    let comparisonKey: String
    var tone: ComparisonCellTone = .standard
    var id: String { candidateID }
}

struct ComparisonRow: Equatable, Identifiable {
    let id: String
    let label: String
    let cells: [ComparisonCell]
    var isCore = false

    var hasDifferences: Bool {
        Set(cells.map(\.comparisonKey)).count > 1
    }
}

struct ComparisonSection: Equatable, Identifiable {
    let id: ComparisonSectionID
    let rows: [ComparisonRow]
    var title: String { id.title }
}

enum ComparisonPresentation {
    static func sections(
        candidates: [Recommendation],
        insightStates: [String: ComparisonInsightState],
        onlyDifferences: Bool
    ) -> [ComparisonSection] {
        let sections = [
            ComparisonSection(id: .summary, rows: summaryRows(candidates)),
            ComparisonSection(id: .cost, rows: costRows(candidates)),
            ComparisonSection(id: .route, rows: routeRows(candidates)),
            ComparisonSection(id: .vehicle, rows: vehicleRows(candidates, insightStates: insightStates)),
            ComparisonSection(id: .trust, rows: trustRows(candidates)),
        ]
        guard onlyDifferences else { return sections }
        return sections.map { section in
            ComparisonSection(id: section.id, rows: section.rows.filter { $0.isCore || $0.hasDifferences })
        }
    }

    private static func summaryRows(_ values: [Recommendation]) -> [ComparisonRow] {
        [
            textRow(id: "platform", label: "平台", values: values) { $0.listing.platform.label },
            textRow(id: "vehicle-name", label: "车型", values: values) { $0.listing.vehicleName },
            minimumRow(id: "best-total", label: "总成本", values: values, value: \.bestTotal, format: formatMoney, isCore: true),
            textRow(id: "store", label: "门店", values: values) { $0.listing.store.name },
        ]
    }

    private static func costRows(_ values: [Recommendation]) -> [ComparisonRow] {
        [
            minimumRow(id: "rental-total", label: "租车小计", values: values, value: \.rentalTotal, format: formatMoney),
            minimumRow(id: "base-price", label: "车辆租金", values: values, value: \.listing.basePrice, format: formatMoney),
            minimumRow(id: "platform-fees", label: "平台费", values: values, value: \.listing.platformFees, format: formatMoney),
            minimumRow(id: "insurance-fees", label: "保险费", values: values, value: \.listing.insuranceFees, format: formatMoney),
            minimumRow(id: "one-way-fee", label: "异店费", values: values, value: \.listing.oneWayFee, format: formatMoney),
            minimumRow(id: "arrival-cost", label: "最优到店成本", values: values, value: bestRouteCost, format: formatMoney),
        ]
    }

    private static func routeRows(_ values: [Recommendation]) -> [ComparisonRow] {
        [
            minimumRow(id: "store-distance", label: "门店距离", values: values, value: \.listing.store.distanceKm, format: { String(format: "%.1f km", $0) }),
            textRow(id: "store-address", label: "门店地址", values: values) { $0.listing.store.address },
            textRow(id: "store-hours", label: "营业时间", values: values) { $0.listing.store.hours },
            minimumRow(id: "taxi-cost", label: "打车成本", values: values, value: \.taxiRoute.cost, format: formatMoney),
            minimumRow(id: "taxi-duration", label: "打车时间", values: values, value: \.taxiRoute.durationMinutes, format: { "\(Int($0.rounded())) 分" }),
            minimumRow(id: "transit-cost", label: "公交成本", values: values, value: \.transitRoute.cost, format: formatMoney),
            minimumRow(id: "transit-duration", label: "公交时间", values: values, value: \.transitRoute.durationMinutes, format: { "\(Int($0.rounded())) 分" }),
        ]
    }

    private static func vehicleRows(
        _ values: [Recommendation],
        insightStates: [String: ComparisonInsightState]
    ) -> [ComparisonRow] {
        let insightCells = values.map { candidate in
            guard let state = insightStates[candidate.id] else {
                return ComparisonCell(candidateID: candidate.id, text: "未确认", comparisonKey: "unknown", tone: .unavailable)
            }
            let insight = state.insight
            let tone: ComparisonCellTone = {
                if case .fallback = state { return .warning }
                return .standard
            }()
            return ComparisonCell(candidateID: candidate.id, text: insight.shortSummary, comparisonKey: insight.shortSummary, tone: tone)
        }

        let insightsByID = insightStates.mapValues(\.insight)
        let basicLabels = orderedUnique(values.flatMap { candidate in
            insightsByID[candidate.id]?.formattedBasicSpecs.map(\.label) ?? []
        })
        let configurationLabels = VehicleInsight.commonConfigurationFeatureNames

        let basicRows = basicLabels.map { label in
            insightFactRow(
                id: "spec-\(label)",
                label: label,
                candidates: values,
                insightsByID: insightsByID,
                facts: { $0.formattedBasicSpecs }
            )
        }
        let configurationRows = configurationLabels.map { label in
            insightFactRow(
                id: "feature-\(label)",
                label: label,
                candidates: values,
                insightsByID: insightsByID,
                facts: { $0.formattedConfigurationFacts }
            )
        }

        return [
            textRow(id: "vehicle-class", label: "车型类别", values: values) { $0.listing.vehicleClass },
            textRow(id: "vehicle-match", label: "匹配程度", values: values) { $0.match.displayLabel ?? "未指定" },
            ComparisonRow(id: "vehicle-insight", label: "车型资料", cells: insightCells),
        ] + basicRows + configurationRows
    }

    private static func trustRows(_ values: [Recommendation]) -> [ComparisonRow] {
        let maxCompleteness = values.map(\.listing.dataCompleteness).max()
        return [
            ComparisonRow(
                id: "completeness",
                label: "费用完整度",
                cells: values.map { value in
                    let percent = Int((value.listing.dataCompleteness * 100).rounded())
                    return ComparisonCell(
                        candidateID: value.id,
                        text: "\(percent)%",
                        comparisonKey: "\(percent)",
                        tone: value.listing.dataCompleteness == maxCompleteness ? .advantage : .standard
                    )
                }
            ),
            textRow(id: "credibility", label: "报价可信度", values: values) { QuoteCredibility.make(for: $0).title },
            textRow(id: "warnings", label: "风险", values: values) { recommendation in
                recommendation.warnings.isEmpty
                    ? "无已知风险"
                    : renderWarnings(recommendation.warnings)
            },
        ]
    }

    private static func textRow(
        id: String,
        label: String,
        values: [Recommendation],
        text: (Recommendation) -> String
    ) -> ComparisonRow {
        ComparisonRow(
            id: id,
            label: label,
            cells: values.map {
                let rendered = text($0)
                return ComparisonCell(candidateID: $0.id, text: rendered, comparisonKey: rendered)
            }
        )
    }

    private static func minimumRow(
        id: String,
        label: String,
        values: [Recommendation],
        value: (Recommendation) -> Double,
        format: (Double) -> String,
        isCore: Bool = false
    ) -> ComparisonRow {
        let minimum = values.map(value).min()
        return ComparisonRow(
            id: id,
            label: label,
            cells: values.map { recommendation in
                let raw = value(recommendation)
                return ComparisonCell(
                    candidateID: recommendation.id,
                    text: format(raw),
                    comparisonKey: String(format: "%.4f", raw),
                    tone: minimum.map { raw == $0 } == true ? .advantage : .standard
                )
            },
            isCore: isCore
        )
    }

    private static func bestRouteCost(_ value: Recommendation) -> Double {
        value.bestRouteMode == .taxi ? value.taxiRoute.cost : value.transitRoute.cost
    }

    private static func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private static func insightFactRow(
        id: String,
        label: String,
        candidates: [Recommendation],
        insightsByID: [String: VehicleInsight],
        facts: (VehicleInsight) -> [VehicleInsightFact]
    ) -> ComparisonRow {
        ComparisonRow(
            id: id,
            label: label,
            cells: candidates.map { candidate in
                let fact = insightsByID[candidate.id].flatMap { insight in
                    facts(insight).first { $0.label == label }
                }
                guard let fact else {
                    return ComparisonCell(candidateID: candidate.id, text: "未确认", comparisonKey: "unknown", tone: .unavailable)
                }
                return ComparisonCell(candidateID: candidate.id, text: fact.value, comparisonKey: fact.value)
            }
        )
    }
}
