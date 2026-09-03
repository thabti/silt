import AppKit
import Foundation
import SwiftUI

/// Everything the views read, pre-computed once per change.
///
/// The category cards used to call `bytes(in:)` and `buckets(in:)` inside their own bodies,
/// which walked all 123 buckets several times per render. Now the totals are built once,
/// when the data actually changes.
struct ScanIndex {
    var cleanable: [ScannedTarget] = []
    var reviewOnly: [ScannedTarget] = []
    var byCategory: [CleanCategory: [ScannedTarget]] = [:]
    var bytesByCategory: [CleanCategory: Int64] = [:]
    var categoriesWithContent: [CleanCategory] = []
    var junkBytes: Int64 = 0
    var reviewBytes: Int64 = 0
    var trash: ScannedTarget?

    static func build(from scanned: [ScannedTarget]) -> ScanIndex {
        var index = ScanIndex()
        index.byCategory = Dictionary(grouping: scanned.filter { $0.bytes > 0 }, by: { $0.target.category })

        for (category, buckets) in index.byCategory {
            index.bytesByCategory[category] = buckets.reduce(0) { $0 + $1.bytes }
        }
        index.categoriesWithContent = CleanCategory.allCases.filter { (index.bytesByCategory[$0] ?? 0) > 0 }

        index.cleanable = scanned.filter { $0.target.kind.isDeletable && $0.bytes > 0 }
        index.reviewOnly = scanned.filter { !$0.target.kind.isDeletable && $0.bytes > 0 }
        index.junkBytes = index.cleanable.reduce(0) { $0 + $1.bytes }
        index.reviewBytes = index.reviewOnly.reduce(0) { $0 + $1.bytes }
        index.trash = scanned.first { $0.id == Catalog.trashID }
        return index
    }
}

@MainActor
final class AppModel: ObservableObject {

    enum Phase: Equatable {
        case idle
        case scanning
        case ready
        case cleaning
        case finished
    }

    enum Route: Hashable, Identifiable {
        case overview
        case category(CleanCategory)
        case files
        case artifacts
        case leftovers
        case installedApps

        var id: String {
            switch self {
            case .overview: "overview"
            case .category(let c): c.rawValue
            case .files: "files"
            case .artifacts: "artifacts"
            case .leftovers: "leftovers"
            case .installedApps: "installedApps"
            }
        }

        /// Pages driven by the catalog scan, where the Clean toolbar actions belong.
        /// Everything else (Large files, Build artifacts, App leftovers, Applications)
        /// owns its own action, so new pages default to *not* inheriting cache actions.
        var isCachePage: Bool {
            switch self {
            case .overview, .category: true
            case .files, .artifacts, .leftovers, .installedApps: false
            }
        }

        var title: String {
            switch self {
            case .overview: "Overview"
            case .category(let c): c.title
            case .files: "Large files"
            case .artifacts: "Build artifacts"
            case .leftovers: "App leftovers"
            case .installedApps: "Applications"
            }
        }
    }

    // MARK: - Cache state

    @Published var phase: Phase = .idle
    @Published var disk: DiskSnapshot = .empty
    @Published private(set) var scanned: [ScannedTarget] = []
    @Published private(set) var index = ScanIndex()
    @Published private(set) var isScanning = false
    @Published var selection: Set<String> = []
    @Published var scanProgress = ScanProgress(completed: 0, total: 0, currentName: "")
    @Published var cleanProgress = CleanProgress(completed: 0, total: 0, currentName: "")
    @Published var report: CleanReport?
    @Published var mode: DeletionMode = .trash
    @Published var route: Route = .overview
    @Published var showConfirmation = false
    @Published var lastScan: Date?

    /// The exact job the confirmation sheet is about, so what is listed there is
    /// always what gets cleaned — never a wider selection made on another page.
    @Published var pending: [ScannedTarget] = []
    @Published var pendingScope: String = ""

    /// Review-only folders are measured separately and on demand — see `measureReview()`.
    enum ReviewState: Equatable {
        case notMeasured
        case measuring
        case measured
    }

    @Published private(set) var reviewState: ReviewState = .notMeasured
    @Published var reviewProgress = ScanProgress(completed: 0, total: 0, currentName: "")

    private var scanTask: Task<Void, Never>?
    /// Bumped per scan so late results from a cancelled run can be discarded.
    private var scanGeneration = 0
    /// id → position in `scanned`, so merging a streamed bucket is a lookup, not a search.
    private var bucketIndexByID: [String: Int] = [:]
    /// True once the user has touched the selection, which stops a rescan overwriting it.
    private var hasChosenSelection = false
    private var reviewTask: Task<Void, Never>?
    private var reviewGeneration = 0
    private var lastCleanedIDs: Set<String> = []
    private var catalogLoadTask: Task<[CleanTarget], Never>?
    private var presentTargets: [CleanTarget] = []

    init() {
        disk = DiskSpace.snapshot()
        startCatalogLoad()
    }

    // MARK: - Derived numbers (all reads hit the pre-built index)

    var cleanable: [ScannedTarget] { index.cleanable }
    var reviewOnly: [ScannedTarget] { index.reviewOnly }
    var junkBytes: Int64 { index.junkBytes }
    var reviewBytes: Int64 { index.reviewBytes }
    var categoriesWithContent: [CleanCategory] { index.categoriesWithContent }

    func buckets(in category: CleanCategory) -> [ScannedTarget] {
        (index.byCategory[category] ?? []).sorted { $0.bytes > $1.bytes }
    }

    func bytes(in category: CleanCategory) -> Int64 { index.bytesByCategory[category] ?? 0 }

    func selectedBytes(in category: CleanCategory) -> Int64 {
        (index.byCategory[category] ?? [])
            .filter { selection.contains($0.id) && $0.target.kind.isDeletable }
            .reduce(0) { $0 + $1.bytes }
    }

