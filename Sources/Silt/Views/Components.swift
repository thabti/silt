import SwiftUI

/// Round check control. Big enough to hit without aiming.
struct CheckDot: View {
    let isOn: Bool
    var tint: Color = Theme.accent

    var body: some View {
        ZStack {
            Circle()
                .fill(isOn ? AnyShapeStyle(tint) : AnyShapeStyle(Color.primary.opacity(0.05)))
                .frame(width: 20, height: 20)
            Circle()
                .stroke(isOn ? tint : Color.primary.opacity(0.35), lineWidth: 1.2)
                .frame(width: 20, height: 20)
            if isOn {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.readableForeground(on: tint))
            }
        }
        .animation(.snappy(duration: 0.15), value: isOn)
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
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    IconTile(symbol: category.symbol, tint: Theme.tint(for: category), size: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(category.title)
                            .font(Theme.heading(14))
                            .foregroundStyle(.primary)
                        Text("\(bucketCount) \(bucketCount == 1 ? "location" : "locations")")
                            .font(Theme.heading(11, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .opacity(hovering ? 1 : 0.4)
                }

                Text(bytes.byteLabel)
                    .font(Theme.figure(22))
                    .contentTransition(.numericText())
                    .foregroundStyle(.primary)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.track)
                        Capsule()
                            .fill(Theme.tint(for: category))
                            .frame(width: max(4, geo.size.width * share))
                    }
                }
                .frame(height: 6)

                if category != .review {
                    Text(selectedBytes > 0 ? "\(selectedBytes.byteLabel) selected" : "Nothing selected")
                        .font(Theme.heading(11, weight: .regular))
                        .foregroundStyle(selectedBytes > 0 ? Theme.accent : .secondary)
                } else {
                    Text("Manual only")
                        .font(Theme.heading(11, weight: .regular))
                        .foregroundStyle(.secondary)
                }
            }
            .card(padding: 14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(hovering ? Color.primary.opacity(0.03) : .clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(category.title), \(bytes.byteLabel), \(bucketCount) \(bucketCount == 1 ? "location" : "locations")")
        .accessibilityValue(category == .review ? "Manual only" : (selectedBytes > 0 ? "\(selectedBytes.byteLabel) selected" : "Nothing selected"))
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
        HStack(alignment: .top, spacing: 12) {
            if deletable {
                Button(action: onToggle) { CheckDot(isOn: isSelected) }
                    .buttonStyle(.plain)
                    .padding(.top, 6)
                    .accessibilityLabel("Select \(target.name)")
                    .accessibilityValue(isSelected ? "On" : "Off")
            } else {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(width: 20)
                    .padding(.top, 8)
            }

            IconTile(symbol: target.category.symbol, tint: Theme.tint(for: target.category), size: 36)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(target.name)
                        .font(Theme.heading(13))
                    Pill(text: target.kind.label, color: target.kind.pillColor)
                    if bucket.unreadable {
                        Pill(text: "Partly locked", color: Theme.warn)
                    }
                }
                Text(target.consequence)
                    .font(Theme.heading(12, weight: .regular))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Text(target.displayPath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if hovering {
                        Button("Reveal", action: onReveal)
                            .buttonStyle(.link)
                            .font(Theme.heading(11, weight: .regular))
                    }
                }
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 2) {
                Text(bucket.bytes.byteLabel)
                    .font(Theme.figure(14))
                Text("\(bucket.fileCount.formatted()) files")
                    .font(Theme.heading(11, weight: .regular))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hovering ? Color.primary.opacity(0.04) : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { if deletable { onToggle() } }
        .onHover { hovering = $0 }
        .contextMenu { Button("Reveal in Finder", action: onReveal) }
        .accessibilityAction(named: "Reveal in Finder", onReveal)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(target.name), \(target.kind.label), \(bucket.bytes.byteLabel)")
        .accessibilityValue(deletable ? (isSelected ? "Selected" : "Not selected") : "Review only")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Empty and busy states share this look.
struct StatusPanel<Accessory: View>: View {
    let symbol: String
    let title: String
    let message: String
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            VStack(spacing: 6) {
                Text(title)
                    .font(Theme.heading(20, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .font(Theme.heading(13, weight: .regular))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }
            accessory()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}
