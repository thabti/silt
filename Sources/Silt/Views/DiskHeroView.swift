import SwiftUI

/// The headline: one ring, one very large number, and a segmented bar that reads
/// the way the macOS storage bar does.
struct DiskHeroView: View {
    @ObservedObject var model: AppModel
    var animate: Bool

    private var usedFraction: Double { model.disk.usedFraction }
    private var junkFraction: Double { min(model.junkFraction, usedFraction) }
    private var otherUsedFraction: Double { max(0, usedFraction - junkFraction) }

    var body: some View {
        HStack(alignment: .center, spacing: 34) {
            ring
            stats
        }
        .card(padding: 28)
    }

    // MARK: Ring

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.07), lineWidth: 26)

            // Everything already in use, minus the part we can reclaim.
            Circle()
                .trim(from: 0, to: otherUsedFraction)
                .stroke(
                    LinearGradient(colors: [Color.secondary.opacity(0.55), Color.secondary.opacity(0.30)],
                                   startPoint: .top, endPoint: .bottom),
                    style: StrokeStyle(lineWidth: 26, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            // The reclaimable slice, drawn on top in the accent colour.
            Circle()
                .trim(from: otherUsedFraction, to: usedFraction)
                .stroke(Theme.accentGradient, style: StrokeStyle(lineWidth: 26, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: Theme.accent.opacity(0.45), radius: 10)

            VStack(spacing: 2) {
                Text(model.junkBytes.byteLabel)
                    .font(Theme.figure(42))
                    .contentTransition(.numericText())
                    .foregroundStyle(Theme.accentGradient)
                Text("reclaimable")
                    .font(Theme.heading(13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 208, height: 208)
        .animation(.smooth(duration: 0.7), value: usedFraction)
        .animation(.smooth(duration: 0.7), value: junkFraction)
    }

    // MARK: Stats

    private var stats: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.disk.volumeName)
                    .font(Theme.heading(15, weight: .medium))
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(model.disk.free.byteLabel)
                        .font(Theme.figure(46))
                        .contentTransition(.numericText())
                    Text("free")
                        .font(Theme.heading(19, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Text("of \(model.disk.total.byteLabel)")
                    .font(Theme.heading(14))
                    .foregroundStyle(.tertiary)
            }

            storageBar

            HStack(spacing: 20) {
                legend(color: Color.secondary.opacity(0.5), title: "In use", value: (model.disk.used - model.junkBytes).byteLabel)
                legend(color: Theme.accent, title: "Reclaimable", value: model.junkBytes.byteLabel)
                legend(color: Color.primary.opacity(0.10), title: "Free", value: model.disk.free.byteLabel)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var storageBar: some View {
        GeometryReader { geo in
            let width = geo.size.width
            HStack(spacing: 2) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.45))
                    .frame(width: max(0, width * otherUsedFraction))
                Rectangle()
                    .fill(Theme.accentGradient)
                    .frame(width: max(0, width * junkFraction))
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
            }
            .clipShape(Capsule())
        }
        .frame(height: 16)
        .animation(.smooth(duration: 0.7), value: junkFraction)
    }

    private func legend(color: Color, title: String, value: String) -> some View {
        HStack(spacing: 7) {
            Circle().fill(color).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Theme.heading(12, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(Theme.figure(15, weight: .semibold))
            }
        }
    }
}
