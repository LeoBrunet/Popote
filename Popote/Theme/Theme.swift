import SwiftUI

// "Tomate · bistrot" from the UIStudio mockups: tomato red, cream paper, serif titles.

enum Theme {
    static let accent = Color(red: 0.88, green: 0.33, blue: 0.22)
    static let accentSoft = accent.opacity(0.13)
    static let onAccent = Color.white
    static let background = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.09, green: 0.08, blue: 0.07, alpha: 1)
        : UIColor(red: 0.985, green: 0.965, blue: 0.94, alpha: 1) })
    static let card = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.15, green: 0.14, blue: 0.13, alpha: 1)
        : .white })
    static let herb = Color(red: 0.24, green: 0.56, blue: 0.36)
    static let health = Color(red: 1.0, green: 0.18, blue: 0.33)

    static let protein = Color(red: 0.86, green: 0.29, blue: 0.40)
    static let carbs = Color(red: 0.96, green: 0.64, blue: 0.18)
    static let fat = Color(red: 0.38, green: 0.46, blue: 0.86)

    static let radius: CGFloat = 22
    static let titleFont = Font.system(.title2, design: .serif, weight: .bold)
    static let displayFont = Font.system(.largeTitle, design: .serif, weight: .bold)
}

enum DS {
    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let s: CGFloat = 12
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
    }
}

extension View {
    /// Rounded card on the cream background.
    func card(padding: CGFloat = DS.Spacing.m) -> some View {
        self.padding(padding)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }
}

extension View {
    /// Cream band behind the status bar so scrolled content doesn't run under the clock.
    func statusBarBackdrop() -> some View {
        safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: 0).background(Theme.background) }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var secondary = false

    func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonBody(configuration: configuration, secondary: secondary)
    }
}

private struct PrimaryButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let secondary: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(secondary ? Color.primary : Theme.onAccent)
            .background(secondary ? Theme.card : Theme.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                if secondary {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.primary.opacity(0.12))
                }
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
    }
}
