import SwiftUI

struct BlueprintSheetActionBar<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            content
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(WorkbenchStyle.elevatedSurface)
        .overlay(alignment: .top) {
            Rectangle().fill(WorkbenchStyle.hairline).frame(height: 1)
        }
    }
}

struct BlueprintWebLocationBar: View {
    let platformName: String
    let currentURL: String
    var message: String
    var tone: WorkbenchRailTone = .active

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(tone.color)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(platformName)官方登录页")
                    .font(.caption.weight(.semibold))
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(WorkbenchStyle.muted)
                Text(currentURL)
                    .font(.caption2)
                    .foregroundStyle(WorkbenchStyle.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(tone.color.opacity(0.07))
        .accessibilityElement(children: .combine)
    }
}
