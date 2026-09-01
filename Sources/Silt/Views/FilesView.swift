import SwiftUI

/// The simple part: what are the biggest things on this Mac, sorted by size,
/// grouped by what they are. Selected items go to the Trash and nowhere else.
struct FilesView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            switch model.filesPhase {
            case .idle:
                idleCard
            case .scanning:
                scanningCard
            case .ready:
                if model.files.isEmpty {
                    emptyCard
                } else {
                    breakdown
                    chips
                    if !model.selectedFiles.isEmpty { selectionBar }
                    if let notice = model.fileNotice { noticeRow(notice) }
                    list
                }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            IconTile(symbol: "doc.text.magnifyingglass", tint: Theme.accent, size: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text("Large files")
                    .font(Theme.heading(20, weight: .bold))
                Text("Everything in your home folder, biggest first. Bundles like apps and photo libraries count as one item.")
                    .font(Theme.heading(14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 8) {
                if model.filesPhase == .ready, !model.files.isEmpty {
                    Text(model.listedFileBytes.byteLabel)
                        .font(Theme.figure(20))
                    Text("\(model.filteredFiles.count) items listed")
                        .font(Theme.heading(12))
                        .foregroundStyle(.secondary)
                }
                Picker("", selection: $model.fileThreshold) {
                    ForEach(AppModel.fileThresholds) { threshold in
                        Text(threshold.title).tag(threshold.bytes)
                    }
                }
                .labelsHidden()
                .frame(width: 150)
                .onChange(of: model.fileThreshold) { _, _ in
                    if model.filesPhase != .idle { model.scanFiles() }
                }
            }
        }
        .card(padding: 22)
    }

    // MARK: States

    private var idleCard: some View {
        VStack(spacing: 14) {
            Text("Find the big stuff")
                .font(Theme.heading(22, weight: .bold))
            Text("Silt walks your home folder and lists anything over \(model.fileThreshold.byteLabel). Read-only — nothing moves until you pick it.")
                .font(Theme.heading(14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            Button("Scan for large files") { model.scanFiles() }
                .buttonStyle(.borderedProminent)
                .controlSize(.extraLarge)
                .tint(Theme.accent)
        }
        .frame(maxWidth: .infinity)
        .card(padding: 34)
    }

    private var scanningCard: some View {
        VStack(spacing: 12) {
            ProgressView(value: min(1, Double(model.fileProgress.visited) / 400_000))
                .progressViewStyle(.linear)
                .frame(maxWidth: 420)
            Text("\(model.fileProgress.visited.formatted()) items checked · \(model.fileProgress.found) big ones so far")
                .font(Theme.figure(13, weight: .medium))
                .foregroundStyle(.secondary)
            Text(model.fileProgress.currentFolder.isEmpty ? "Walking your home folder…" : model.fileProgress.currentFolder)
                .font(Theme.heading(12))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Button("Stop") { model.cancelFileScan() }
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .card(padding: 30)
    }

    private var emptyCard: some View {
        VStack(spacing: 10) {
            Text("Nothing over \(model.fileThreshold.byteLabel)")
                .font(Theme.heading(20, weight: .semibold))
            Text("Try a smaller threshold.")
                .font(Theme.heading(13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .card(padding: 30)
    }

    // MARK: Breakdown

    private var breakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What is taking the space")
                .font(Theme.heading(15, weight: .semibold))

            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(model.fileKindTotals) { total in
                        Rectangle()
                            .fill(total.kind.tint)
                            .frame(width: max(2, geo.size.width * fraction(of: total.bytes)))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 16)

            HStack(spacing: 18) {
                ForEach(model.fileKindTotals.prefix(5)) { total in
                    HStack(spacing: 7) {
                        Circle().fill(total.kind.tint).frame(width: 9, height: 9)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(total.kind.title)
                                .font(Theme.heading(12, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text(total.bytes.byteLabel)
                                .font(Theme.figure(14, weight: .semibold))
                        }
                    }
                }
                Spacer()
            }
        }
        .card(radius: 18, padding: 18)
    }

    private func fraction(of bytes: Int64) -> Double {
        let total = model.totalFileBytes
        return total > 0 ? Double(bytes) / Double(total) : 0
    }

    // MARK: Filter chips

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "All \(model.files.count)", tint: Theme.accent, active: model.kindFilter == nil) {
                    model.kindFilter = nil
                }
                ForEach(model.fileKindTotals) { total in
                    chip(
                        title: "\(total.kind.title) \(total.count)",
                        tint: total.kind.tint,
                        active: model.kindFilter == total.kind
                    ) {
                        model.kindFilter = model.kindFilter == total.kind ? nil : total.kind
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func chip(title: String, tint: Color, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.heading(12.5, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(active ? AnyShapeStyle(tint) : AnyShapeStyle(Color.primary.opacity(0.06)))
                )
                .foregroundStyle(active ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: Selection

    private var selectionBar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text(model.selectedFileBytes.byteLabel)
                    .font(Theme.figure(15))
                Text("\(model.selectedFiles.count) selected")
                    .font(Theme.heading(12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("Hand-picked files always go to the Trash, never straight to deletion.")
                .font(Theme.heading(12))
                .foregroundStyle(.tertiary)
            Button("Deselect") { model.fileSelection.removeAll() }
                .controlSize(.large)
            Button {
                model.trashSelectedFiles()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                    Text("Move to Trash")
                        .font(Theme.heading(14, weight: .semibold))
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Theme.accent)
        }
        .card(radius: 16, padding: 14)
    }

    private func noticeRow(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.good)
            Text(text)
                .font(Theme.heading(13, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Rescan") { model.scanFiles() }
                .controlSize(.regular)
        }
        .card(radius: 14, padding: 12)
    }

    // MARK: List

    private var list: some View {
        LazyVStack(spacing: 2) {
            ForEach(model.filteredFiles) { entry in
                FileRow(
                    entry: entry,
                    isSelected: model.isSelected(entry),
                    onToggle: { model.toggle(entry) },
                    onReveal: { model.reveal(entry.url) }
                )
                if entry.id != model.filteredFiles.last?.id {
                    Divider().opacity(0.35).padding(.leading, 96)
                }
            }
        }
        .card(radius: 20, padding: 6)
    }
}

struct FileRow: View {
    let entry: FileEntry
    let isSelected: Bool
    let onToggle: () -> Void
    let onReveal: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onToggle) { CheckDot(isOn: isSelected) }
                .buttonStyle(.plain)

            IconTile(symbol: entry.kind.symbol, tint: entry.kind.tint, size: 36)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(entry.name)
                        .font(Theme.heading(13))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if entry.isBundle {
                        Pill(text: "Bundle", color: entry.kind.tint)
                    }
                }
                HStack(spacing: 8) {
                    Text(entry.displayPath)
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
                Text(entry.bytes.byteLabel)
                    .font(Theme.figure(14))
                Text(entry.modifiedLabel)
                    .font(Theme.heading(11.5))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(hovering ? Color.primary.opacity(0.04) : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { onToggle() }
        .onHover { hovering = $0 }
    }
}
