import Foundation

/// Matches a user's vehicle query against a rental listing's vehicle info.
public func matchVehicle(query: String, vehicleName: String, vehicleClass: String) -> VehicleMatch {
    let normalizedQuery = normalize(query)
    let normalizedName = normalize(vehicleName)
    let normalizedClass = normalize(vehicleClass)

    guard !normalizedQuery.isEmpty else {
        return VehicleMatch(kind: .notSpecified, score: 0, label: "未指定车型")
    }

    // Check for exact model match via aliases
    let aliases = MODEL_ALIASES[normalizedQuery] ?? [normalizedQuery]
    if aliases.contains(where: { normalizedName.contains(normalize($0)) }) {
        return VehicleMatch(kind: .exact, score: 1, label: "精确车型")
    }

    // Check for same vehicle family only for generic class queries.
    if let familyLabel = sameVehicleFamilyLabel(query: normalizedQuery, vehicleClass: normalizedClass, vehicleName: normalizedName) {
        return VehicleMatch(kind: .similarClass, score: 0.72, label: "同级 \(familyLabel) 替代")
    }

    return VehicleMatch(kind: .lowConfidence, score: 0.35, label: "低置信替代")
}

/// Returns true when a non-empty query should be treated as a concrete model rather than a generic class.
public func isSpecificVehicleModelQuery(_ query: String) -> Bool {
    let normalizedQuery = normalize(query)
    guard !normalizedQuery.isEmpty else { return false }
    return inferGenericQueryFamily(normalizedQuery) == nil
}

// MARK: - Private Helpers

/// Known model name aliases for exact matching.
private let MODEL_ALIASES: [String: [String]] = [
    "瑞虎8": ["瑞虎8", "奇瑞瑞虎8", "tiggo8", "tiggo 8"],
    "哈弗h6": ["哈弗h6", "h6", "haval h6"]
]

/// Keywords for inferring vehicle class/family.
private let CLASS_KEYWORDS: [String: [String]] = [
    "suv": ["suv", "越野", "运动型"],
    "sedan": ["轿车", "三厢", "两厢", "sedan"],
    "mpv": ["mpv", "商务", "多用途"]
]

private let FAMILY_LABELS: [String: String] = [
    "suv": "SUV",
    "sedan": "轿车",
    "mpv": "MPV"
]

private func sameVehicleFamilyLabel(query: String, vehicleClass: String, vehicleName: String) -> String? {
    guard let queryFamily = inferGenericQueryFamily(query),
          let candidateFamily = inferFamily("\(vehicleClass) \(vehicleName)")
    else { return nil }
    guard queryFamily == candidateFamily else { return nil }
    return FAMILY_LABELS[queryFamily] ?? queryFamily.uppercased()
}

private func inferGenericQueryFamily(_ value: String) -> String? {
    if value.contains("suv") {
        return "suv"
    }
    for (family, keywords) in CLASS_KEYWORDS {
        if keywords.contains(where: { value.contains($0) }) {
            return family
        }
    }
    return nil
}

private func inferFamily(_ value: String) -> String? {
    if value.contains("瑞虎") || value.contains("哈弗") || value.contains("suv") {
        return "suv"
    }
    for (family, keywords) in CLASS_KEYWORDS {
        if keywords.contains(where: { value.contains($0) }) {
            return family
        }
    }
    return nil
}

private func normalize(_ value: String) -> String {
    value
        .lowercased()
        .replacingOccurrences(of: " ", with: "")
        .replacingOccurrences(of: "·", with: "")
        .replacingOccurrences(of: "-", with: "")
}
