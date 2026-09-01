import SwiftUI

/// The storage header, drawn the way System Settings draws it: volume name, a flat
/// segmented capacity bar, and a legend with the numbers. The teal segment is what
/// Silt can clear.
struct DiskHeroView: View {
    @ObservedObject var model: AppModel
    var animate: Bool

    private var usedFraction: Double { model.disk.usedFraction }
    private var junkFraction: Double { min(model.junkFraction, usedFraction) }
    private var otherUsedFraction: Double { max(0, usedFraction - junkFraction) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.disk.volumeName)
                    .font(Theme.heading(15))
                Spacer()
                Text("\(model.disk.used.byteLabel) of \(model.disk.total.byteLabel) used")
                    .font(Theme.figure(13, weight: .regular))
                    .foregroundStyle(.secondary)
            }

            bar

            HStack(spacing: 18) {
                legend(color: Color(nsColor: .systemGray), title: "In use",
                       value: (model.disk.used - model.junkBytes).byteLabel)
                legend(color: Theme.accent, title: "Reclaimable", value: model.junkBytes.byteLabel)
                legend(color: Theme.track, title: "Free", value: model.disk.free.byteLabel)
                Spacer()
                if model.junkBytes > 0 {
                    Text("\(model.junkBytes.byteLabel) can be cleared")
                        .font(Theme.figure(13))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .card()
    }

    private var bar: some View {
        GeometryReader { geo in
            let width = geo.size.width
            HStack(spacing: 2) {
                Rectangle()
                    .fill(Color(nsColor: .systemGray))
                    .frame(width: max(0, width * otherUsedFraction))
                Rectangle()
                    .fill(Theme.accent)
                    .frame(width: max(0, width * junkFraction))
                Rectangle()
                    .fill(Theme.track)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .frame(height: 12)
        .animation(.smooth(duration: 0.5), value: junkFraction)
    }

    private func legend(color: Color, title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title)
                .font(Theme.heading(12, weight: .regular))
                .foregroundStyle(.secondary)
            Text(value)
                .font(Theme.figure(12))
        }
    }
}
