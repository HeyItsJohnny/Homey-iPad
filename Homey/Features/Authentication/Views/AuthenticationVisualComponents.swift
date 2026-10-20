import SwiftUI

struct AuthenticationBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let bloomSize = max(width, height) * 0.68
            let sideGlowSize = max(width, height) * 0.58

            ZStack {
                LinearGradient(
                    stops: [
                        .init(color: HomeyTheme.sidebarBackground, location: 0.0),
                        .init(color: HomeyTheme.primarySoft, location: 0.34),
                        .init(color: HomeyTheme.backgroundSecondary, location: 0.58),
                        .init(color: HomeyTheme.surfaceSecondary, location: 0.82),
                        .init(color: HomeyTheme.surfacePrimary, location: 1.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(reduceTransparency ? 0.24 : 0.58),
                                HomeyTheme.sand.opacity(reduceTransparency ? 0.10 : 0.22),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: bloomSize * 0.50
                        )
                    )
                    .frame(width: bloomSize, height: bloomSize)
                    .blur(radius: reduceTransparency ? 24 : 54)
                    .position(x: width * 0.35, y: height * 0.24)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                HomeyTheme.primarySoft.opacity(reduceTransparency ? 0.06 : 0.14),
                                Color.white.opacity(reduceTransparency ? 0.06 : 0.16),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: sideGlowSize * 0.52
                        )
                    )
                    .frame(width: sideGlowSize, height: sideGlowSize)
                    .blur(radius: reduceTransparency ? 22 : 48)
                    .position(x: width * 0.76, y: height * 0.42)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                HomeyTheme.primarySoft.opacity(reduceTransparency ? 0.06 : 0.18),
                                HomeyTheme.sand.opacity(reduceTransparency ? 0.04 : 0.12),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: sideGlowSize * 0.48
                        )
                    )
                    .frame(width: sideGlowSize, height: sideGlowSize)
                    .blur(radius: reduceTransparency ? 24 : 52)
                    .position(x: width * 0.18, y: height * 0.88)
            }
        }
        .ignoresSafeArea()
    }
}

struct AuthenticationHeroView: View {
    let isCompact: Bool

    private var headline: AttributedString {
        var text = AttributedString("Home is better together.")

        if let range = text.range(of: "better together.") {
            text[range].foregroundColor = HomeyTheme.primary
        }

        return text
    }

    var body: some View {
        VStack(alignment: isCompact ? .center : .leading, spacing: isCompact ? 12 : 22) {
            Image("homey_login_hero")
                .resizable()
                .scaledToFit()
                .frame(maxHeight: isCompact ? 150 : 390)
                .frame(maxWidth: .infinity, alignment: isCompact ? .center : .leading)
                .accessibilityHidden(true)

            if !isCompact {
                VStack(alignment: .leading, spacing: 12) {
                    Text(headline)
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .foregroundStyle(HomeyTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Homey helps your family stay organized,\nconnected, and at home.")
                        .font(.title3)
                        .foregroundStyle(HomeyTheme.textSecondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 500, alignment: .leading)
                .padding(.leading, 18)
            }
        }
        .padding(.vertical, isCompact ? 4 : 0)
        .padding(.horizontal, isCompact ? 10 : 0)
    }
}

struct AuthenticationFormCard<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var isCompact = false
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(isCompact ? 24 : 36)
            .background(
                RoundedRectangle(cornerRadius: isCompact ? 26 : 30, style: .continuous)
                    .fill(Color.white.opacity(reduceTransparency ? 1 : 0.92))
            )
            .overlay {
                RoundedRectangle(cornerRadius: isCompact ? 26 : 30, style: .continuous)
                    .stroke(Color.white.opacity(0.85), lineWidth: 1)
            }
            .shadow(color: HomeyTheme.shadow, radius: 30, x: 0, y: 16)
    }
}

