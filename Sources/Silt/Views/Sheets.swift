import SwiftUI

/// Nothing is removed until this sheet is confirmed, and it spells out the exact
/// destination — Trash or gone — plus every bucket in the job.
struct ConfirmSheet: View {
    @ObservedObject var model: AppModel

    private var buckets: [ScannedTarget] { model.pending }
    private var includesTrash: Bool { buckets.contains { $0.target.id == Catalog.trashID } }
    /// The Trash bucket is always erased permanently, but a mixed job only reads as
    /// "Delete" when everything in it actually is permanent.
    private var trashOnly: Bool { !buckets.isEmpty && buckets.allSatisfy { $0.target.id == Catalog.trashID } }
    private var isPermanent: Bool { trashOnly || model.mode == .permanent }

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
                Text(trashOnly ? "Not recoverable. Emptying the Trash frees the space immediately." : model.mode.explanation)
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
                    Text(trashOnly
                         ? "Emptying the Trash cannot be undone."
                         : includesTrash
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
                DisclosureGroup("\(report.failureCount + report.blocked.count) items left alone") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(failureReasons, id: \.self) { reason in
                                Text(reason)
                                    .font(Theme.heading(12, weight: .regular))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .frame(maxHeight: 140)
                    .padding(.top, 8)
                }
                .font(Theme.heading(12, weight: .medium))
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
            }

            Button("Done") { model.dismissReport() }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(28)
        .frame(width: 480)
    }

    private var failureReasons: [String] {
        report.outcomes.flatMap { outcome in
            outcome.failures.map { "\(outcome.name): \($0)" }
        } + report.blocked
    }
}


/// Confirmation for a hand-picked file job. Same contract as ConfirmSheet: what is listed
/// is exactly what runs, in the mode shown.
struct FilesConfirmSheet: View {
    @ObservedObject var model: AppModel

    private var isPermanent: Bool { model.mode == .permanent }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(isPermanent
                     ? "Delete \(model.pendingFileBytes.byteLabel)?"
                     : "Move \(model.pendingFileBytes.byteLabel) to the Trash?")
                    .font(Theme.heading(18, weight: .bold))
                HStack(spacing: 8) {
                    Pill(text: "Large files", color: Theme.accent)
                    Text("\(model.pendingFiles.count) \(model.pendingFiles.count == 1 ? "item" : "items")")
                        .font(Theme.heading(13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Text(model.mode.explanation)
                    .font(Theme.heading(14))
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(model.pendingFiles) { entry in
                        HStack(spacing: 12) {
                            IconTile(symbol: entry.kind.symbol, tint: entry.kind.tint, size: 30)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.name)
                                    .font(Theme.heading(14, weight: .semibold))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text(entry.displayPath)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Text(entry.bytes.byteLabel)
                                .font(Theme.figure(15, weight: .semibold))
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .frame(maxHeight: 240)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )

            if isPermanent {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.danger)
                    Text("Deleting now cannot be undone. These are your own files, not regenerable caches.")
                        .font(Theme.heading(13, weight: .medium))
                    Spacer()
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.danger.opacity(0.10)))
            }

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel") {
                    model.showFilesConfirmation = false
                    model.pendingFiles = []
                }
                .controlSize(.large)
                .keyboardShortcut(.cancelAction)
                Button(isPermanent ? "Delete" : "Move to Trash") { model.confirmCleanFiles() }
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

struct AppsConfirmSheet: View {
    @ObservedObject var model: AppModel
    @State private var runningIDs: Set<String> = []
    private var total: Int64 { model.pendingAppUninstalls.reduce(0) { $0 + $1.bytes } }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(model.pendingAppUninstalls.count == 1
                     ? "Uninstall \(model.pendingAppUninstalls.first?.app.name ?? "this app")?"
                     : "Uninstall \(model.pendingAppUninstalls.count) apps?")
                    .font(Theme.heading(18, weight: .bold))
                Text("Each app and the support files below move to the Trash, so you can put them back.")
                    .font(Theme.heading(13)).foregroundStyle(.secondary)
            }
            if !runningIDs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Running apps must quit first", systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.danger)
                    Text(runningNames).font(Theme.heading(13)).foregroundStyle(.secondary)
                    Button("Quit apps") { model.quitPendingApps(); refreshRunning() }.buttonStyle(.bordered)
                    Text("If an app refuses to quit, cancel and quit it manually.").font(Theme.heading(11)).foregroundStyle(.tertiary)
                }.card(radius: 12, padding: 12)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(model.pendingAppUninstalls) { job in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack { Image(nsImage: ApplicationIconCache.shared.icon(for: job.app.url)).resizable().scaledToFit().frame(width: 36, height: 36); Text(job.app.name).font(Theme.heading(14, weight: .semibold)); Spacer(); Text(job.app.bytes.byteLabel).font(Theme.figure(14)) }
                            Text(job.app.url.path).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                            ForEach(job.supportFiles) { file in HStack { Text(file.url.path).font(.system(size: 10.5, design: .monospaced)).lineLimit(1).truncationMode(.middle); Spacer(); Text(file.bytes.byteLabel).font(Theme.figure(11)) }.foregroundStyle(.secondary) }
                        }.card(radius: 12, padding: 12)
                    }
                }
            }.frame(maxHeight: 360)
            HStack { Text("Combined total").font(Theme.heading(13, weight: .semibold)); Spacer(); Text(total.byteLabel).font(Theme.figure(16)) }
            HStack { Spacer(); Button("Cancel") { model.showAppsConfirmation = false; model.pendingAppUninstalls = [] }.keyboardShortcut(.cancelAction); Button("Uninstall") { model.confirmUninstallApps() }.buttonStyle(.borderedProminent).tint(Theme.danger).disabled(!runningIDs.isEmpty).keyboardShortcut(.defaultAction) }
        }.padding(26).frame(width: 620)
        .onAppear { refreshRunning() }
        .task { while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(750)); refreshRunning() } }
    }
    private var runningNames: String { model.pendingAppUninstalls.filter { runningIDs.contains($0.app.bundleID) }.map(\.app.name).joined(separator: ", ") }
    private func refreshRunning() { runningIDs = model.runningSelectedBundleIDs() }
}
