import SwiftUI

/// Which appearance the app runs in. Stored as a raw string in AppStorage.
enum Appearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light:  "Light"
        case .dark:   "Dark"
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light:  "sun.max"
        case .dark:   "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light:  .light
        case .dark:   .dark
        }
    }
}

/// Silt's visual language: flat, restrained, native.
///
/// The reference is System Settings › Storage, not a landing page. The rules that came out
/// of the de-slop pass: one accent — the teal of the app icon — and system semantic colors
/// for everything else; no gradients; no glow shadows; system typography with monospaced
/// digits wherever numbers need to line up. All colors come from NSColor's system palette
/// so they adapt to light and dark for free.
enum Theme {

    // MARK: - Palette

    static let accent = Color(nsColor: .systemTeal)
    static let danger = Color(nsColor: .systemRed)
    static let good = Color(nsColor: .systemGreen)
    static let warn = Color(nsColor: .systemOrange)

    static var canvas: Color { Color(nsColor: .windowBackgroundColor) }
    static var card: Color { Color(nsColor: .controlBackgroundColor) }
    static var hairline: Color { Color.primary.opacity(0.08) }
    /// The empty part of a capacity bar — System Settings' light gray track.
    static var track: Color { Color.primary.opacity(0.10) }

    static func tint(for category: CleanCategory) -> Color {
        switch category {
        case .developer:    Color(nsColor: .systemBlue)
        case .browsers:     Color(nsColor: .systemTeal)
        case .applications: Color(nsColor: .systemGreen)
        case .system:       Color(nsColor: .systemGray)
        case .review:       Color(nsColor: .systemOrange)
        }
    }

    // MARK: - Type

    /// System font with tabular figures — sizes stay modest, alignment does the talking.
    static func figure(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }

    static func heading(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight)
    }
}

// MARK: - Card

/// Grouped-inset container, the way System Settings draws its lists: flat fill,
/// hairline edge, no shadow.
struct CardBackground: ViewModifier {
    var radius: CGFloat = 10
    var padding: CGFloat = 16

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
    }
}

extension View {
    func card(radius: CGFloat = 10, padding: CGFloat = 16) -> some View {
        modifier(CardBackground(radius: radius, padding: padding))
    }
}

// MARK: - Reusable bits

/// Small flat icon square, System Settings sidebar style: solid color, white symbol.
struct IconTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 34

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
            .fill(tint)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.52, weight: .medium))
                    .foregroundStyle(.white)
            )
    }
}

struct Pill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(Capsule().fill(color.opacity(0.14)))
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
