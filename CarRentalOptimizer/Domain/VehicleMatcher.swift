import Foundation

private let modelAliases: [String: [String]] = [
    "瑞虎8": ["瑞虎8", "奇瑞瑞虎8", "tiggo8", "tiggo 8"],
    "哈弗h6": ["哈弗h6", "h6", "haval h6"]
]

private let classKeywords: [String: [String]] = [
    "suv": ["suv", "越野", "运动型"],
    "sedan": ["轿车", "三厢", "两厢", "sedan"],
    "mpv": ["mpv", "商务", "多用途"]
]

struct VehicleCandidate {
    let vehicleName: String
    let vehicleClass: String
}

func matchVehicle(query: String, candidate: VehicleCandidate) -> VehicleMatch {
    let normalizedQuery = normalize(query)
    let normalizedName = normalize(candidate.vehicleName)
    let normalizedClass = normalize(candidate.vehicleClass)

    if normalizedQuery.isEmpty {
        return VehicleMatch(kind: .notSpecified, score: 0, label: "未指定车型")
    }

    let aliases = modelAliases[normalizedQuery] ?? [normalizedQuery]
    if aliases.contains(where: { normalizedName.contains(normalize($0)) }) {
        return VehicleMatch(kind: .exact, score: 1, label: "精确车型")
    }

    if sameVehicleFamily(query: normalizedQuery, vehicleClass: normalizedClass, vehicleName: normalizedName) {
        return VehicleMatch(kind: .similarClass, score: 0.72, label: "同级 SUV 替代")
    }

    return VehicleMatch(kind: .lowConfidence, score: 0.35, label: "低置信替代")
}

private func sameVehicleFamily(query: String, vehicleClass: String, vehicleName: String) -> Bool {
    let queryFamily = inferFamily(query)
    let candidateFamily = inferFamily("\(vehicleClass) \(vehicleName)")
    return queryFamily != nil && candidateFamily != nil && queryFamily == candidateFamily
}

private func inferFamily(_ value: String) -> String? {
    if value.contains("瑞虎") || value.contains("哈弗") || value.contains("suv") {
        return "suv"
    }
    return classKeywords.first { _, keywords in
        keywords.contains { value.contains($0) }
    }?.key
}

private func normalize(_ value: String) -> String {
    value.lowercased()
        .replacingOccurrences(of: " ", with: "")
        .replacingOccurrences(of: "·", with: "")
        .replacingOccurrences(of: "-", with: "")
}
