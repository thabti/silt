import AppKit
import SwiftUI

@MainActor final class ApplicationIconCache: ObservableObject {
    static let shared = ApplicationIconCache()
    private var images: [String: NSImage] = [:]
    func icon(for url: URL) -> NSImage {
        if let image = images[url.path] { return image }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 128, height: 128); images[url.path] = image
        return image
    }
}

struct ApplicationsView: View {
    @ObservedObject var model: AppModel
    @State private var search = ""
    @State private var sort: Sort = .size
    @State private var filter: Filter = .all

    enum Sort: String, CaseIterable, Identifiable { case size = "Size", name = "Name", lastUsed = "Last opened"; var id: Self { self } }
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All apps", sixMonths = "Not opened in 6 months", year = "Not opened in a year", large = "Over 500 MB"
        var id: Self { self }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let notice = model.applicationsNotice { noticeRow(notice) }
                if model.appsPhase == .scanning && model.installedApps.isEmpty { loading }
                else if visible.isEmpty { empty }
                else { grid }
            }.padding(24).frame(maxWidth: 1100).frame(maxWidth: .infinity)
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Search apps")
    }

    private var header: some View {
        HStack(spacing: 16) {
            IconTile(symbol: "app.badge", tint: Theme.accent, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text("Applications").font(Theme.heading(20, weight: .bold))
                Text("\(model.installedApps.count) apps · \(model.totalInstalledAppBytes.byteLabel) · \(model.selectedInstalledApps.count) selected")
                    .font(Theme.figure(13)).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
            if model.appsPhase == .scanning { ProgressView().controlSize(.small); Button("Stop") { model.cancelInstalledAppsScan() } }
            else { Button("Rescan") { model.scanInstalledApps() }.buttonStyle(.bordered) }
            Menu {
                Section("Sort by") { Picker("Sort", selection: $sort) { ForEach(Sort.allCases) { Text($0.rawValue).tag($0) } } }
                Section("Filter") { Picker("Filter", selection: $filter) { ForEach(Filter.allCases) { Text($0.rawValue).tag($0) } } }
            } label: { Label(filter.rawValue, systemImage: "line.3.horizontal.decrease.circle") }
        }.card(padding: 22)
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 168), spacing: 14)], spacing: 14) {
            ForEach(visible) { app in ApplicationTile(app: app, selected: model.installedAppSelection.contains(app.id)) { model.toggle(app) } }
        }
    }
    private var loading: some View { VStack(spacing: 12) { ProgressView(); Text("Measuring installed applications…").foregroundStyle(.secondary); Button("Stop") { model.cancelInstalledAppsScan() } }.frame(maxWidth: .infinity).card(padding: 34) }
    private var empty: some View { Text(search.isEmpty ? "No applications found." : "No applications match your search.").frame(maxWidth: .infinity).foregroundStyle(.secondary).card(padding: 34) }
    /// A refused uninstall is not a success — and the reason (App Management) is not
    /// something anyone guesses, so the row offers the setting directly.
    @ViewBuilder
    private func noticeRow(_ text: String) -> some View {
        let blocked = model.applicationsNeedsPermission
        HStack(spacing: 10) {
            Image(systemName: blocked ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(blocked ? Theme.danger : Theme.good)
            VStack(alignment: .leading, spacing: 2) {
                Text(text).font(Theme.heading(13))
                if blocked {
                    Text("macOS blocks apps from removing other apps until you allow it.")
                        .font(Theme.heading(12)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if blocked {
                Button("Open Settings") { model.openAppManagementSettings() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.danger)
            }
        }
        .card(radius: 14, padding: 12)
    }

    private var visible: [InstalledApp] {
        let now = Date(), calendar = Calendar.current
        let filtered = model.installedApps.filter { app in
            let queryMatch = search.isEmpty || app.name.localizedCaseInsensitiveContains(search) || app.bundleID.localizedCaseInsensitiveContains(search)
            guard queryMatch else { return false }
            switch filter {
            case .all: return true
            case .large: return app.bytes >= 500 * 1_024 * 1_024
            case .sixMonths: return app.lastUsed.map { $0 < calendar.date(byAdding: .month, value: -6, to: now)! } ?? true
            case .year: return app.lastUsed.map { $0 < calendar.date(byAdding: .year, value: -1, to: now)! } ?? true
            }
        }
        return filtered.sorted { a, b in
            // Apps macOS will not let you remove sink to the bottom — they are reference,
            // not choices, and they should not sit between things you can act on.
            if a.isRemovable != b.isRemovable { return a.isRemovable }
            switch sort { case .size: return a.bytes > b.bytes; case .name: return a.name.localizedStandardCompare(b.name) == .orderedAscending; case .lastUsed: return (a.lastUsed ?? .distantPast) > (b.lastUsed ?? .distantPast) }
        }
    }
}

private struct ApplicationTile: View {
    let app: InstalledApp; let selected: Bool; let toggle: () -> Void
    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: ApplicationIconCache.shared.icon(for: app.url)).resizable().scaledToFit().frame(width: 64, height: 64)
            Text(app.name).font(Theme.heading(13, weight: .semibold)).lineLimit(2).multilineTextAlignment(.center)
            Text(app.bytes.byteLabel).font(Theme.figure(13)).monospacedDigit()
            Text(app.lastUsed.map { "Last opened \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "Never opened")
                .font(Theme.heading(10)).foregroundStyle(.tertiary).lineLimit(1)
        }.frame(maxWidth: .infinity).frame(height: 150).padding(10)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(selected ? 0.08 : 0.04)))
        .overlay(alignment: .topTrailing) { if app.isRemovable { CheckDot(isOn: selected).padding(9) } else { Image(systemName: "lock.fill").foregroundStyle(.secondary).padding(11) } }
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? Theme.accent : Color.primary.opacity(0.08), lineWidth: 1))
        .contentShape(Rectangle()).onTapGesture { toggle() }
        .accessibilityLabel("\(app.name), \(app.bytes.byteLabel)").accessibilityValue(app.isRemovable ? (selected ? "Selected" : "Not selected") : "Locked")
    }
}
