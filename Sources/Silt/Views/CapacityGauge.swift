import SwiftUI

/// The disk at a glance, parked at the foot of the sidebar.
///
/// Three arcs that sum to the whole volume: what is in use and staying, what Silt could
/// reclaim, and what is already free. It reads from the live disk snapshot and the current
/// scan totals, so emptying a cache or uninstalling an app animates the ring immediately —
/// the point of the app, made visible without opening a page.
struct CapacityGauge: View {
    let total: Int64
    let free: Int64
    let reclaimable: Int64

    private var usedFraction: Double {
        guard total > 0 else { return 0 }
        return Double(total - free) / Double(total)
    }

    /// Reclaimable is a slice *of* used space, never more than what is actually in use.
    private var reclaimableFraction: Double {
        guard total > 0 else { return 0 }
        return min(Double(reclaimable) / Double(total), usedFraction)
    }

    private var otherFraction: Double { max(0, usedFraction - reclaimableFraction) }

    var body: some View {
        VStack(spacing: 10) {
            ring
            legend
        }
        .animation(.smooth(duration: 0.55), value: reclaimableFraction)
        .animation(.smooth(duration: 0.55), value: usedFraction)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Disk capacity")
        .accessibilityValue("\(free.byteLabel) free of \(total.byteLabel), \(reclaimable.byteLabel) reclaimable")
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Theme.track, lineWidth: 11)

            Circle()
                .trim(from: 0, to: otherFraction)
                .stroke(Color(nsColor: .systemGray), style: StrokeStyle(lineWidth: 11, lineCap: .butt))
                .rotationEffect(.degrees(-90))

            Circle()
                .trim(from: otherFraction, to: otherFraction + reclaimableFraction)
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 11, lineCap: .butt))
                .rotationEffect(.degrees(-90))

            VStack(spacing: 1) {
                Text(free.byteLabel)
                    .font(Theme.figure(15, weight: .bold))
                    .contentTransition(.numericText())
                Text("free")
                    .font(Theme.heading(10, weight: .regular))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 92, height: 92)
        .padding(.top, 2)
    }

    private var legend: some View {
        VStack(spacing: 4) {
            row(color: Color(nsColor: .systemGray), title: "Used", value: max(0, total - free - reclaimable))
            row(color: Theme.accent, title: "Reclaimable", value: reclaimable)
            row(color: Theme.track, title: "Free", value: free)
        }
    }

    private func row(color: Color, title: String, value: Int64) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title)
                .font(Theme.heading(11, weight: .regular))
                .foregroundStyle(.secondary)
            Spacer(minLength: 6)
            Text(value.byteLabel)
                .font(Theme.figure(11, weight: .medium))
                .contentTransition(.numericText())
        }
    }
}