    var selectedBuckets: [ScannedTarget] { index.cleanable.filter { selection.contains($0.id) } }
    var selectedBytes: Int64 { selectedBuckets.reduce(0) { $0 + $1.bytes } }

    /// Share of the whole disk that is reclaimable junk — used to size the ring segment.
    var junkFraction: Double {
        disk.total > 0 ? Double(junkBytes) / Double(disk.total) : 0
    }

    /// The category currently on screen, or nil on the overview and the files page.
    var scopeCategory: CleanCategory? {
        if case let .category(category) = route { return category }
        return nil
    }

    /// Cleaning follows the page you are on: on a category page only that category's
    /// selection is in play, on the overview everything selected is.
    var scopedBuckets: [ScannedTarget] {
        guard let category = scopeCategory else { return selectedBuckets }
        return selectedBuckets.filter { $0.target.category == category }
    }

    var scopedBytes: Int64 { scopedBuckets.reduce(0) { $0 + $1.bytes } }

    var scopedCleanableCount: Int {
        guard let category = scopeCategory else { return cleanable.count }
        return cleanable.filter { $0.target.category == category }.count
    }

    var bytesSelectedOutsideScope: Int64 { selectedBytes - scopedBytes }

    var pendingBytes: Int64 { pending.reduce(0) { $0 + $1.bytes } }

    /// Trash stays visible on the overview even when its measured size is zero.
    var trashBucket: ScannedTarget? {
        index.trash
    }

    /// True only on a cold start, when there is genuinely nothing to show yet.
    var hasResults: Bool { !scanned.isEmpty }

    // MARK: - Selection

    func isSelected(_ bucket: ScannedTarget) -> Bool { selection.contains(bucket.id) }

    func toggle(_ bucket: ScannedTarget) {
        guard bucket.target.kind.isDeletable else { return }
        hasChosenSelection = true
        if selection.contains(bucket.id) {
            selection.remove(bucket.id)
        } else {
            selection.insert(bucket.id)
        }
    }

    func setSelection(_ on: Bool, in category: CleanCategory) {
        hasChosenSelection = true
        for bucket in buckets(in: category) where bucket.target.kind.isDeletable {
            if on { selection.insert(bucket.id) } else { selection.remove(bucket.id) }
        }
    }

    /// Explicit user action, so a later rescan must not overwrite it.
    func chooseRecommended() {
        hasChosenSelection = true
        selectRecommended()
    }

    func clearSelection() {
        hasChosenSelection = true
        selection.removeAll()
    }

    func selectRecommended() {
        // Recommended = the buckets nothing has to re-download. Anything that costs
        // a re-download, and the Trash, stays off until the person opts in.
        selection = Set(cleanable.filter { $0.target.kind == .safe }.map(\.id))
    }

    func selectEverythingCleanable() {
        hasChosenSelection = true
        selection = Set(cleanable.map(\.id))
    }

    // MARK: - Scanning

    /// - Parameter only: when given, just those buckets are re-measured and merged into the
    ///   results already on screen. Used after a clean, where re-walking all 123 locations
    ///   to learn that 10 of them are now empty is pure waste.
    func scan(only ids: Set<String>? = nil) {
        scanTask?.cancel()
        scanGeneration &+= 1
        let generation = scanGeneration

        let isPartial = ids != nil && hasResults
        isScanning = true
        report = nil

        if !isPartial {
            // Full scan: keep whatever is on screen until the first fresh bucket arrives,
            // so the sidebar and the overview never blink out of existence.
            phase = hasResults ? .ready : .scanning
        }

        disk = DiskSpace.snapshot()

        scanTask = Task { [weak self] in
            guard let self else { return }
            let targets = await self.loadPresentTargets(refresh: ids == nil && self.lastScan != nil)
            let filtered: [CleanTarget] = {
                guard let ids else { return Scanner.quickTargets(targets) }
                return targets.filter { ids.contains($0.id) }
            }()

            guard !Task.isCancelled else { return }

            await MainActor.run {
                // Results stay on screen and are replaced bucket by bucket as fresh ones
                // arrive. Wiping them here emptied the sidebar and dropped the detail pane
                // onto "Nothing to clean" for the whole scan.
                self.scanProgress = ScanProgress(completed: 0, total: filtered.count, currentName: "")
            }

            let collected = Collected()
            await Scanner.stream(targets: filtered) { bucket in
                collected.add(bucket.id)
                Task { @MainActor [weak self] in
                    self?.merge(bucket, generation: generation)
                }
            }
            let returnedIDs = collected.ids

            guard !Task.isCancelled else { return }

            await MainActor.run {
                self.finishScan(fullScan: !isPartial, measured: returnedIDs, generation: generation)
            }
        }
    }

    private func merge(_ bucket: ScannedTarget, generation: Int) {
        // A cancelled scan's in-flight jobs still finish. Without this check they land
        // after the next scan has started, reviving stale buckets and pushing the
        // progress bar past 100%.
        guard generation == scanGeneration else { return }

        if let existing = bucketIndexByID[bucket.id] {
            scanned[existing] = bucket
        } else {
            bucketIndexByID[bucket.id] = scanned.count
            scanned.append(bucket)
        }
        index = ScanIndex.build(from: scanned)

        scanProgress.completed += 1
        scanProgress.currentName = bucket.target.name

        // Results stream in, so switch away from the cold-start panel as soon as
        // there is something real to look at.
        if phase == .scanning, bucket.bytes > 0 {
            phase = .ready
        }
    }

    private func replaceAll(with buckets: [ScannedTarget]) {
        scanned = buckets
        reindexBuckets()
        index = ScanIndex.build(from: buckets)
    }

