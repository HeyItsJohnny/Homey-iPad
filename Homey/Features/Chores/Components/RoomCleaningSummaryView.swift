import SwiftUI

struct RoomCleaningSummaryView: View {
    let summary: RoomCleaningSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(HomeyTheme.primary)
                    .frame(width: 28, height: 28)
                    .background(HomeyTheme.primarySoft, in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.room.name)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(HomeyTheme.textPrimary)
                        .lineLimit(1)

                    Text(summary.room.displayRoomType.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(HomeyTheme.textSecondary)
                }

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 6) {
                summaryRow("Last Cleaned", value: lastCleanedText)
                summaryRow("Preferred Cleaning", value: summary.preferredCleaningText)
            }
        }
        .padding(12)
        .background(HomeyTheme.surfacePrimary.opacity(0.74), in: RoundedRectangle(cornerRadius: HomeyRadius.button, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: HomeyRadius.button, style: .continuous)
                .stroke(HomeyTheme.borderSubtle.opacity(0.78), lineWidth: 1)
        }
    }

    private func summaryRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(HomeyTheme.textSecondary)

            Spacer(minLength: 8)

            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(HomeyTheme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    private var lastCleanedText: String {
        guard let lastCleanedAt = summary.lastCleanedAt else {
            return "Never"
        }

        return lastCleanedAt.formatted(date: .abbreviated, time: .omitted)
    }
}
