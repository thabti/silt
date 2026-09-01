import SwiftUI

enum Theme {

    // MARK: - Palette

    static let accent = Color(red: 0.40, green: 0.42, blue: 0.98)
    static let accentSoft = Color(red: 0.58, green: 0.55, blue: 1.00)
    static let danger = Color(red: 0.98, green: 0.35, blue: 0.42)
    static let good = Color(red: 0.16, green: 0.78, blue: 0.58)
    static let warn = Color(red: 1.00, green: 0.68, blue: 0.22)

    static var canvas: Color { Color(nsColor: .windowBackgroundColor) }
    static var card: Color { Color(nsColor: .controlBackgroundColor) }
    static var hairline: Color { Color.primary.opacity(0.07) }

    static let accentGradient = LinearGradient(
        colors: [accentSoft, accent],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func tint(for category: CleanCategory) -> Color {
        switch category {
        case .developer:    Color(red: 0.45, green: 0.44, blue: 1.00)
        case .browsers:     Color(red: 0.19, green: 0.64, blue: 0.98)
        case .applications: Color(red: 0.98, green: 0.44, blue: 0.62)
        case .system:       Color(red: 0.13, green: 0.76, blue: 0.62)
        case .review:       Color(red: 0.62, green: 0.64, blue: 0.70)
        }
    }

    static func gradient(for category: CleanCategory) -> LinearGradient {
        let base = tint(for: category)
        return LinearGradient(
            colors: [base.opacity(0.95), base.opacity(0.62)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Type

    /// Big, friendly, tabular figures — the numbers are the point of this app.
    static func figure(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }

    static func heading(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

// MARK: - Card

struct CardBackground: ViewModifier {
    var radius: CGFloat = 22
    var padding: CGFloat = 22

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.10), radius: 18, x: 0, y: 8)
    }
}

extension View {
    func card(radius: CGFloat = 22, padding: CGFloat = 22) -> some View {
        modifier(CardBackground(radius: radius, padding: padding))
    }
}

// MARK: - Reusable bits

/// A rounded, gradient-filled icon tile — the visual anchor of every row.
struct IconTile: View {
    let symbol: String
    let gradient: LinearGradient
    var size: CGFloat = 42

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
            .fill(gradient)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .shadow(color: .black.opacity(0.16), radius: 6, x: 0, y: 3)
    }
}

struct Pill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.16)))
            .foregroundStyle(color)
    }
}

extension CleanKind {
    var pillColor: Color {
        switch self {
        case .safe:     Theme.good
        case .prunable: Theme.warn
        case .review:   Color.secondary
        }
    }
}
