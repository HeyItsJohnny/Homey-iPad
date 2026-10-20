import SwiftUI

struct ChoreSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(HomeyTheme.textSecondary)
                        .accessibilityHidden(true)

                    TextField("Search chores", text: $searchText)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                }
                .font(.body.weight(.medium))
                .foregroundStyle(HomeyTheme.textPrimary)
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
                .background(HomeyTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: HomeyRadius.card, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: HomeyRadius.card, style: .continuous)
                        .stroke(HomeyTheme.borderSubtle, lineWidth: 1)
                }

                Text("Chore search results will appear here once chore list UI is built.")
                    .font(.subheadline)
                    .foregroundStyle(HomeyTheme.textSecondary)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(HomeyTheme.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Search Chores")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
