import SwiftUI

/// Sky & Sand: the iPad app's shared visual language. Keep data/category colors independent.
enum HomeyTheme {
    static let backgroundPrimary = color(0xF7FBFF)
    static let backgroundSecondary = color(0xF2F7FB)
    static let surfacePrimary = color(0xFFFFFF)
    static let surfaceSecondary = color(0xF2F7FB)
    static let surfaceElevated = surfacePrimary
    static let sidebarBackground = color(0xEAF5FC)

    // Slightly deeper than the decorative sky tint for readable white button labels.
    static let primary = color(0x2478BC)
    static let primaryPressed = color(0x1D619A)
    static let primarySoft = color(0xDDEFFC)
    static let textPrimary = color(0x17324D)
    static let textSecondary = color(0x536D82)
    static let textMuted = color(0x62798C)
    static let textOnPrimary = Color.white
    static let borderSubtle = color(0xDCE8F0)
    static let divider = borderSubtle
    static let shadow = color(0x17324D).opacity(0.06)

    static let success = color(0x32774A)
    static let successSoft = color(0xEAF7ED)
    static let warning = color(0x95630C)
    static let warningSoft = color(0xFFF6DC)
    static let danger = color(0xB54442)
    static let dangerSoft = color(0xFFF0EE)
    static let info = primary
    static let infoSoft = primarySoft
    static let peach = color(0xA55E2B)
    static let peachSoft = color(0xFFF0E5)
    static let lavender = color(0x7060AC)
    static let lavenderSoft = color(0xF1EEFF)
    static let coral = color(0xB45149)
    static let sand = color(0xFFF7E8)

    static let mealBreakfast = peach
    static let mealLunch = success
    static let mealDinner = lavender
    static let mealSnack = warning
    static let tripSaved = peach
    static let tripPlanned = success
    static let tripPast = lavender
    static let choreTask = primary
    static let choreChore = lavender
    static let choreCompleted = success
    static let choreRemaining = textSecondary

    private static func color(_ hex: UInt32) -> Color {
        Color(.sRGB, red: Double((hex >> 16) & 0xff) / 255,
              green: Double((hex >> 8) & 0xff) / 255,
              blue: Double(hex & 0xff) / 255, opacity: 1)
    }
}

enum HomeyRadius {
    static let control: CGFloat = 12
    static let button: CGFloat = 14
    static let card: CGFloat = 20
    static let page: CGFloat = 26
}

/// Shared primary action, including native destructive roles and disabled/pressed feedback.
struct HomeyPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let fill = configuration.role == .destructive ? HomeyTheme.danger :
            (configuration.isPressed ? HomeyTheme.primaryPressed : HomeyTheme.primary)
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(HomeyTheme.textOnPrimary)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(fill, in: RoundedRectangle(cornerRadius: HomeyRadius.button, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.9 : 1) : 0.5)
    }
}

struct HomeySecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(configuration.role == .destructive ? HomeyTheme.danger : HomeyTheme.primary)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(configuration.isPressed ? HomeyTheme.primarySoft : HomeyTheme.surfacePrimary,
                        in: RoundedRectangle(cornerRadius: HomeyRadius.button, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: HomeyRadius.button, style: .continuous)
                    .stroke(HomeyTheme.borderSubtle, lineWidth: 1)
            }
            .opacity(isEnabled ? 1 : 0.5)
    }
}
