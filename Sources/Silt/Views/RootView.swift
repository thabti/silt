import SwiftUI

struct RootView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 232, ideal: 244, max: 280)
        } detail: {
            detail
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
        .onAppear {
            if model.phase == .idle { model.scan() }
        }
        .onChange(of: model.route) { _, route in
            // Measuring the review folders is a minute of disk work, so it waits until
            // you actually open the page that shows them.
            if route == .category(.review) { model.measureReview() }
        }
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
            HStack(spacing: 11) {
                IconTile(symbol: "sparkles", gradient: Theme.accentGradient, size: 34)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Silt")
                        .font(Theme.heading(19, weight: .bold))
                    Text("Disk cleanup")
                        .font(Theme.heading(11.5))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 14)

            List(selection: $model.route) {
                sidebarRow(route: .overview, symbol: "chart.pie.fill", trailing: model.junkBytes)

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
                }
            }
            .listStyle(.sidebar)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                if model.isScanning {
                    VStack(alignment: .leading, spacing: 5) {
                        ProgressView(value: model.scanProgress.fraction)
                            .progressViewStyle(.linear)
                        Text("Measuring \(model.scanProgress.completed) of \(model.scanProgress.total)")
                            .font(Theme.figure(11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                } else if let last = model.lastScan {
                    Text("Scanned \(last.formatted(date: .omitted, time: .shortened))")
                        .font(Theme.heading(11.5))
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
                .controlSize(.large)
                .disabled(model.phase == .cleaning)
            }
            .padding(14)
        }
    }

    private func sidebarRow(route: AppModel.Route, symbol: String, trailing: Int64) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(categoryOf(route).map(Theme.tint) ?? Theme.accent)
                .frame(width: 20)
            Text(route.title)
                .font(Theme.heading(14, weight: .medium))
            Spacer()
            if trailing > 0 {
                Text(trailing.byteLabel)
                    .font(Theme.figure(11.5, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
        .tag(route)
    }

    private func categoryOf(_ route: AppModel.Route) -> CleanCategory? {
        if case let .category(category) = route { return category }
        return nil
    }

    // MARK: - Detail

    private var detail: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [Theme.canvas, Theme.canvas.opacity(0.92), Theme.accent.opacity(0.06)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            content

            if model.route != .files, model.phase == .ready,
               model.scopedCleanableCount > 0 || model.bytesSelectedOutsideScope > 0 {
                actionBar
            }
        }
        .overlay(alignment: .top) {
            // A rescan over existing results is a background job, not a new screen.
            if model.isScanning, model.hasResults {
                ProgressView(value: model.scanProgress.fraction)
                    .progressViewStyle(.linear)
                    .tint(Theme.accent)
                    .frame(height: 2)
            }
        }
        .navigationTitle("")
    }

    @ViewBuilder
    private var content: some View {
        if model.route == .files {
            ScrollView {
                FilesView(model: model)
                    .padding(28)
                    .frame(maxWidth: 1000, alignment: .leading)
                    .frame(maxWidth: .infinity)
            }
        } else if model.phase == .cleaning {
            StatusPanel(
                symbol: "wand.and.sparkles",
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
                    }
                }
                .padding(28)
                .padding(.bottom, 108)
                .frame(maxWidth: 1000, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        } else if model.phase == .scanning {
            StatusPanel(
                symbol: "hourglass",
                title: "Measuring \(model.scanProgress.total) locations",
                message: model.scanProgress.currentName.isEmpty ? "Reading sizes…" : model.scanProgress.currentName
            ) {
                VStack(spacing: 12) {
                    ProgressView(value: model.scanProgress.fraction)
                        .progressViewStyle(.linear)
                        .frame(width: 320)
                    Text("\(model.scanProgress.completed) of \(model.scanProgress.total)")
                        .font(Theme.figure(13, weight: .medium))
                        .foregroundStyle(.secondary)
                    Button("Stop") { model.cancelScan() }
                        .controlSize(.large)
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
                    .controlSize(.extraLarge)
                    .tint(Theme.accent)
            }
        } else {
            StatusPanel(
                symbol: "checkmark.seal.fill",
                title: "Nothing to clean",
                message: "None of the known cache locations hold anything worth removing right now."
            ) {
                Button("Scan again") { model.scan() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }
        }
    }

    // MARK: - Action bar

    /// The bar acts on the page you are looking at: inside Browsers it cleans browsers,
    /// on the overview it cleans everything ticked. Anything selected on another page is
    /// offered separately rather than folded in silently.
    private var actionBar: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.scopedBytes.byteLabel)
                    .font(Theme.figure(26))
                    .contentTransition(.numericText())
                Text(scopeCaption)
                    .font(Theme.heading(12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if model.bytesSelectedOutsideScope > 0 {
                Button {
                    model.requestClean(.everythingSelected)
                } label: {
                    Text("Clean all \(model.selectedBytes.byteLabel)")
                        .font(Theme.heading(13, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .help("Includes locations you selected on other pages")
            }

            Picker("", selection: $model.mode) {
                ForEach(DeletionMode.allCases) { mode in
                    Text(mode.shortTitle).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 168)
            .help(model.mode.explanation)

            Button {
                model.requestClean(.currentPage)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                    Text(model.scopedBytes > 0 ? "Clean \(model.scopedBytes.byteLabel)" : "Clean")
                        .font(Theme.heading(16, weight: .semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.extraLarge)
            .tint(model.mode == .permanent ? Theme.danger : Theme.accent)
            .disabled(model.scopedBuckets.isEmpty)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    private var scopeCaption: String {
        if let category = model.scopeCategory {
            return "\(model.scopedBuckets.count) of \(model.scopedCleanableCount) in \(category.title) selected"
        }
        return "\(model.selectedBuckets.count) of \(model.cleanable.count) locations selected"
    }
}
