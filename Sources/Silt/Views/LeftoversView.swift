import SwiftUI

struct LeftoversView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(symbol: "app.dashed",
                       title: "App leftovers",
                       blurb: "Data left behind by apps that are no longer installed. Low-confidence matches are listed for reference and can never be removed.",
                       scannedAt: model.lastLeftoverScan) {
                HStack(spacing: 10) {
                    if model.leftoversPhase == .ready {
                        Button("Rescan") { model.scanLeftovers() }
                        if !model.leftovers.isEmpty {
                            PageTotals(bytes: model.totalLeftoverBytes,
                                       noun: "app",
                                       count: model.leftovers.count,
                                       selected: model.selectedLeftovers.count)
                        }
                    }
                }
            }

            switch model.leftoversPhase {
            case .idle:
                PagePrompt(title: "Find data apps left behind",
                           message: "Silt matches leftover folders against the apps you still have.",
                           actionTitle: "Scan for app leftovers") { model.scanLeftovers() }

            case .scanning:
                PageProgress(counts: "\(model.leftoverProgress.visited.formatted()) items checked · \(model.leftoverProgress.found) found",
                             folder: model.leftoverProgress.currentFolder,
                             fallback: "Reading app data locations…",
                             label: "Scanning for app leftovers") { model.cancelLeftoverScan() }

            case .ready:
                if let notice = model.leftoverNoticeState {
                    PageNotice(text: notice.text, isWarning: notice.hasFailures) {
                        Button("Rescan") { model.scanLeftovers() }
                    }
                }
                if model.leftovers.isEmpty {
                    PagePrompt(title: "No app leftovers found",
                               message: "Every data folder here belongs to an app you still have installed.",
                               actionTitle: "Scan again",
                               prominent: false) { model.scanLeftovers() }
                } else {
                    LazyVStack(spacing: 2) {
                        ForEach(model.leftovers) { group in
                            LeftoverGroupRow(group: group,
                                             selected: model.leftoverSelection.contains(group.id),
                                             model: model)
                            if group.id != model.leftovers.last?.id {
                                Divider().overlay(Theme.hairline).padding(.leading, 96)
                            }
                        }
                    }
                    .card(radius: 20, padding: 6)
                }
            }
        }
    }
}

struct LeftoverGroupRow: View {
    let group: AppLeftoverGroup; let selected: Bool; @ObservedObject var model: AppModel
    @State private var expanded = false
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { model.toggle(group) } label: {
                    group.isDeletable
                        ? AnyView(CheckDot(isOn: selected))
                        : AnyView(Image(systemName: "lock.fill").foregroundStyle(.secondary))
                }
                .buttonStyle(.plain)
                .disabled(!group.isDeletable)
                .accessibilityLabel(group.isDeletable
                                    ? "Select \(group.name)"
                                    : "\(group.name) cannot be removed, low-confidence match")
                .accessibilityValue(selected ? "On" : "Off")

                Button { expanded.toggle() } label: {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show locations for \(group.name)")
                .accessibilityValue(expanded ? "Expanded" : "Collapsed")
                IconTile(symbol: "app.dashed", tint: Theme.accent, size: 36)
                VStack(alignment: .leading, spacing: 3) { Text(group.name).font(Theme.heading(13)); Text(group.id).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(.tertiary) }
                Pill(text: group.confidence.label, color: group.isDeletable ? Theme.good : .secondary)
                Spacer(); VStack(alignment: .trailing) { Text(group.bytes.byteLabel).font(Theme.figure(14)); Text("\(group.items.count) locations").font(Theme.heading(11)).foregroundStyle(.tertiary) }
            }
            .padding(12)
            .contentShape(Rectangle())
            .onTapGesture { expanded.toggle() }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(group.name), \(group.bytes.byteLabel), \(group.items.count) \(group.items.count == 1 ? "location" : "locations")")
            .accessibilityValue(group.isDeletable
                                ? (selected ? "Selected" : "Not selected")
                                : "Low-confidence match, not removable")
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            if expanded { ForEach(group.items) { item in LeftoverChildRow(item: item, model: model) } }
        }
    }
}

private struct LeftoverChildRow: View {
    let item: AppLeftoverItem; @ObservedObject var model: AppModel; @State private var hover = false
    var body: some View {
        HStack(spacing: 8) {
            Text(item.location).font(Theme.heading(12))
            Text(item.url.path)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            if hover {
                Button("Reveal") { model.reveal(item.url) }.buttonStyle(.link)
            }
            Spacer()
            Text(item.bytes.byteLabel).font(Theme.figure(12))
        }
        .padding(.leading, 96)
        .padding(.trailing, 12)
        .padding(.vertical, 7)
        .onHover { hover = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.location), \(item.bytes.byteLabel)")
        .accessibilityValue(item.url.path)
    }
}

