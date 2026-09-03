import SwiftUI

struct RootView: View {
    @ObservedObject var model: AppModel
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue
    @AppStorage("protectedLocations") private var protectedLocations = true
    @State private var showDisableProtectionConfirmation = false

    private var appearance: Appearance { Appearance(rawValue: appearanceRaw) ?? .system }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 300)
        } detail: {
            detail
                .toolbar { toolbarContent }
        }
        .sheet(isPresented: $model.showConfirmation) {
            ConfirmSheet(model: model)
        }
        .sheet(isPresented: $model.showFilesConfirmation) {
            FilesConfirmSheet(model: model)
        }
        .sheet(isPresented: $model.showAppsConfirmation) { AppsConfirmSheet(model: model) }
        .alert("Turn off personal-folder protection?", isPresented: $showDisableProtectionConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Turn Off Protection", role: .destructive) {
                protectedLocations = false
            }
            .tint(Theme.danger)
        } message: {
            Text("Silt will no longer refuse to list or trash items inside Documents, Desktop, Downloads, Photos, .ssh, and the rest of the protected-location list. Hand-picked files remain Trash-only, but caches may be deleted permanently.")
        }
        .sheet(isPresented: Binding(
            get: { model.phase == .finished && model.report != nil },
            set: { if !$0 { model.dismissReport() } }
        )) {
            if let report = model.report {
                ReportSheet(model: model, report: report)
            }
        }
        .preferredColorScheme(appearance.colorScheme)
        .onAppear {
            SafetyGuard.protectedLocationsEnabled = protectedLocations
            if model.phase == .idle { model.scan() }
            if model.route == .artifacts { model.scanArtifactsIfNeeded() }
            if model.route == .leftovers { model.scanLeftoversIfNeeded() }
            if model.route == .installedApps { model.scanInstalledAppsIfNeeded() }
        }
        .onChange(of: protectedLocations) { _, enabled in
            SafetyGuard.protectedLocationsEnabled = enabled
        }
        .onChange(of: model.route) { _, route in
            // Measuring the review folders is a minute of disk work, so it waits until
            // you actually open the page that shows them.
            if route == .category(.review) { model.measureReview() }
            if route == .artifacts { model.scanArtifactsIfNeeded() }
            if route == .leftovers { model.scanLeftoversIfNeeded() }
            if route == .installedApps { model.scanInstalledAppsIfNeeded() }
        }
    }

    // MARK: - Toolbar

    /// Actions live in the toolbar, where Mac apps keep them — not in a floating bar.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // The scan control sits on the leading side, apart from the destructive actions.
        ToolbarItem(placement: .navigation) {
            Button {
                model.isScanning ? model.cancelScan() : model.scan()
            } label: {
                if model.isScanning {
                    Label("Stop", systemImage: "stop.fill")
                } else {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
            }
            .disabled(model.phase == .cleaning)
            .help(scanHelp)
            .accessibilityLabel(model.isScanning ? "Stop scanning" : "Rescan")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                SettingsControls(appearanceRaw: $appearanceRaw,
                                 protectedLocations: $protectedLocations,
                                 showDisableProtectionConfirmation: $showDisableProtectionConfirmation)
            } label: {
                Image(systemName: protectedLocations ? "gearshape" : "exclamationmark.triangle.fill")
                    .foregroundStyle(protectedLocations ? Color.primary : Theme.danger)
            }
            .help(protectedLocations ? "Settings" : "Personal-folder protection is off")
            .accessibilityLabel(protectedLocations ? "Settings" : "Settings, personal-folder protection is off")

            // Large files: same mode + Clean pair as the cache pages. Permanent deletion
            // of hand-picked files exists by explicit request; the confirmation sheet is
            // what stands between the click and the disk.
            if model.route == .files, model.filesPhase == .ready, !model.files.isEmpty {
                Menu {
                    Section("After cleaning") {
                        Picker("After cleaning", selection: $model.mode) {
                            ForEach(DeletionMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.inline)
                    }
                } label: {
                    Label(model.mode.title, systemImage: model.mode == .trash ? "trash" : "trash.slash")
                }
                .help(model.mode.explanation)
                .accessibilityLabel("After cleaning: \(model.mode.title)")

                Button {
                    model.requestCleanFiles()
                } label: {
                    Label(
                        model.selectedFileBytes > 0 ? "Clean \(model.selectedFileBytes.byteLabel)" : "Clean",
                        systemImage: "trash"
                    )
                    .labelStyle(.titleAndIcon)
                }
                .disabled(model.selectedFiles.isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
                .tint(model.mode == .permanent ? Theme.danger : nil)
                .help("\(model.selectedFiles.count) selected · \(model.mode.explanation)")
            }
            if model.route == .installedApps {
                Button(model.selectedInstalledAppBytes > 0 ? "Uninstall \(model.selectedInstalledAppBytes.byteLabel)" : "Uninstall") { model.requestUninstallApps() }
                    .buttonStyle(.borderedProminent).tint(Theme.danger)
                    .disabled(model.selectedInstalledApps.isEmpty)
            }

            if model.route == .artifacts, model.artifactsPhase == .ready, !model.artifacts.isEmpty {
                Button {
                    model.trashSelectedArtifacts()
                } label: {
                    Label(
                        model.selectedArtifactBytes > 0 ? "Move to Trash \(model.selectedArtifactBytes.byteLabel)" : "Move to Trash",
                        systemImage: "trash"
                    )
                    .labelStyle(.titleAndIcon)
                }
                .disabled(model.selectedArtifacts.isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Artifacts always go to the Trash — they regenerate on the next install or build")
            }

            if model.route == .leftovers, model.leftoversPhase == .ready, !model.leftovers.isEmpty {
                Button { model.trashSelectedLeftovers() } label: {
                    Label(model.selectedLeftoverBytes > 0 ? "Move to Trash \(model.selectedLeftoverBytes.byteLabel)" : "Move to Trash", systemImage: "trash")
                        .labelStyle(.titleAndIcon)
                }.disabled(model.selectedLeftovers.isEmpty).keyboardShortcut(.return, modifiers: .command)
                    .help("High-confidence leftovers always go to the Trash")
            }

            if model.route.isCachePage, model.phase == .ready, model.scopedCleanableCount > 0 {
                Menu {
                    Section("After cleaning") {
                        Picker("After cleaning", selection: $model.mode) {
                            ForEach(DeletionMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.inline)
                    }
                } label: {
                    Label(model.mode.title, systemImage: model.mode == .trash ? "trash" : "trash.slash")
                }
                .help(model.mode.explanation)

                if model.bytesSelectedOutsideScope > 0 {
                    Menu {
                        Button("Clean everything selected — \(model.selectedBytes.byteLabel)") {
                            model.requestClean(.everythingSelected)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .help("Includes locations selected on other pages")
                }

                Button {
                    model.requestClean(.currentPage)
                } label: {
                    Label(
                        model.scopedBytes > 0 ? "Clean \(model.scopedBytes.byteLabel)" : "Clean",
                        systemImage: "trash"
                    )
                    .labelStyle(.titleAndIcon)
                }
                .disabled(model.scopedBuckets.isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
                .tint(model.mode == .permanent ? Theme.danger : nil)
                .help(scopeCaption)
            }
        }
    }

    private var scanHelp: String {
        if model.isScanning {
            return "Stop — measuring \(model.scanProgress.completed) of \(model.scanProgress.total)"
        }
        if let last = model.lastScan {
            return "Rescan (last scanned \(last.formatted(date: .omitted, time: .shortened)))"
        }
        return "Scan"
    }

    private var scopeCaption: String {
        if let category = model.scopeCategory {
            return "\(model.scopedBuckets.count) of \(model.scopedCleanableCount) in \(category.title) selected"
        }
        return "\(model.selectedBuckets.count) of \(model.cleanable.count) locations selected"
    }

    // MARK: - Sidebar

    /// Categories that hold something, plus whichever one you are looking at.
    ///
    /// Keeping the current page in the list matters after a clean: emptying Browsers
    /// should not delete the row out from under you while you are standing on it.
    private var sidebarCategories: [CleanCategory] {
        var categories = model.categoriesWithContent
        if let current = model.scopeCategory, !categories.contains(current) {
            categories.append(current)
        }
        // Review is reachable before it has been measured — that is where you go to ask for it.
        if model.hasReviewTargets, !categories.contains(.review) {
            categories.append(.review)
        }
        return categories
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: $model.route) {
                sidebarRow(route: .overview, symbol: "internaldrive.fill", trailing: model.junkBytes)

                if !sidebarCategories.isEmpty {
                    Section("Caches") {
                        ForEach(sidebarCategories) { category in
                            sidebarRow(
                                route: .category(category),
                                symbol: category.symbol,
                                trailing: model.bytes(in: category)
                            )
                        }
                    }
                }

                Section("Storage") {
                    sidebarRow(route: .files, symbol: "doc.text.magnifyingglass", trailing: model.totalFileBytes)
                    sidebarRow(route: .artifacts, symbol: "shippingbox", trailing: model.totalArtifactBytes)
                    sidebarRow(route: .leftovers, symbol: "app.dashed", trailing: model.totalLeftoverBytes)
                    sidebarRow(route: .installedApps, symbol: "app.badge", trailing: model.totalInstalledAppBytes)
                }
            }
            .listStyle(.sidebar)
            .environment(\.sidebarRowSize, .large)
        }
        .navigationTitle("Silt")
    }

    private func sidebarRow(route: AppModel.Route, symbol: String, trailing: Int64) -> some View {
        HStack(spacing: 8) {
            Label {
                Text(route.title)
            } icon: {
                Image(systemName: symbol)
                    .foregroundStyle(categoryOf(route).map(Theme.tint) ?? Theme.accent)
            }
            Spacer()
            if trailing > 0 {
                Text(trailing.byteLabel)
                    .font(Theme.figure(12, weight: .regular))
                    .foregroundStyle(.tertiary)
            }
        }
        .tag(route)
    }

    private func categoryOf(_ route: AppModel.Route) -> CleanCategory? {
        if case let .category(category) = route { return category }
        return nil
    }

    // MARK: - Detail

    private var detail: some View {
        VStack(spacing: 0) {
            if !protectedLocations {
                protectionWarning
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
            }

            content
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.canvas)
            .overlay(alignment: .top) {
                // A rescan over existing results is a background job, not a new screen.
                if model.isScanning, model.hasResults {
                    ProgressView(value: model.scanProgress.fraction)
                        .progressViewStyle(.linear)
                        .tint(Theme.accent)
                        .frame(height: 2)
                }
            }
            .navigationTitle(model.route.title)
    }

    private var protectionWarning: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.danger)
            Text("Personal-folder protection is off — Silt will not refuse Documents, Photos, .ssh, …")
                .font(Theme.heading(12, weight: .medium))
            Spacer(minLength: 12)
            Button("Turn back on") {
                protectedLocations = true
            }
            .buttonStyle(.bordered)
            .tint(Theme.danger)
            .accessibilityLabel("Turn personal-folder protection back on")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.danger.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Theme.danger.opacity(0.35), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Warning: Personal-folder protection is off. Silt will not refuse Documents, Photos, SSH, and other protected folders.")
        .accessibilityAddTraits(.isStaticText)
    }

    @ViewBuilder
    private var content: some View {
        if model.route == .files {
            ScrollView {
                FilesView(model: model)
                    .padding(24)
                    .frame(maxWidth: 900, alignment: .leading)
                    .frame(maxWidth: .infinity)
            }
        } else if model.route == .artifacts {
            ScrollView {
                ArtifactsView(model: model)
                    .padding(24)
                    .frame(maxWidth: 900, alignment: .leading)
                    .frame(maxWidth: .infinity)
            }
        } else if model.route == .leftovers {
            ScrollView {
                LeftoversView(model: model).padding(24).frame(maxWidth: 900, alignment: .leading).frame(maxWidth: .infinity)
            }
        } else if model.route == .installedApps {
            ApplicationsView(model: model)
        } else if model.phase == .cleaning {
            StatusPanel(
                symbol: "trash",
                title: "Clearing up",
                message: model.cleanProgress.currentName
            ) {
                ProgressView(value: model.cleanProgress.fraction)
                    .progressViewStyle(.linear)
                    .frame(width: 320)
            }
        } else if model.hasResults {
            ScrollView {
                Group {
                    switch model.route {
                    case .overview:
                        OverviewView(model: model)
                    case .category(let category):
                        CategoryDetailView(model: model, category: category)
                    case .files:
                        EmptyView()
                    case .artifacts:
                        EmptyView()
                    case .leftovers:
                        EmptyView()
                    case .installedApps:
                        EmptyView()
                    }
                }
                .padding(24)
                .frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        } else if model.phase == .scanning {
            StatusPanel(
                symbol: "magnifyingglass",
                title: "Measuring \(model.scanProgress.total) locations",
                message: model.scanProgress.currentName.isEmpty ? "Reading sizes…" : model.scanProgress.currentName
            ) {
                VStack(spacing: 12) {
                    ProgressView(value: model.scanProgress.fraction)
                        .progressViewStyle(.linear)
                        .frame(width: 320)
                    Text("\(model.scanProgress.completed) of \(model.scanProgress.total)")
                        .font(Theme.figure(12, weight: .regular))
                        .foregroundStyle(.secondary)
                    Button("Stop") { model.cancelScan() }
                }
            }
        } else if model.phase == .idle {
            StatusPanel(
                symbol: "magnifyingglass",
                title: "Let's find some space",
                message: "Silt looks at \(Catalog.all.count) known cache and log locations. Nothing is removed until you say so."
            ) {
                Button("Scan my Mac") { model.scan() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(Theme.accent)
            }
        } else {
            StatusPanel(
                symbol: "checkmark.seal",
                title: "Nothing to clean",
                message: "None of the known cache locations hold anything worth removing right now."
            ) {
                Button("Scan again") { model.scan() }
                    .buttonStyle(.bordered)
            }
        }
    }
}
