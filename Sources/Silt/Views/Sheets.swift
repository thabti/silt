import SwiftUI

/// Nothing is removed until this sheet is confirmed, and it spells out the exact
/// destination — Trash or gone — plus every bucket in the job.
struct ConfirmSheet: View {
    @ObservedObject var model: AppModel

    private var buckets: [ScannedTarget] { model.pending }
    private var includesTrash: Bool { buckets.contains { $0.target.id == Catalog.trashID } }
    private var isPermanent: Bool { model.mode == .permanent }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(isPermanent ? "Delete \(model.pendingBytes.byteLabel)?" : "Move \(model.pendingBytes.byteLabel) to the Trash?")
                    .font(Theme.heading(18, weight: .bold))
                HStack(spacing: 8) {
                    Pill(text: model.pendingScope, color: Theme.accent)
                    Text("\(buckets.count) \(buckets.count == 1 ? "location" : "locations")")
                        .font(Theme.heading(13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Text(model.mode.explanation)
                    .font(Theme.heading(14))
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(buckets) { bucket in
                        HStack(spacing: 12) {
                            IconTile(symbol: bucket.target.category.symbol,
                                     tint: Theme.tint(for: bucket.target.category),
                                     size: 30)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(bucket.target.name)
                                    .font(Theme.heading(14, weight: .semibold))
                                Text(bucket.target.displayPath)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Text(bucket.bytes.byteLabel)
                                .font(Theme.figure(15, weight: .semibold))
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                    }
                }
            }
            .frame(maxHeight: 240)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )

            if includesTrash || isPermanent {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.danger)
                    Text(includesTrash
                         ? "Emptying the Trash cannot be undone, whichever option you pick."
                         : "Deleting now cannot be undone.")
                        .font(Theme.heading(13, weight: .medium))
                    Spacer()
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.danger.opacity(0.10)))
            }

            HStack(spacing: 12) {
                Text("Folders stay in place — only their contents are cleared.")
                    .font(Theme.heading(12))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Cancel") { model.showConfirmation = false }
                    .controlSize(.large)
                    .keyboardShortcut(.cancelAction)
                Button(isPermanent ? "Delete" : "Move to Trash") { model.confirmClean() }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .tint(isPermanent ? Theme.danger : Theme.accent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(width: 560)
    }
}

struct ReportSheet: View {
    @ObservedObject var model: AppModel
    let report: CleanReport

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.good)

            VStack(spacing: 6) {
                Text(report.bytesFreed.byteLabel)
                    .font(Theme.figure(34, weight: .bold))
                Text(model.mode == .trash && !report.outcomes.isEmpty
                     ? "moved to the Trash"
                     : "freed")
                    .font(Theme.heading(16, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("\(report.itemsRemoved.formatted()) items across \(report.outcomes.count) locations")
                    .font(Theme.heading(13))
                    .foregroundStyle(.tertiary)
            }

            if !report.outcomes.isEmpty {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(report.outcomes.sorted { $0.bytesFreed > $1.bytesFreed }) { outcome in
                            HStack {
                                Text(outcome.name)
                                    .font(Theme.heading(13, weight: .medium))
                                Spacer()
                                if !outcome.failures.isEmpty {
                                    Pill(text: "\(outcome.failures.count) skipped", color: Theme.warn)
                                }
                                Text(outcome.bytesFreed.byteLabel)
                                    .font(Theme.figure(13, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 10)
                        }
                    }
                }
                .frame(maxHeight: 190)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.04)))
            }

            if report.failureCount > 0 || !report.blocked.isEmpty {
                Text("\(report.failureCount + report.blocked.count) items were left alone — usually because macOS protects them or an app has them open.")
                    .font(Theme.heading(12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Done") { model.dismissReport() }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(28)
        .frame(width: 480)
    }
}
