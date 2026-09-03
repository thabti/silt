import SwiftUI

/// The chrome every scanning page shares.
///
/// Files, Build artifacts and App leftovers each wrote their own header, idle card,
/// progress card, empty state and notice row. Four independent implementations meant four
/// fidelity levels, and App leftovers had ended up visibly the least finished of them.
/// These components have no style knobs on purpose: the knobs are what let the copies
/// drift apart in the first place.

/// Header card: icon, title, one line of explanation, optional last-scan time, and a
/// trailing slot for whatever that page needs there.
struct PageHeader<Trailing: View>: View {
    let symbol: String
    let title: String
    let blurb: String
    var scannedAt: Date?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            IconTile(symbol: symbol, tint: Theme.accent, size: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.heading(20, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                Text(blurb)
                    .font(Theme.heading(14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let scannedAt {
                    Text("Scanned \(scannedAt.formatted(date: .omitted, time: .shortened))")
                        .font(Theme.heading(12))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 12)
            trailing()
        }
        .card(padding: 22)
    }
}

/// The trailing figure pair: total over a caption that becomes a selection count.
struct PageTotals: View {
    let bytes: Int64
    let noun: String
    let count: Int
    let selected: Int

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(bytes.byteLabel).font(Theme.figure(20))
            Text(selected > 0 ? "\(selected) of \(count) selected" : "\(count) \(count == 1 ? noun : noun + "s")")
                .font(Theme.heading(12))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Centred card used for both the idle prompt and the empty result, so the two states
/// stop looking like they belong to different apps.
struct PagePrompt: View {
    let title: String
    var message: String?
    var actionTitle: String?
    var prominent = true
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Text(title)
                .font(Theme.heading(prominent ? 22 : 20, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            if let message {
                Text(message)
                    .font(Theme.heading(14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }
            if let actionTitle, let action {
                if prominent {
                    Button(actionTitle, action: action)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.extraLarge)
                        .tint(Theme.accent)
                } else {
                    Button(actionTitle, action: action).controlSize(.large)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .card(padding: prominent ? 34 : 30)
    }
}

/// Centred progress card. Supplies its own fallback text and line clamp, which is what
/// stopped two of the three pages from jumping as long paths streamed past.
struct PageProgress: View {
    let counts: String
    let folder: String
    var fallback = "Walking your home folder…"
    var label = "Scanning"
    let onStop: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            ProgressView().accessibilityLabel(label)
            Text(counts)
                .font(Theme.figure(13, weight: .medium))
                .foregroundStyle(.secondary)
            Text(folder.isEmpty ? fallback : folder)
                .font(Theme.heading(12))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .accessibilityHidden(true)
            Button("Stop", action: onStop).controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .card(padding: 30)
    }
}

/// Result banner. Turns into a warning when the run reported failures, because a partial
/// failure presented with a green tick is a lie.
struct PageNotice<Trailing: View>: View {
    let text: String
    var secondary: String?
    var isWarning = false
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isWarning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(isWarning ? Theme.danger : Theme.good)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(text).font(Theme.heading(13))
                if let secondary {
                    Text(secondary).font(Theme.heading(12)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            trailing()
        }
        .card(radius: 14, padding: 12)
        .accessibilityElement(children: .combine)
    }
}
