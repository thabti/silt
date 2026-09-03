import SwiftUI

struct LeftoversView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 16) {
                IconTile(symbol: "app.dashed", tint: Theme.accent, size: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text("App leftovers").font(Theme.heading(20, weight: .bold))
                    Text("Data left behind by apps that are no longer installed. Low-confidence matches are shown but never removable.")
                        .font(Theme.heading(14)).foregroundStyle(.secondary)
                    if let date = model.lastLeftoverScan { Text("Scanned \(date.formatted(date: .omitted, time: .shortened))").font(Theme.heading(12)).foregroundStyle(.tertiary) }
                }
                Spacer()
                if model.leftoversPhase == .ready { Button("Rescan") { model.scanLeftovers() }.buttonStyle(.bordered) }
                if model.leftoversPhase == .ready, !model.leftovers.isEmpty {
                    VStack(alignment: .trailing) { Text(model.totalLeftoverBytes.byteLabel).font(Theme.figure(20)); Text("\(model.leftovers.count) apps").font(Theme.heading(12)).foregroundStyle(.secondary) }
                }
            }.card(padding: 22)
            switch model.leftoversPhase {
            case .idle:
                VStack(spacing: 14) {
                    Text("Find data apps left behind")
                        .font(Theme.heading(22, weight: .bold))
                    Text("Silt matches leftover folders against the apps you still have. Low-confidence matches are listed for reference and can never be removed.")
                        .font(Theme.heading(14))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 460)
                    Button("Scan for app leftovers") { model.scanLeftovers() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.extraLarge)
                        .tint(Theme.accent)
                }
                .frame(maxWidth: .infinity)
                .card(padding: 34)
            case .scanning:
                VStack(spacing: 12) {
                    ProgressView().accessibilityLabel("Scanning for app leftovers")
                    Text("\(model.leftoverProgress.visited.formatted()) items checked · \(model.leftoverProgress.found) found")
                        .font(Theme.figure(13, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(model.leftoverProgress.currentFolder.isEmpty ? "Reading app data locations…" : model.leftoverProgress.currentFolder)
                        .font(Theme.heading(12))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .accessibilityHidden(true)
                    Button("Stop") { model.cancelLeftoverScan() }.controlSize(.large)
                }.frame(maxWidth: .infinity).card(padding: 30)
            case .ready:
                if let notice = model.leftoverNotice {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.good)
                            .accessibilityHidden(true)
                        Text(notice).font(Theme.heading(13))
                        Spacer()
                        Button("Rescan") { model.scanLeftovers() }
                    }
                    .card(radius: 14, padding: 12)
                    .accessibilityElement(children: .combine)
                }
                if model.leftovers.isEmpty {
                    VStack(spacing: 10) {
                        Text("No app leftovers found").font(Theme.heading(20, weight: .semibold))
                        Text("Every data folder here belongs to an app you still have installed.")
                            .font(Theme.heading(13)).foregroundStyle(.secondary)
                        Button("Scan again") { model.scanLeftovers() }.controlSize(.large)
                    }.frame(maxWidth: .infinity).card(padding: 30)
                }
                else { LazyVStack(spacing: 2) { ForEach(model.leftovers) { LeftoverGroupRow(group: $0, selected: model.leftoverSelection.contains($0.id), model: model) } }.card(radius: 20, padding: 6) }
            }
        }
    }
}

private struct LeftoverGroupRow: View {
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
    var body: some View { HStack { Text(item.location).font(Theme.heading(12)); Text(item.url.path).font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle); if hover { Button("Reveal") { model.reveal(item.url) }.buttonStyle(.link) }; Spacer(); Text(item.bytes.byteLabel).font(Theme.figure(12)) }.padding(.leading, 88).padding(.trailing, 12).padding(.vertical, 7).onHover { hover = $0 } }
}
