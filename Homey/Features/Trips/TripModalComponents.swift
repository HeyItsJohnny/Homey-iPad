import SwiftUI

/// Uses the same sheet dimensions, typography and card surface as Calendar's event editor.
struct TripModalLayout<Content: View>: View {
    let title: String
    let subtitle: String
    var onDone: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        NavigationStack {
            ZStack {
                HomeyTheme.backgroundPrimary.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if let onDone {
                            HStack {
                                if let onEdit {
                                    Button("Edit Idea", action: onEdit)
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(HomeyTheme.primary)
                                        .padding(.horizontal, 18)
                                        .frame(minHeight: 44)
                                        .background(HomeyTheme.surfacePrimary, in: Capsule())
                                }
                                Spacer()
                                Button("Done", action: onDone)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(HomeyTheme.primary)
                                    .padding(.horizontal, 18)
                                    .frame(minHeight: 44)
                                    .background(HomeyTheme.surfacePrimary, in: Capsule())
                            }
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text(title)
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundStyle(HomeyTheme.textPrimary)
                                .accessibilityAddTraits(.isHeader)
                            Text(subtitle).font(.title3).foregroundStyle(HomeyTheme.textSecondary)
                        }
                        VStack(alignment: .leading, spacing: 22, content: content)
                            .font(.body.weight(.medium))
                            .foregroundStyle(HomeyTheme.textPrimary)
                            .tint(HomeyTheme.primary)
                            .padding(28)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .dashboardCard(cornerRadius: HomeyRadius.page)
                    }
                    .padding(.horizontal, 28).padding(.top, 28).padding(.bottom, 34)
                    .frame(maxWidth: 720).frame(maxWidth: .infinity, alignment: .center)
                }.scrollIndicators(.hidden)
            }
        }
        .presentationDetents([.large])
    }
}

struct TripModalField: View {
    let title: String
    var supportingText = "Optional"
    @Binding var text: String
    var axis: Axis = .horizontal
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            TripModalSectionLabel(title: title, supportingText: supportingText)
            TextField(title, text: $text, axis: axis)
                .textInputAutocapitalization(.sentences)
                .font(.body.weight(.medium))
                .padding(.horizontal, 16).padding(.vertical, axis == .vertical ? 14 : 10)
                .frame(minHeight: axis == .vertical ? 104 : 56, alignment: axis == .vertical ? .topLeading : .center)
                .tripInsetPanel(padding: 0)
                .accessibilityLabel(title)
        }
    }
}

struct TripModalSectionLabel: View {
    let title: String
    var supportingText: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.bold())
            if let supportingText { Text(supportingText).font(.caption).foregroundStyle(HomeyTheme.textSecondary) }
        }
    }
}

struct TripModalInfo: View {
    let title: String
    let value: String
    let icon: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(HomeyTheme.primary).frame(width: 22)
            VStack(alignment: .leading, spacing: 5) {
                TripModalSectionLabel(title: title)
                Text(value).foregroundStyle(HomeyTheme.textSecondary).textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }.tripInsetPanel()
    }
}

struct TripModalBanner: View {
    let message: String
    var isError = false
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "info.circle.fill")
            Text(message).frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(isError ? HomeyTheme.danger : HomeyTheme.primary)
        .padding(14)
        .background((isError ? HomeyTheme.danger : HomeyTheme.primary).opacity(0.08), in: RoundedRectangle(cornerRadius: HomeyRadius.button))
        .accessibilityElement(children: .combine)
    }
}



extension View {
    func tripInsetPanel(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .background(HomeyTheme.backgroundPrimary.opacity(0.62), in: RoundedRectangle(cornerRadius: HomeyRadius.button))
            .overlay { RoundedRectangle(cornerRadius: HomeyRadius.button).stroke(HomeyTheme.borderSubtle, lineWidth: 1) }
    }
}
