import SwiftUI

struct ChoreSectionDescriptionHeader: View {
    let title: String
    let description: String
    var trailing: AnyView?

    init(title: String, description: String, trailing: AnyView? = nil) {
        self.title = title
        self.description = description
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(HomeyTheme.textPrimary)

                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(HomeyTheme.textSecondary)
            }

            if let trailing {
                Spacer()
                trailing
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomeyTheme.backgroundPrimary, in: RoundedRectangle(cornerRadius: HomeyRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: HomeyRadius.card, style: .continuous)
                .stroke(HomeyTheme.borderSubtle, lineWidth: 1)
        }
    }
}
