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
            case .idle: Button("Scan for app leftovers") { model.scanLeftovers() }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity).card(padding: 34)
            case .scanning:
                VStack(spacing: 12) { ProgressView(); Text("\(model.leftoverProgress.visited) entries checked · \(model.leftoverProgress.found) found").font(Theme.figure(13)); Text(model.leftoverProgress.currentFolder).foregroundStyle(.tertiary); Button("Stop") { model.cancelLeftoverScan() } }.frame(maxWidth: .infinity).card(padding: 30)
            case .ready:
                if let notice = model.leftoverNotice { Text(notice).font(Theme.heading(13, weight: .medium)).card(radius: 14, padding: 12) }
                if model.leftovers.isEmpty { Text("No app leftovers found").font(Theme.heading(20, weight: .semibold)).frame(maxWidth: .infinity).card(padding: 30) }
                else { LazyVStack(spacing: 2) { ForEach(model.leftovers) { LeftoverGroupRow(group: $0, selected: model.leftoverSelection.contains($0.id), model: model) } }.card(radius: 20, padding: 6) }
            default: EmptyView()
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
                Button { model.toggle(group) } label: { group.isDeletable ? AnyView(CheckDot(isOn: selected)) : AnyView(Image(systemName: "lock.fill").foregroundStyle(.secondary)) }.buttonStyle(.plain).disabled(!group.isDeletable)
                Button { expanded.toggle() } label: { Image(systemName: expanded ? "chevron.down" : "chevron.right") }.buttonStyle(.plain)
                IconTile(symbol: "app.dashed", tint: Theme.accent, size: 36)
                VStack(alignment: .leading, spacing: 3) { Text(group.name).font(Theme.heading(13)); Text(group.id).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(.tertiary) }
                Pill(text: group.confidence.rawValue, color: group.isDeletable ? Theme.good : .secondary)
                Spacer(); VStack(alignment: .trailing) { Text(group.bytes.byteLabel).font(Theme.figure(14)); Text("\(group.items.count) locations").font(Theme.heading(11)).foregroundStyle(.tertiary) }
            }.padding(12).contentShape(Rectangle()).onTapGesture { expanded.toggle() }
            if expanded { ForEach(group.items) { item in LeftoverChildRow(item: item, model: model) } }
        }
    }
}

private struct LeftoverChildRow: View {
    let item: AppLeftoverItem; @ObservedObject var model: AppModel; @State private var hover = false
    var body: some View { HStack { Text(item.location).font(Theme.heading(12)); Text(item.url.path).font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle); if hover { Button("Reveal") { model.reveal(item.url) }.buttonStyle(.link) }; Spacer(); Text(item.bytes.byteLabel).font(Theme.figure(12)) }.padding(.leading, 88).padding(.trailing, 12).padding(.vertical, 7).onHover { hover = $0 } }
}