struct AuthenticationFormHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "house.fill")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(HomeyTheme.primary, in: RoundedRectangle(cornerRadius: HomeyRadius.button, style: .continuous))
                .accessibilityHidden(true)

            Text(title)
                .font(.largeTitle.bold())
                .foregroundStyle(HomeyTheme.textPrimary)
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(HomeyTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

struct AuthenticationTextField<Field: Hashable>: View {
    let title: String
    let systemImage: String
    @Binding var text: String
    var focusedField: FocusState<Field?>.Binding
    let field: Field
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType?
    var textInputAutocapitalization: TextInputAutocapitalization? = .never
    var isAutocorrectionDisabled = true
    var submitLabel: SubmitLabel = .next

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(HomeyTheme.textSecondary)
                .frame(width: 22)
                .accessibilityHidden(true)

            TextField(title, text: $text)
                .textInputAutocapitalization(textInputAutocapitalization)
                .autocorrectionDisabled(isAutocorrectionDisabled)
                .keyboardType(keyboardType)
                .textContentType(textContentType)
                .focused(focusedField, equals: field)
                .submitLabel(submitLabel)
        }
        .authenticationFieldBackground(isFocused: focusedField.wrappedValue == field)
    }
}

struct AuthenticationPickerField<Selection: Hashable>: View {
    let title: String
    let systemImage: String
    @Binding var selection: Selection
    let options: [Selection]
    let label: (Selection) -> String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(HomeyTheme.textSecondary)
                .frame(width: 22)
                .accessibilityHidden(true)

            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(label(option))
                        .tag(option)
                }
            }
            .pickerStyle(.menu)
            .tint(HomeyTheme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .authenticationFieldBackground(isFocused: false)
    }
}

struct AuthenticationSecureField<Field: Hashable>: View {
    let title: String
    @Binding var text: String
    @Binding var isPasswordVisible: Bool
    var focusedField: FocusState<Field?>.Binding
    let field: Field
    var textContentType: UITextContentType = .password
    var submitLabel: SubmitLabel = .go

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock")
                .foregroundStyle(HomeyTheme.textSecondary)
                .frame(width: 22)
                .accessibilityHidden(true)

            Group {
                if isPasswordVisible {
                    TextField(title, text: $text)
                        .textContentType(textContentType)
                } else {
                    SecureField(title, text: $text)
                        .textContentType(textContentType)
                }
            }
            .focused(focusedField, equals: field)
            .submitLabel(submitLabel)

            Button {
                isPasswordVisible.toggle()
            } label: {
                Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                    .foregroundStyle(HomeyTheme.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPasswordVisible ? "Hide \(title.lowercased())" : "Show \(title.lowercased())")
        }
        .authenticationFieldBackground(isFocused: focusedField.wrappedValue == field)
    }
}

struct AuthenticationErrorView: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(HomeyTheme.danger)
                .accessibilityHidden(true)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(HomeyTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(HomeyTheme.dangerSoft, in: RoundedRectangle(cornerRadius: HomeyRadius.button, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(message)")
    }
}

struct AuthenticationSuccessView: View {
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(HomeyTheme.success)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HomeyTheme.textPrimary)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(HomeyTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(HomeyTheme.success.opacity(0.12), in: RoundedRectangle(cornerRadius: HomeyRadius.button, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Success: \(title) \(message)")
    }
}

struct AuthenticationDividerWithText: View {
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(HomeyTheme.borderSubtle)
                .frame(height: 1)

            Text(text)
                .font(.footnote)
                .foregroundStyle(HomeyTheme.textSecondary)

            Rectangle()
                .fill(HomeyTheme.borderSubtle)
                .frame(height: 1)
        }
    }
}



struct AuthenticationSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(HomeyTheme.primary)
            .opacity(configuration.isPressed ? 0.70 : 1)
    }
}

extension View {
    func authenticationFieldBackground(isFocused: Bool) -> some View {
        modifier(AuthenticationFieldBackground(isFocused: isFocused))
    }
}

private struct AuthenticationFieldBackground: ViewModifier {
    let isFocused: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .background(HomeyTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: HomeyRadius.button, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: HomeyRadius.button, style: .continuous)
                    .stroke(isFocused ? HomeyTheme.primary : HomeyTheme.borderSubtle, lineWidth: isFocused ? 1.5 : 1)
            }
    }
}
