import SwiftUI

/// Round check control. Big enough to hit without aiming.
struct CheckDot: View {
    let isOn: Bool
    var tint: Color = Theme.accent

    var body: some View {
        ZStack {
            Circle()
                .fill(isOn ? AnyShapeStyle(tint) : AnyShapeStyle(Color.primary.opacity(0.06)))
                .frame(width: 24, height: 24)
            Circle()
                .stroke(isOn ? tint : Color.primary.opacity(0.18), lineWidth: 1.5)
                .frame(width: 24, height: 24)
            if isOn {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(.white)
            }
        }
        .animation(.snappy(duration: 0.18), value: isOn)
    }
}

/// One category tile on the overview.
struct CategoryCard: View {
    let category: CleanCategory
    let bytes: Int64
    let selectedBytes: Int64
    let bucketCount: Int
    let share: Double          // 0...1 against the biggest category
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    IconTile(symbol: category.symbol, gradient: Theme.gradient(for: category), size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.title)
                            .font(Theme.heading(19, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("\(bucketCount) \(bucketCount == 1 ? "location" : "locations")")
                            .font(Theme.heading(12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .opacity(hovering ? 1 : 0.35)
                }

                Text(bytes.byteLabel)
                    .font(Theme.figure(30))
                    .contentTransition(.numericText())
                    .foregroundStyle(.primary)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.07))
                        Capsule()
                            .fill(Theme.gradient(for: category))
                            .frame(width: max(6, geo.size.width * share))
                    }
                }
                .frame(height: 8)

                if category != .review {
                    Text(selectedBytes > 0 ? "\(selectedBytes.byteLabel) selected" : "Nothing selected")
                        .font(Theme.heading(12, weight: .medium))
                        .foregroundStyle(selectedBytes > 0 ? Theme.accent : .secondary)
                } else {
                    Text("Manual only")
                        .font(Theme.heading(12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .card(radius: 20, padding: 18)
            .scaleEffect(hovering ? 1.012 : 1)
            .animation(.snappy(duration: 0.18), value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// One location, with the plain-language consequence of clearing it.
struct BucketRow: View {
    let bucket: ScannedTarget
    let isSelected: Bool
    let onToggle: () -> Void
    let onReveal: () -> Void

    @State private var hovering = false

    private var target: CleanTarget { bucket.target }
    private var deletable: Bool { target.kind.isDeletable }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            if deletable {
                Button(action: onToggle) { CheckDot(isOn: isSelected) }
                    .buttonStyle(.plain)
                    .padding(.top, 10)
            } else {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 24)
                    .padding(.top, 12)
            }

            IconTile(symbol: target.category.symbol, gradient: Theme.gradient(for: target.category), size: 40)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(target.name)
                        .font(Theme.heading(17, weight: .semibold))
                    Pill(text: target.kind.label, color: target.kind.pillColor)
                    if bucket.unreadable {
                        Pill(text: "Partly locked", color: Theme.warn)
                    }
                }
                Text(target.consequence)
                    .font(Theme.heading(13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Text(target.displayPath)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if hovering {
                        Button("Reveal", action: onReveal)
                            .buttonStyle(.link)
                            .font(Theme.heading(11.5, weight: .medium))
                    }
                }
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 3) {
                Text(bucket.bytes.byteLabel)
                    .font(Theme.figure(22))
                Text("\(bucket.fileCount.formatted()) files")
                    .font(Theme.heading(11.5))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(hovering ? Color.primary.opacity(0.04) : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { if deletable { onToggle() } }
        .onHover { hovering = $0 }
    }
}

/// Empty and busy states share this look.
struct StatusPanel<Accessory: View>: View {
    let symbol: String
    let title: String
    let message: String
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        VStack(spacing: 18) {
            IconTile(symbol: symbol, gradient: Theme.accentGradient, size: 76)
            VStack(spacing: 8) {
                Text(title)
                    .font(Theme.heading(30, weight: .bold))
                Text(message)
                    .font(Theme.heading(15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }
            accessory()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}
