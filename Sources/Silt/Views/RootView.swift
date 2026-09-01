import SwiftUI

struct RootView: View {
    @ObservedObject var model: AppModel
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue

    private var appearance: Appearance { Appearance(rawValue: appearanceRaw) ?? .system }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 236, max: 280)
        } detail: {
            detail
                .toolbar { toolbarContent }
        }
        .sheet(isPresented: $model.showConfirmation) {
            ConfirmSheet(model: model)
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
            if model.phase == .idle { model.scan() }
        }
        .onChange(of: model.route) { _, route in
            // Measuring the review folders is a minute of disk work, so it waits until
            // you actually open the page that shows them.
            if route == .category(.review) { model.measureReview() }
        }
    }

    // MARK: - Toolbar

    /// Actions live in the toolbar, where Mac apps keep them — not in a floating bar.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Picker("Appearance", selection: $appearanceRaw) {
                    ForEach(Appearance.allCases) { option in
                        Label(option.title, systemImage: option.symbol).tag(option.rawValue)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: appearance.symbol)
            }
            .help("Appearance")

            if model.route != .files, model.route != .artifacts, model.phase == .ready, model.scopedCleanableCount > 0 {
                Picker("After cleaning", selection: $model.mode) {
                    ForEach(DeletionMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
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
                }
            }
            .listStyle(.sidebar)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                if model.isScanning {
                    VStack(alignment: .leading, spacing: 5) {
                        ProgressView(value: model.scanProgress.fraction)
                            .progressViewStyle(.linear)
                        Text("Measuring \(model.scanProgress.completed) of \(model.scanProgress.total)")
                            .font(Theme.figure(11, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                } else if let last = model.lastScan {
                    Text("Scanned \(last.formatted(date: .omitted, time: .shortened))")
                        .font(Theme.heading(11, weight: .regular))
                        .foregroundStyle(.tertiary)
                }

                Button {
                    model.isScanning ? model.cancelScan() : model.scan()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: model.isScanning ? "stop.fill" : "arrow.clockwise")
                        Text(model.isScanning ? "Stop" : "Rescan")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(model.phase == .cleaning)
            }
            .padding(12)
        }
        .navigationTitle("Silt")
    }

    private func sidebarRow(route: AppModel.Route, symbol: String, trailing: Int64) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(categoryOf(route).map(Theme.tint) ?? Theme.accent)
                .frame(width: 20)
            Text(route.title)
                .font(Theme.heading(13, weight: .regular))
            Spacer()
            if trailing > 0 {
                Text(trailing.byteLabel)
                    .font(Theme.figure(11, weight: .regular))
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
        content
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
