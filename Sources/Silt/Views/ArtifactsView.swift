import SwiftUI

struct ArtifactsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            switch model.artifactsPhase {
            case .idle: idleCard
            case .scanning: scanningCard
            case .ready:
                if model.artifacts.isEmpty { emptyCard }
                else {
                    if let notice = model.artifactNotice { noticeRow(notice) }
                    artifactList
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            IconTile(symbol: "shippingbox", tint: Theme.accent, size: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text("Build artifacts").font(Theme.heading(20, weight: .bold)).accessibilityAddTraits(.isHeader)
                Text("Dependency and build folders across your home. They regenerate on the next install or build.")
                    .font(Theme.heading(14)).foregroundStyle(.secondary)
                if let scanned = model.lastArtifactScan {
                    Text("Scanned \(scanned.formatted(date: .omitted, time: .shortened))")
                        .font(Theme.heading(12)).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if model.artifactsPhase == .ready {
                Button("Rescan") { model.scanArtifacts() }.buttonStyle(.bordered)
            }
            if model.artifactsPhase == .ready, !model.artifacts.isEmpty {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(model.totalArtifactBytes.byteLabel).font(Theme.figure(20))
                    Text(model.selectedArtifacts.isEmpty
                         ? "\(model.artifacts.count) folders"
                         : "\(model.selectedArtifacts.count) of \(model.artifacts.count) selected")
                        .font(Theme.heading(12)).foregroundStyle(.secondary)
                }
            }
        }.card(padding: 22)
    }

    private var idleCard: some View {
        VStack(spacing: 14) {
            Text("Find old project weight").font(Theme.heading(22, weight: .bold))
            Text("Silt checks project markers before listing a folder. Nothing moves until you select it.")
                .font(Theme.heading(14)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Scan for build artifacts") { model.scanArtifacts() }
                .buttonStyle(.borderedProminent).controlSize(.extraLarge).tint(Theme.accent)
        }.frame(maxWidth: .infinity).card(padding: 34)
    }

    private var scanningCard: some View {
        VStack(spacing: 12) {
            ProgressView().accessibilityLabel("Scanning for build artifacts").controlSize(.small)
            Text("\(model.artifactProgress.visited.formatted()) items checked · \(model.artifactProgress.found) artifacts found")
                .font(Theme.figure(13, weight: .medium)).foregroundStyle(.secondary)
            Text(model.artifactProgress.currentFolder.isEmpty ? "Walking your home folder…" : model.artifactProgress.currentFolder)
                .font(Theme.heading(12)).foregroundStyle(.tertiary)
            Button("Stop") { model.cancelArtifactScan() }.controlSize(.large)
        }.frame(maxWidth: .infinity).card(padding: 30)
    }

    private var emptyCard: some View {
        VStack(spacing: 10) {
            Text("No build artifacts found").font(Theme.heading(20, weight: .semibold))
            Text("Only folders with a matching project marker are shown.").font(Theme.heading(13)).foregroundStyle(.secondary)
            Button("Scan again") { model.scanArtifacts() }.buttonStyle(.bordered)
        }.frame(maxWidth: .infinity).card(padding: 30)
    }


    private func noticeRow(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.good)
            Text(text).font(Theme.heading(13, weight: .medium))
            Spacer()
            Button("Rescan") { model.scanArtifacts() }
        }.card(radius: 14, padding: 12)
    }

    private var artifactList: some View {
        LazyVStack(spacing: 2) {
            ForEach(model.artifacts) { artifact in
                ArtifactRow(artifact: artifact, isSelected: model.artifactSelection.contains(artifact.id)) {
                    model.toggle(artifact)
                } onReveal: { model.reveal(artifact.url) }
                if artifact.id != model.artifacts.last?.id { Divider().opacity(0.35).padding(.leading, 88) }
            }
        }.card(radius: 20, padding: 6)
    }
}

private struct ArtifactRow: View {
    let artifact: ProjectArtifact
    let isSelected: Bool
    let onToggle: () -> Void
    let onReveal: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onToggle) { CheckDot(isOn: isSelected) }
                .buttonStyle(.plain)
                .accessibilityLabel("Select \(artifact.projectName)")
                .accessibilityValue(isSelected ? "On" : "Off")
            IconTile(symbol: "folder.badge.gearshape", tint: Theme.accent, size: 36)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(artifact.projectName).font(Theme.heading(13)).lineLimit(1)
                    Pill(text: artifact.pattern.title, color: Theme.accent)
                }
                HStack(spacing: 8) {
                    Text(artifact.displayPath).font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                    Button("Reveal", action: onReveal).buttonStyle(.link).opacity(hovering ? 1 : 0)
                }
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 2) {
                Text(artifact.bytes.byteLabel).font(Theme.figure(14))
                Text(artifact.lastTouched?.formatted(date: .abbreviated, time: .omitted) ?? "Unknown")
                    .font(Theme.heading(11)).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 9).padding(.horizontal, 12).contentShape(Rectangle())
        .background(RoundedRectangle(cornerRadius: 8).fill(hovering ? Color.primary.opacity(0.04) : .clear))
        .onTapGesture(perform: onToggle).onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(artifact.projectName), \(artifact.pattern.title), \(artifact.bytes.byteLabel)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