    private func reindexBuckets() {
        bucketIndexByID = Dictionary(scanned.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func finishScan(fullScan: Bool, measured: [String] = [], generation: Int) {
        // A clean that started while this scan was running owns the phase; never stomp it.
        guard phase != .cleaning, phase != .finished else {
            isScanning = false
            return
        }
        // An older scan can clear its cancellation check, suspend, and resume after a new
        // scan has started. Without this it would flip isScanning off and re-sort
        // half-refreshed state under the newer run.
        guard generation == scanGeneration else { return }
        // Drop quick buckets that were on screen before this scan but which the scan did
        // not return — they no longer exist on disk. `returned` has to come from the scan
        // itself; deriving it from `scanned` compared the array against itself and never
        // removed anything. Review buckets are outside a quick scan's remit and survive.
        if fullScan {
            let returned = Set(measured)
            scanned.removeAll { $0.target.kind != .review && !returned.contains($0.id) }
        }
        scanned.sort { $0.bytes > $1.bytes }
        reindexBuckets()
        index = ScanIndex.build(from: scanned)
        isScanning = false
        lastScan = Date()
        disk = DiskSpace.snapshot()
        phase = .ready

        if fullScan, !hasChosenSelection {
            // Only preseed on the first scan of a session. Re-running a scan must not
            // silently discard a selection someone spent time curating.
            selectRecommended()
        } else {
            // A partial rescan can empty a bucket. Drop those from the selection instead
            // of leaving a tick on something that no longer holds anything.
            let live = Set(cleanable.map(\.id))
            selection = selection.intersection(live)
        }
    }

    /// Measures the review-only folders. Slow by nature — these are the biggest trees on
    /// the disk — so it runs on request, streams each result as it lands, and is remembered
    /// for the rest of the session.
    func measureReview(force: Bool = false) {
        if reviewState == .measuring { return }
        if reviewState == .measured, !force { return }

        reviewTask?.cancel()
        reviewGeneration &+= 1
        let reviewRun = reviewGeneration
        reviewState = .measuring

        reviewTask = Task { [weak self] in
            guard let self else { return }
            let targets = Scanner.reviewTargets(await self.loadPresentTargets())

            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.reviewProgress = ScanProgress(completed: 0, total: targets.count, currentName: "")
            }

            await Scanner.stream(targets: targets) { bucket in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.mergeReview(bucket, generation: reviewRun)
                }
            }

            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard reviewRun == self.reviewGeneration else { return }
                self.reviewState = .measured
                self.scanned.sort { $0.bytes > $1.bytes }
                self.reindexBuckets()
                self.index = ScanIndex.build(from: self.scanned)
            }
        }
    }

    func cancelReviewMeasure() {
        reviewTask?.cancel()
        reviewTask = nil
        // A cancelled walk returns a truncated size. Bump the generation so in-flight
        // results are dropped rather than stored as final.
        reviewGeneration &+= 1
        reviewState = .notMeasured
    }

    private func mergeReview(_ bucket: ScannedTarget, generation: Int) {
        guard generation == reviewGeneration else { return }
        if let existing = bucketIndexByID[bucket.id] {
            scanned[existing] = bucket
        } else {
            bucketIndexByID[bucket.id] = scanned.count
            scanned.append(bucket)
        }
        index = ScanIndex.build(from: scanned)
        reviewProgress.completed += 1
        reviewProgress.currentName = bucket.target.name
    }

    /// Review folders present on this Mac, so the sidebar row exists before anything is measured.
    @Published private(set) var hasReviewTargets = false

    private func startCatalogLoad() {
        catalogLoadTask = Task.detached { Catalog.present() }
    }

    private func loadPresentTargets(refresh: Bool = false) async -> [CleanTarget] {
        if refresh {
            catalogLoadTask?.cancel()
            presentTargets = []
            startCatalogLoad()
        }
        if !presentTargets.isEmpty { return presentTargets }
        if catalogLoadTask == nil { startCatalogLoad() }
        let targets = await catalogLoadTask?.value ?? []
        presentTargets = targets
        hasReviewTargets = !Scanner.reviewTargets(targets).isEmpty
        return targets
    }

    /// Rescans whatever the current page shows. The toolbar button used to always
    /// rescan the cache catalog, so on four of five pages it appeared to do nothing.
    func rescanCurrentPage() {
        switch route {
        case .category(.review): measureReview(force: true)
        case .overview, .category: scan()
        case .files: scanFiles()
        case .artifacts: scanArtifacts()
        case .leftovers: scanLeftovers()
        case .installedApps: scanInstalledApps()
        }
    }

    /// Whether the current page has a scan running, for the toolbar's stop/refresh state.
    var isCurrentPageScanning: Bool {
        switch route {
        case .category(.review): reviewState == .measuring
        case .overview, .category: isScanning
        case .files: filesPhase == .scanning
        case .artifacts: artifactsPhase == .scanning
        case .leftovers: leftoversPhase == .scanning
        case .installedApps: appsPhase == .scanning
        }
    }

    func cancelCurrentPageScan() {
        switch route {
        case .category(.review): cancelReviewMeasure()
        case .overview, .category: cancelScan()
        case .files: cancelFileScan()
        case .artifacts: cancelArtifactScan()
        case .leftovers: cancelLeftoverScan()
        case .installedApps: cancelInstalledAppsScan()
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        // Enqueued merge callbacks would otherwise still match the current generation.
        scanGeneration &+= 1
        isScanning = false
        phase = hasResults ? .ready : .idle
    }

    // MARK: - Cleaning

    enum CleanScope {
        case currentPage
        case everythingSelected
    }

    func requestClean(_ scope: CleanScope = .currentPage) {
        // Sizes are still moving while a scan runs, and a clean started now would have
        // its phase overwritten when the scan lands.
        guard !isScanning else { return }
        let buckets: [ScannedTarget]
        switch scope {
        case .currentPage:
            buckets = scopedBuckets
            pendingScope = scopeCategory?.title ?? "Everything selected"
        case .everythingSelected:
            buckets = selectedBuckets
            pendingScope = "Everything selected"
        }
        guard !buckets.isEmpty else { return }
        pending = buckets
        showConfirmation = true
    }

    /// Starts the normal confirmation flow with Trash as the entire job.
    func requestEmptyTrash() {
        guard let trashBucket, !trashBucket.isEmpty else { return }
        pending = [trashBucket]
        pendingScope = "Trash"
        showConfirmation = true
    }

    func confirmClean() {
        // A scan landing mid-clean would overwrite the phase and could swallow the report.
        // requestClean guards this, but confirmClean is reachable on its own.
        if isScanning { cancelScan() }
        let buckets = pending
        guard !buckets.isEmpty else { return }
        showConfirmation = false
        phase = .cleaning
        cleanProgress = CleanProgress(completed: 0, total: buckets.count, currentName: "")

        Task { [weak self] in
            guard let self else { return }
            let chosenMode = self.mode
            let result = await Cleaner.clean(buckets, mode: chosenMode) { progress in
                Task { @MainActor [weak self] in
                    self?.cleanProgress = progress
                }
            }
            await MainActor.run {
                self.report = result
                self.lastCleanedIDs = Set(buckets.map(\.id))
                self.pending = []
                self.disk = DiskSpace.snapshot()
                self.phase = .finished
            }
        }
    }

    /// Only the buckets that were just cleaned need re-measuring.
    func dismissReport() {
        report = nil
        phase = .ready
        let touched = lastCleanedIDs
        lastCleanedIDs = []
        if touched.isEmpty {
            scan()
        } else {
            scan(only: touched)
        }
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
    }

    // MARK: - Large files


    struct FileThreshold: Identifiable, Hashable {
        let bytes: Int64
        var id: Int64 { bytes }
        var title: String { "over \(bytes.byteLabel)" }
    }

    static let fileThresholds: [FileThreshold] = [
        FileThreshold(bytes: 20 * 1_000_000),
        FileThreshold(bytes: 50 * 1_000_000),
        FileThreshold(bytes: 100 * 1_000_000),
        FileThreshold(bytes: 500 * 1_000_000),
        FileThreshold(bytes: 1_000_000_000),
    ]

    @Published var filesPhase: ScanPhase = .idle
    @Published private(set) var files: [FileEntry] = []
    @Published var fileSelection: Set<String> = []
    @Published var fileProgress = FileScanProgress(visited: 0, found: 0, currentFolder: "")
    @Published var fileThreshold: Int64 = 100 * 1_000_000
    @Published var kindFilter: FileKind?
    @Published var fileNotice: String?
    @Published private(set) var fileKindTotals: [FileKindTotal] = []

    struct FileKindTotal: Identifiable, Hashable {
        let kind: FileKind
        let bytes: Int64
        let count: Int
        var id: String { kind.rawValue }
    }

    private var fileTask: Task<Void, Never>?
    private var fileNoticeTask: Task<Void, Never>?

    var filteredFiles: [FileEntry] {
        guard let kindFilter else { return files }
        return files.filter { $0.kind == kindFilter }
    }

    var listedFileBytes: Int64 { filteredFiles.reduce(0) { $0 + $1.bytes } }
    var totalFileBytes: Int64 { files.reduce(0) { $0 + $1.bytes } }

    var selectedFiles: [FileEntry] { files.filter { fileSelection.contains($0.id) } }
    var selectedFileBytes: Int64 { selectedFiles.reduce(0) { $0 + $1.bytes } }

    func isSelected(_ entry: FileEntry) -> Bool { fileSelection.contains(entry.id) }

    func toggle(_ entry: FileEntry) {
        if fileSelection.contains(entry.id) {
            fileSelection.remove(entry.id)
        } else {
            fileSelection.insert(entry.id)
        }
    }

    func scanFiles() {
        fileTask?.cancel()
        filesPhase = .scanning
        fileSelection = []
        clearFileNotice()
        fileProgress = FileScanProgress(visited: 0, found: 0, currentFolder: "")

        let minimum = fileThreshold
        fileTask = Task { [weak self] in
            let found = await FileScanner.scan(minimumBytes: minimum, limit: 500) { visited, discovered, folder in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    // One assignment, not three: each published write rebuilt RootView.
                    self.fileProgress = FileScanProgress(
                        visited: self.fileProgress.visited + visited,
                        found: self.fileProgress.found + discovered,
                        currentFolder: folder.isEmpty ? self.fileProgress.currentFolder : folder)
                }
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.setFiles(found)
                self?.filesPhase = .ready
            }
        }
    }

    func cancelFileScan() {
        fileTask?.cancel()
        fileTask = nil
        filesPhase = files.isEmpty ? .idle : .ready
    }

    private func setFiles(_ entries: [FileEntry]) {
        files = entries
        fileKindTotals = Dictionary(grouping: entries, by: { $0.kind })
            .map { FileKindTotal(kind: $0.key, bytes: $0.value.reduce(0) { $0 + $1.bytes }, count: $0.value.count) }
            .sorted { $0.bytes > $1.bytes }
        if let filter = kindFilter, !entries.contains(where: { $0.kind == filter }) {
            kindFilter = nil
        }
    }

    /// The exact file job the confirmation sheet is about — captured at request time,
    /// like `pending` for cache buckets.
    @Published var pendingFiles: [FileEntry] = []
    @Published var showFilesConfirmation = false

    var pendingFileBytes: Int64 { pendingFiles.reduce(0) { $0 + $1.bytes } }

    func requestCleanFiles() {
        guard !selectedFiles.isEmpty else { return }
        pendingFiles = selectedFiles
        showFilesConfirmation = true
    }

    /// Runs the captured file job in the current mode. Every path is re-checked by the
    /// guard immediately before removal, whichever mode is active.
    func confirmCleanFiles() {
        let chosen = pendingFiles
        pendingFiles = []
        showFilesConfirmation = false
        guard !chosen.isEmpty else { return }

        let permanent = mode == .permanent
        let tally = Removal.run(chosen.map { entry in
            RemovalUnit(url: entry.url, bytes: entry.bytes, label: entry.name,
                        verdict: { SafetyGuard.verdictForUserFile(entry.url, isBundle: entry.isBundle) },
                        remove: {
                            if permanent {
                                try FileManager.default.removeItem(at: entry.url)
                            } else {
                                try FileManager.default.trashItem(at: entry.url, resultingItemURL: nil)
                            }
                            return false
                        })
        })

        let fm = FileManager.default
        setFiles(files.filter { fm.fileExists(atPath: $0.url.path) })
        fileSelection = []
        disk = DiskSpace.snapshot()
        setFileNotice(tally.notice(verb: permanent ? "Deleted" : "Moved",
                                   noun: "item",
                                   toTrash: !permanent),
                      hasFailures: !tally.refused.isEmpty)
    }

    // MARK: - Build artifacts


    @Published var artifactsPhase: ScanPhase = .idle
    @Published private(set) var artifacts: [ProjectArtifact] = []
    @Published var artifactSelection: Set<String> = []
    @Published var artifactProgress = ArtifactScanProgress(visited: 0, found: 0, currentFolder: "")
    @Published var artifactNotice: String?
    @Published private(set) var lastArtifactScan: Date?
    private var artifactTask: Task<Void, Never>?
    private var artifactIndexByID: [String: Int] = [:]
    private var artifactGeneration = 0
    private var artifactNoticeTask: Task<Void, Never>?
    private var leftoverNoticeTask: Task<Void, Never>?
    private var applicationsNoticeTask: Task<Void, Never>?

    @Published var leftoversPhase: ScanPhase = .idle
    @Published private(set) var leftovers: [AppLeftoverGroup] = []
    @Published var leftoverSelection: Set<String> = []
    @Published var leftoverProgress = ArtifactScanProgress(visited: 0, found: 0, currentFolder: "")
    /// Text plus whether the run reported failures. Inferring severity by searching the
    /// sentence for "left alone" coupled presentation to exact English wording.
    struct PageNoticeState: Equatable {
        let text: String
        let hasFailures: Bool
    }

    @Published var leftoverNoticeState: PageNoticeState?
    var leftoverNotice: String? { leftoverNoticeState?.text }
    @Published private(set) var lastLeftoverScan: Date?
    private var leftoverTask: Task<Void, Never>?

    struct PendingAppUninstall: Identifiable, Sendable {
        let app: InstalledApp
        let supportFiles: [AppLeftoverItem]
        var id: String { app.id }
        var bytes: Int64 { app.bytes + supportFiles.reduce(0) { $0 + $1.bytes } }
    }
    @Published var appsPhase: ScanPhase = .idle
    @Published private(set) var installedApps: [InstalledApp] = []
    @Published var installedAppSelection: Set<String> = []
    @Published var pendingAppUninstalls: [PendingAppUninstall] = []
    @Published var showAppsConfirmation = false
    @Published var applicationsNotice: String?
    /// True when a bundle could not be moved — almost always App Management not granted.
    @Published var applicationsNeedsPermission = false
    private var installedAppsTask: Task<Void, Never>?

    var selectedInstalledApps: [InstalledApp] { installedApps.filter { $0.isRemovable && installedAppSelection.contains($0.id) } }
    var selectedInstalledAppBytes: Int64 { selectedInstalledApps.reduce(0) { $0 + $1.bytes } }
    var totalInstalledAppBytes: Int64 { installedApps.reduce(0) { $0 + $1.bytes } }

    func scanInstalledAppsIfNeeded() { if appsPhase == .idle { scanInstalledApps() } }
    func scanInstalledApps() {
        installedAppsTask?.cancel(); appsPhase = .scanning; applicationsNotice = nil; installedApps = []
        installedAppsTask = Task { [weak self] in
            let result = await InstalledApps.inventory { app in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if !self.installedApps.contains(where: { $0.id == app.id }) { self.installedApps.append(app) }
                    self.installedApps.sort { $0.bytes > $1.bytes }
                }
            }
            guard !Task.isCancelled else { return }
            self?.installedApps = result; self?.appsPhase = .ready
        }
    }
    func cancelInstalledAppsScan() { installedAppsTask?.cancel(); installedAppsTask = nil; appsPhase = installedApps.isEmpty ? .idle : .ready }
    func toggle(_ app: InstalledApp) {
        guard app.isRemovable else { return }
        if installedAppSelection.contains(app.id) { installedAppSelection.remove(app.id) } else { installedAppSelection.insert(app.id) }
    }
    @Published private(set) var isPreparingUninstall = false
    private var uninstallPrepGeneration = 0

    func requestUninstallApps() {
        let chosen = selectedInstalledApps
        guard !chosen.isEmpty, !isPreparingUninstall else { return }
        uninstallPrepGeneration &+= 1
        let prepGeneration = uninstallPrepGeneration
        isPreparingUninstall = true
        // Collecting each app's support files walks eleven Library locations and sizes
        // every match. Doing that inline froze the window before the sheet appeared.
        Task { [weak self] in
            let jobs = await Task.detached(priority: .userInitiated) {
                chosen.map { app in
                    PendingAppUninstall(app: app,
                                        supportFiles: LeftoverScanner.items(forBundleID: app.bundleID, appName: app.name))
                }
            }.value
            await MainActor.run {
                guard let self else { return }
                // Only the newest request may open the sheet; an older walk finishing
                // late must not replace it or reopen a cancelled sheet.
                guard prepGeneration == self.uninstallPrepGeneration else { return }
                self.isPreparingUninstall = false
                guard !jobs.isEmpty else { return }
                self.pendingAppUninstalls = jobs
                self.showAppsConfirmation = true
            }
        }
    }
    /// macOS 13+ gates moving anything out of /Applications behind App Management. The
    /// error code varies by failure mode and none of them mention the setting, so treat a
    /// failed bundle move as a permission problem and say where to fix it.
    static func uninstallFailureHint(_ error: Error) -> String {
        let code = (error as NSError).code
        let permissionDenied = code == NSFileWriteNoPermissionError
            || code == NSFileReadNoPermissionError
            || code == NSFileWriteUnknownError
            || code == NSFileNoSuchFileError
        guard permissionDenied else { return error.localizedDescription }
        return "blocked by macOS — grant App Management"
    }

    /// Opens System Settings straight at Privacy & Security › App Management.
    func openAppManagementSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles") else { return }
        NSWorkspace.shared.open(url)
    }

    func confirmUninstallApps() {
        let jobs = pendingAppUninstalls
        guard !jobs.isEmpty, runningSelectedBundleIDs().isEmpty else { return }
        pendingAppUninstalls = []
        showAppsConfirmation = false
        applicationsNeedsPermission = false

        // One tally across both levels so refusals stay in per-job order: the app's own
        // refusal, then that app's support files, then the next app.
        var tally = RemovalTally()
        var appsMoved = 0
        var filesMoved = 0

        for job in jobs {
            // Only the app bundle may use the Finder fallback. Support files live in
            // ~/Library and are never App-Management protected, so involving Finder for
            // them would trigger an automation prompt for nothing.
            let bundle = Removal.run(
                [RemovalUnit(url: job.app.url, bytes: job.app.bytes, label: job.app.name,
                             verdict: { SafetyGuard.verdictForApplicationBundle(job.app.url, bundleID: job.app.bundleID) },
                             remove: { try TrashService.trash(job.app.url) == .finder })],
                describeFailure: Self.uninstallFailureHint,
                onFailure: { [weak self] _ in self?.applicationsNeedsPermission = true }
            )
            tally.merge(bundle)

            // If the bundle did not move, its Library data must stay with it.
            guard bundle.removed == 1 else { continue }
            appsMoved += 1

            let support = Removal.run(job.supportFiles.map { file in
                RemovalUnit(url: file.url, bytes: file.bytes, label: job.app.name,
                            verdict: {
                                SafetyGuard.verdictForAppLeftover(file.url,
                                                                  matchedOrphanID: job.app.bundleID,
                                                                  verifyInstalled: false)
                            },
                            remove: {
                                try FileManager.default.trashItem(at: file.url, resultingItemURL: nil)
                                return false
                            })
            })
            tally.merge(support)
            filesMoved += support.removed
        }

        let fm = FileManager.default
        installedApps.removeAll { !fm.fileExists(atPath: $0.url.path) }
        installedAppSelection.formIntersection(Set(installedApps.map(\.id)))
        disk = DiskSpace.snapshot()

        // One app refusing eleven support files for the same reason collapses to one line.
        // Done once at the end so the visible cap counts distinct reasons.
        tally.dedupeRefusals()

        // This page counts two kinds of thing, so it writes its own headline rather than
        // using the shared template.
        let headline = appsMoved == 0
            ? "Nothing was uninstalled."
            : "Uninstalled \(appsMoved) \(appsMoved == 1 ? "app" : "apps") and \(filesMoved) support "
              + "\(filesMoved == 1 ? "file" : "files") — \(tally.freed.byteLabel) moved to the Trash."
              + (tally.viaFallback > 0 ? " Finder handled \(tally.viaFallback) of them." : "")
        setApplicationsNotice(headline + tally.refusalSuffix(max: 3),
                              hasFailures: !tally.refused.isEmpty)

        if !leftovers.isEmpty { scanLeftovers() }
    }
    /// One pending app that is still running, with whatever we last asked of it.
    struct RunningPendingApp: Identifiable, Equatable {
        let app: InstalledApp
        var asked: Bool          // a graceful quit has been requested
        var refused: Bool        // it ignored the request long enough to offer force quit
        var id: String { app.id }
    }

    /// Bundle ids we have asked to quit, and when — so a quit that is merely slow reads as
    /// "Quitting…" rather than as a dead button.
    private var quitRequests: [String: Date] = [:]

    /// Case-insensitive: Info.plist casing and the running process's casing can differ.
    private func runningApplications(matching ids: Set<String>) -> [NSRunningApplication] {
        let wanted = Set(ids.map { $0.lowercased() })
        return NSWorkspace.shared.runningApplications.filter {
            guard let id = $0.bundleIdentifier?.lowercased() else { return false }
            return wanted.contains(id)
        }
    }

    func runningSelectedBundleIDs() -> Set<String> {
        let ids = Set(pendingAppUninstalls.map { $0.app.bundleID })
        return Set(runningApplications(matching: ids).compactMap { $0.bundleIdentifier })
    }

    /// The pending apps still running, in a form the sheet can render per app.
    func runningPendingApps() -> [RunningPendingApp] {
        let stillRunning = Set(runningSelectedBundleIDs().map { $0.lowercased() })
        return pendingAppUninstalls
            .filter { stillRunning.contains($0.app.bundleID.lowercased()) }
            .map { job in
                let requested = quitRequests[job.app.bundleID.lowercased()]
                // Give an app a few seconds to put its affairs in order before suggesting force.
                let refused = requested.map { Date().timeIntervalSince($0) > 4 } ?? false
                return RunningPendingApp(app: job.app, asked: requested != nil, refused: refused)
            }
    }

    /// Ask one app to quit. `force` sends SIGKILL-equivalent termination, which loses
    /// unsaved work — only ever offered after a graceful request has been ignored.
    func quit(_ bundleID: String, force: Bool = false) {
        let matches = runningApplications(matching: [bundleID])
        guard !matches.isEmpty else { return }
        quitRequests[bundleID.lowercased()] = force ? Date.distantPast : Date()
        for application in matches {
            _ = force ? application.forceTerminate() : application.terminate()
        }
    }

    func quitPendingApps(force: Bool = false) {
        for entry in runningPendingApps() {
            quit(entry.app.bundleID, force: force)
        }
    }

    func clearQuitRequests() { quitRequests.removeAll() }

    var selectedArtifacts: [ProjectArtifact] { artifacts.filter { artifactSelection.contains($0.id) } }
    var selectedArtifactBytes: Int64 { selectedArtifacts.reduce(0) { $0 + $1.bytes } }
    var totalArtifactBytes: Int64 { artifacts.reduce(0) { $0 + $1.bytes } }
    var selectedLeftovers: [AppLeftoverGroup] { leftovers.filter { $0.isDeletable && leftoverSelection.contains($0.id) } }
    var selectedLeftoverBytes: Int64 { selectedLeftovers.reduce(0) { $0 + $1.bytes } }
    var totalLeftoverBytes: Int64 { leftovers.reduce(0) { $0 + $1.bytes } }

    /// What Silt could genuinely reclaim right now, across every page that has been
    /// scanned: cache junk, regenerable build artifacts, and data from apps that are gone.
    /// Large files and installed apps are deliberately excluded — those are your own
    /// things, a choice rather than junk, and counting them would overstate the number.
    var reclaimableTotal: Int64 {
        // Leftovers under ~/Library/Logs are already inside the `system.logs` catalog
        // bucket; counting both inflates the headline and offers the same bytes twice.
        let logsPrefix = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs").standardizedFileURL.path
        let doubleCounted = leftovers
            .flatMap(\.items)
            .filter { $0.url.standardizedFileURL.path.hasPrefix(logsPrefix + "/") }
            .reduce(Int64(0)) { $0 + $1.bytes }
        return junkBytes + totalArtifactBytes + max(0, totalLeftoverBytes - doubleCounted)
    }

    func toggle(_ group: AppLeftoverGroup) {
        guard group.isDeletable else { return }
        if leftoverSelection.contains(group.id) { leftoverSelection.remove(group.id) } else { leftoverSelection.insert(group.id) }
    }

    func scanLeftoversIfNeeded() { if leftoversPhase == .idle, lastLeftoverScan == nil { scanLeftovers() } }
    func scanLeftovers() {
        leftoverTask?.cancel(); leftoversPhase = .scanning; leftoverNoticeState = nil
        leftoverProgress = ArtifactScanProgress(visited: 0, found: 0, currentFolder: "")
        leftoverTask = Task { [weak self] in
            let found = await LeftoverScanner.scan { checked, discovered, location in
                Task { @MainActor [weak self] in self?.leftoverProgress = ArtifactScanProgress(visited: checked, found: discovered, currentFolder: location) }
            } onFound: { _ in }
            guard !Task.isCancelled else { return }
            self?.leftovers = found; self?.leftoverSelection.formIntersection(Set(found.map(\.id)))
            self?.leftoversPhase = .ready; self?.lastLeftoverScan = Date()
        }
    }
    func cancelLeftoverScan() { leftoverTask?.cancel(); leftoverTask = nil; leftoversPhase = leftovers.isEmpty ? .idle : .ready }
    @Published var pendingLeftovers: [AppLeftoverGroup] = []
    @Published var showLeftoversConfirmation = false
    var pendingLeftoverBytes: Int64 { pendingLeftovers.reduce(0) { $0 + $1.bytes } }

    func requestTrashLeftovers() {
        guard !selectedLeftovers.isEmpty else { return }
        pendingLeftovers = selectedLeftovers
        showLeftoversConfirmation = true
    }

    func cancelPendingLeftovers() {
        pendingLeftovers = []
        showLeftoversConfirmation = false
    }

    func trashSelectedLeftovers() {
        let chosen = pendingLeftovers
        pendingLeftovers = []
        showLeftoversConfirmation = false
        guard !chosen.isEmpty else { return }

        // Refusals are attributed to the group, not the individual file, because the group
        // is what the user selected.
        let tally = Removal.run(chosen.flatMap { group in
            group.items.map { item in
                RemovalUnit(url: item.url, bytes: item.bytes, label: group.name,
                            verdict: { SafetyGuard.verdictForAppLeftover(item.url, matchedOrphanID: item.matchedID) },
                            remove: {
                                try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
                                return false
                            })
            }
        })

        // Groups are rebuilt rather than filtered: a group whose items all went must
        // disappear, not linger as an empty row.
        let fm = FileManager.default
        leftovers = leftovers.compactMap { group in
            let remaining = group.items.filter { fm.fileExists(atPath: $0.url.path) }
            return remaining.isEmpty ? nil : AppLeftoverGroup(id: group.id, name: group.name,
                                                              confidence: group.confidence, items: remaining)
        }
        leftoverSelection.formIntersection(Set(leftovers.map(\.id)))
        disk = DiskSpace.snapshot()
        setLeftoverNotice(tally.notice(verb: "Moved", noun: "item", toTrash: true),
                          hasFailures: !tally.refused.isEmpty)
    }

    func toggle(_ artifact: ProjectArtifact) {
        if artifactSelection.contains(artifact.id) { artifactSelection.remove(artifact.id) }
        else { artifactSelection.insert(artifact.id) }
    }

    func scanArtifacts() {
        artifactTask?.cancel()
        artifactGeneration &+= 1
        let artifactRun = artifactGeneration
        artifactsPhase = .scanning
        clearArtifactNotice()
        artifactProgress = ArtifactScanProgress(visited: 0, found: 0, currentFolder: "")

        artifactTask = Task { [weak self] in
            let found = await ArtifactScanner.scan { visited, discovered, folder in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.artifactProgress = ArtifactScanProgress(
                        visited: self.artifactProgress.visited + visited,
                        found: self.artifactProgress.found + discovered,
                        currentFolder: folder.isEmpty ? self.artifactProgress.currentFolder : folder)
                }
            } onFound: { artifact in
                Task { @MainActor [weak self] in self?.mergeArtifact(artifact, generation: artifactRun) }
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, artifactRun == self.artifactGeneration else { return }
                self.artifacts = found
                self.sortArtifacts()   // also rebuilds the index map
                self.artifactSelection.formIntersection(Set(found.map(\.id)))
                self.artifactsPhase = .ready
                self.lastArtifactScan = Date()
            }
        }
    }

    func scanArtifactsIfNeeded() {
        guard artifactsPhase == .idle, lastArtifactScan == nil else { return }
        scanArtifacts()
    }

    private func mergeArtifact(_ artifact: ProjectArtifact, generation: Int) {
        guard generation == artifactGeneration else { return }
        // Was a linear search whose comparison key normalised a URL and allocated two
        // strings, then a full re-sort, on every streamed artifact.
        if let position = artifactIndexByID[artifact.id] {
            artifacts[position] = artifact
        } else {
            artifactIndexByID[artifact.id] = artifacts.count
            artifacts.append(artifact)
        }
    }

    private func sortArtifacts() {
        artifacts.sort { $0.bytes > $1.bytes }
        reindexArtifacts()
    }

    private func reindexArtifacts() {
        artifactIndexByID = Dictionary(artifacts.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func cancelArtifactScan() {
        artifactTask?.cancel(); artifactTask = nil
        artifactGeneration &+= 1
        artifactsPhase = artifacts.isEmpty ? .idle : .ready
    }

    @Published var pendingArtifacts: [ProjectArtifact] = []
    @Published var showArtifactsConfirmation = false
    var pendingArtifactBytes: Int64 { pendingArtifacts.reduce(0) { $0 + $1.bytes } }

    func requestTrashArtifacts() {
        guard !selectedArtifacts.isEmpty else { return }
        pendingArtifacts = selectedArtifacts
        showArtifactsConfirmation = true
    }

    func cancelPendingArtifacts() {
        pendingArtifacts = []
        showArtifactsConfirmation = false
    }

    func trashSelectedArtifacts() {
        // Consume the snapshot the sheet listed. Recomputing from the live selection here
        // broke the promise that exactly what you saw is what runs.
        let chosen = pendingArtifacts
        pendingArtifacts = []
        showArtifactsConfirmation = false
        guard !chosen.isEmpty else { return }

        let tally = Removal.run(chosen.map { artifact in
            RemovalUnit(url: artifact.url, bytes: artifact.bytes, label: artifact.projectName,
                        verdict: { SafetyGuard.verdictForProjectArtifact(artifact.url) },
                        remove: {
                            try FileManager.default.trashItem(at: artifact.url, resultingItemURL: nil)
                            return false
                        })
        })

        // Derived from what actually went, rather than mutated inside the removal closure.
        let gone = Set(tally.removedURLs.map(\.standardizedFileURL))
        let affectedProjects = Set(chosen
            .filter { gone.contains($0.url.standardizedFileURL) }
            .map { $0.projectPath.standardizedFileURL })

        let fm = FileManager.default
        artifacts.removeAll { !fm.fileExists(atPath: $0.url.path) }
        reindexArtifacts()
        artifactSelection.formIntersection(Set(artifacts.map(\.id)))
        disk = DiskSpace.snapshot()
        setArtifactNotice(tally.notice(verb: "Moved", noun: "artifact", toTrash: true),
                          hasFailures: !tally.refused.isEmpty)
        refreshArtifacts(in: Array(affectedProjects))
    }

    /// Failures must not vanish. A clean run fades after 8 seconds; anything reporting
    /// items left alone stays until the next scan replaces it.
    private func scheduleNoticeClear(_ hasFailures: Bool, task: inout Task<Void, Never>?, clear: @escaping @MainActor () -> Void) {
        task?.cancel()
        guard !hasFailures else { return }
        task = Task { @MainActor in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            clear()
        }
    }

    private func clearFileNotice() {
        fileNoticeTask?.cancel()
        fileNotice = nil
    }

    private func clearArtifactNotice() {
        artifactNoticeTask?.cancel()
        artifactNotice = nil
    }

    private func setFileNotice(_ text: String, hasFailures: Bool = false) {
        fileNotice = text
        scheduleNoticeClear(hasFailures, task: &fileNoticeTask) { [weak self] in self?.fileNotice = nil }
    }

    private func setLeftoverNotice(_ text: String, hasFailures: Bool = false) {
        leftoverNoticeState = PageNoticeState(text: text, hasFailures: hasFailures)
        scheduleNoticeClear(hasFailures, task: &leftoverNoticeTask) { [weak self] in self?.leftoverNoticeState = nil }
    }

    private func setApplicationsNotice(_ text: String, hasFailures: Bool = false) {
        applicationsNotice = text
        scheduleNoticeClear(hasFailures, task: &applicationsNoticeTask) { [weak self] in self?.applicationsNotice = nil }
    }

    private func setArtifactNotice(_ text: String, hasFailures: Bool = false) {
        artifactNotice = text
        scheduleNoticeClear(hasFailures, task: &artifactNoticeTask) { [weak self] in self?.artifactNotice = nil }
    }

    private func refreshArtifacts(in projectDirectories: [URL]) {
        guard !projectDirectories.isEmpty else { return }
        artifactTask?.cancel()
        artifactGeneration &+= 1
        let refreshRun = artifactGeneration
        let scopes = Set(projectDirectories.map(\.standardizedFileURL))
        artifactTask = Task { [weak self] in
            let refreshed = await ArtifactScanner.scan(projectDirectories: Array(scopes))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                self.artifacts.removeAll { scopes.contains($0.projectPath.standardizedFileURL) }
                self.reindexArtifacts()
                guard refreshRun == self.artifactGeneration else { return }
                for artifact in refreshed { self.mergeArtifact(artifact, generation: refreshRun) }
                self.artifactSelection.formIntersection(Set(self.artifacts.map(\.id)))
                self.lastArtifactScan = Date()
            }
        }
    }
}

/// Collects ids from `Scanner.stream`'s callback, which runs off the main actor.
/// A plain captured array would be a data race.
final class Collected: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func add(_ id: String) {
        lock.lock(); storage.append(id); lock.unlock()
    }

    var ids: [String] {
        lock.lock(); defer { lock.unlock() }; return storage
    }
}
