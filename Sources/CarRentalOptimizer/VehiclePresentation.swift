import CarRentalDomain
import Foundation

extension VehicleMatch {
    var displayLabel: String? {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard kind != .notSpecified, !trimmed.isEmpty, trimmed != "未指定车型" else {
            return nil
        }
        return trimmed
    }
}

extension RentalListing {
    var displayVehicleClass: String? {
        let trimmed = vehicleClass.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "未指定车型" else {
            return nil
        }
        return trimmed
    }

    var displayNameWithClass: String {
        guard let displayVehicleClass else { return vehicleName }
        return "\(vehicleName) · \(displayVehicleClass)"
    }

    func displayName(with match: VehicleMatch) -> String {
        guard let matchLabel = match.displayLabel else { return vehicleName }
        return "\(vehicleName) · \(matchLabel)"
    }
}
