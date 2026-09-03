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
    private var reviewTask: Task<Void, Never>?
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
        if selection.contains(bucket.id) {
            selection.remove(bucket.id)
        } else {
            selection.insert(bucket.id)
        }
    }

    func setSelection(_ on: Bool, in category: CleanCategory) {
        for bucket in buckets(in: category) where bucket.target.kind.isDeletable {
            if on { selection.insert(bucket.id) } else { selection.remove(bucket.id) }
        }
    }

    func selectRecommended() {
        // Recommended = the buckets nothing has to re-download. Anything that costs
        // a re-download, and the Trash, stays off until the person opts in.
        selection = Set(cleanable.filter { $0.target.kind == .safe }.map(\.id))
    }

    func selectEverythingCleanable() {
        selection = Set(cleanable.map(\.id))
    }

    // MARK: - Scanning

    /// - Parameter only: when given, just those buckets are re-measured and merged into the
    ///   results already on screen. Used after a clean, where re-walking all 123 locations
    ///   to learn that 10 of them are now empty is pure waste.
    func scan(only ids: Set<String>? = nil) {
        scanTask?.cancel()

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
                if !isPartial {
                    // Review sizes cost a minute to produce — never throw them away
                    // just because the cheap buckets are being re-measured.
                    self.replaceAll(with: self.scanned.filter { $0.target.kind == .review })
                }
                self.scanProgress = ScanProgress(completed: 0, total: filtered.count, currentName: "")
            }

            await Scanner.stream(targets: filtered) { bucket in
                Task { @MainActor [weak self] in
                    self?.merge(bucket)
                }
            }

            guard !Task.isCancelled else { return }

            await MainActor.run {
                self.finishScan(fullScan: !isPartial)
            }
        }
    }

    private func merge(_ bucket: ScannedTarget) {
        if let existing = scanned.firstIndex(where: { $0.id == bucket.id }) {
            scanned[existing] = bucket
        } else {
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
        index = ScanIndex.build(from: buckets)
    }

    private func finishScan(fullScan: Bool) {
        scanned.sort { $0.bytes > $1.bytes }
        index = ScanIndex.build(from: scanned)
        isScanning = false
        lastScan = Date()
        disk = DiskSpace.snapshot()
        phase = .ready

        if fullScan {
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
                    self.mergeReview(bucket)
                }
            }

            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.reviewState = .measured
                self.scanned.sort { $0.bytes > $1.bytes }
                self.index = ScanIndex.build(from: self.scanned)
            }
        }
    }

    func cancelReviewMeasure() {
        reviewTask?.cancel()
        reviewTask = nil
        reviewState = reviewOnly.isEmpty ? .notMeasured : .measured
    }

    private func mergeReview(_ bucket: ScannedTarget) {
        if let existing = scanned.firstIndex(where: { $0.id == bucket.id }) {
            scanned[existing] = bucket
        } else {
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

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        phase = hasResults ? .ready : .idle
    }

    // MARK: - Cleaning

    enum CleanScope {
        case currentPage
        case everythingSelected
    }

    func requestClean(_ scope: CleanScope = .currentPage) {
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

    enum FilesPhase: Equatable {
        case idle
        case scanning
        case ready
    }

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

    @Published var filesPhase: FilesPhase = .idle
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
        setFileNotice(nil)
        fileProgress = FileScanProgress(visited: 0, found: 0, currentFolder: "")

        let minimum = fileThreshold
        fileTask = Task { [weak self] in
            let found = await FileScanner.scan(minimumBytes: minimum, limit: 500) { visited, discovered, folder in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.fileProgress.visited += visited
                    self.fileProgress.found += discovered
                    if !folder.isEmpty { self.fileProgress.currentFolder = folder }
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

        var removed = 0
        var freed: Int64 = 0
        var refused: [String] = []

        let permanent = mode == .permanent
        for entry in chosen {
            let verdict = SafetyGuard.verdictForUserFile(entry.url, isBundle: entry.isBundle)
            guard verdict.isAllowed else {
                refused.append("\(entry.name): \(verdict.reason ?? "blocked")")
                continue
            }
            do {
                if permanent {
                    try FileManager.default.removeItem(at: entry.url)
                } else {
                    try FileManager.default.trashItem(at: entry.url, resultingItemURL: nil)
                }
                removed += 1
                freed += entry.bytes
            } catch {
                refused.append("\(entry.name): \(error.localizedDescription)")
            }
        }

        let fm = FileManager.default
        setFiles(files.filter { fm.fileExists(atPath: $0.url.path) })
        fileSelection = []
        disk = DiskSpace.snapshot()

        var notice = permanent
            ? "Deleted \(removed) \(removed == 1 ? "item" : "items") — \(freed.byteLabel)."
            : "Moved \(removed) \(removed == 1 ? "item" : "items") to the Trash — \(freed.byteLabel)."
        if !refused.isEmpty {
            notice += " \(refused.count) left alone: \(refused.prefix(2).joined(separator: "; "))"
        }
        setFileNotice(notice)
    }

    // MARK: - Build artifacts

    enum ArtifactsPhase: Equatable { case idle, scanning, ready }

    @Published var artifactsPhase: ArtifactsPhase = .idle
    @Published private(set) var artifacts: [ProjectArtifact] = []
    @Published var artifactSelection: Set<String> = []
    @Published var artifactProgress = ArtifactScanProgress(visited: 0, found: 0, currentFolder: "")
    @Published var artifactNotice: String?
    @Published private(set) var lastArtifactScan: Date?
    private var artifactTask: Task<Void, Never>?
    private var artifactNoticeTask: Task<Void, Never>?

    @Published var leftoversPhase: Phase = .idle
    @Published private(set) var leftovers: [AppLeftoverGroup] = []
    @Published var leftoverSelection: Set<String> = []
    @Published var leftoverProgress = ArtifactScanProgress(visited: 0, found: 0, currentFolder: "")
    @Published var leftoverNotice: String?
    @Published private(set) var lastLeftoverScan: Date?
    private var leftoverTask: Task<Void, Never>?

    enum AppsPhase: Equatable { case idle, scanning, ready }
    struct PendingAppUninstall: Identifiable, Sendable {
        let app: InstalledApp
        let supportFiles: [AppLeftoverItem]
        var id: String { app.id }
        var bytes: Int64 { app.bytes + supportFiles.reduce(0) { $0 + $1.bytes } }
    }
    @Published var appsPhase: AppsPhase = .idle
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
    func requestUninstallApps() {
        let selected = selectedInstalledApps
        guard !selected.isEmpty else { return }
        pendingAppUninstalls = selected.map { app in
            PendingAppUninstall(app: app, supportFiles: LeftoverScanner.items(forBundleID: app.bundleID, appName: app.name))
        }
        showAppsConfirmation = true
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
        pendingAppUninstalls = []; showAppsConfirmation = false
        applicationsNeedsPermission = false
        var appsMoved = 0, filesMoved = 0, bytes: Int64 = 0, refusals: [String] = []
        for job in jobs {
            let appVerdict = SafetyGuard.verdictForApplicationBundle(job.app.url, bundleID: job.app.bundleID)
            guard appVerdict.isAllowed else { refusals.append("\(job.app.name): \(appVerdict.reason ?? "blocked")"); continue }
            do {
                try FileManager.default.trashItem(at: job.app.url, resultingItemURL: nil)
                appsMoved += 1; bytes += job.app.bytes
            } catch {
                refusals.append("\(job.app.name): \(Self.uninstallFailureHint(error))")
                applicationsNeedsPermission = true
                continue
            }
            for file in job.supportFiles {
                let verdict = SafetyGuard.verdictForAppLeftover(file.url, matchedOrphanID: job.app.bundleID, verifyInstalled: false)
                guard verdict.isAllowed else { refusals.append("\(job.app.name): \(verdict.reason ?? "support file blocked")"); continue }
                do { try FileManager.default.trashItem(at: file.url, resultingItemURL: nil); filesMoved += 1; bytes += file.bytes }
                catch { refusals.append("\(job.app.name): \(error.localizedDescription)") }
            }
        }
        let fm = FileManager.default
        installedApps.removeAll { !fm.fileExists(atPath: $0.url.path) }
        installedAppSelection.formIntersection(Set(installedApps.map(\.id))); disk = DiskSpace.snapshot()
        applicationsNotice = (appsMoved == 0
            ? "Nothing was uninstalled."
            : "Uninstalled \(appsMoved) \(appsMoved == 1 ? "app" : "apps") and \(filesMoved) support \(filesMoved == 1 ? "file" : "files") — \(bytes.byteLabel) moved to the Trash.") +
            (refusals.isEmpty ? "" : " \(refusals.count) left alone: \(refusals.prefix(3).joined(separator: "; "))")
        if !leftovers.isEmpty { scanLeftovers() }
    }
    func runningSelectedBundleIDs() -> Set<String> {
        let ids = Set(pendingAppUninstalls.map { $0.app.bundleID })
        return Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier).filter(ids.contains))
    }
    func quitPendingApps() {
        let ids = runningSelectedBundleIDs()
        NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier.map(ids.contains) == true }.forEach { $0.terminate() }
    }

    var selectedArtifacts: [ProjectArtifact] { artifacts.filter { artifactSelection.contains($0.id) } }
    var selectedArtifactBytes: Int64 { selectedArtifacts.reduce(0) { $0 + $1.bytes } }
    var totalArtifactBytes: Int64 { artifacts.reduce(0) { $0 + $1.bytes } }
    var selectedLeftovers: [AppLeftoverGroup] { leftovers.filter { $0.isDeletable && leftoverSelection.contains($0.id) } }
    var selectedLeftoverBytes: Int64 { selectedLeftovers.reduce(0) { $0 + $1.bytes } }
    var totalLeftoverBytes: Int64 { leftovers.reduce(0) { $0 + $1.bytes } }

    func toggle(_ group: AppLeftoverGroup) {
        guard group.isDeletable else { return }
        if leftoverSelection.contains(group.id) { leftoverSelection.remove(group.id) } else { leftoverSelection.insert(group.id) }
    }

    func scanLeftoversIfNeeded() { if leftoversPhase == .idle, lastLeftoverScan == nil { scanLeftovers() } }
    func scanLeftovers() {
        leftoverTask?.cancel(); leftoversPhase = .scanning; leftoverNotice = nil
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
    func trashSelectedLeftovers() {
        let chosen = selectedLeftovers; guard !chosen.isEmpty else { return }
        var removed = 0, freed: Int64 = 0; var refused: [String] = []
        for group in chosen { for item in group.items {
            let verdict = SafetyGuard.verdictForAppLeftover(item.url, matchedOrphanID: item.matchedID)
            guard verdict.isAllowed else { refused.append("\(group.name): \(verdict.reason ?? "blocked")"); continue }
            do { try FileManager.default.trashItem(at: item.url, resultingItemURL: nil); removed += 1; freed += item.bytes }
            catch { refused.append("\(group.name): \(error.localizedDescription)") }
        }}
        leftovers = leftovers.compactMap { group in
            let remaining = group.items.filter { FileManager.default.fileExists(atPath: $0.url.path) }
            return remaining.isEmpty ? nil : AppLeftoverGroup(id: group.id, name: group.name, confidence: group.confidence, items: remaining)
        }
        leftoverSelection.formIntersection(Set(leftovers.map(\.id))); disk = DiskSpace.snapshot()
        leftoverNotice = "Moved \(removed) \(removed == 1 ? "item" : "items") to the Trash — \(freed.byteLabel)." + (refused.isEmpty ? "" : " \(refused.count) left alone: \(refused.prefix(2).joined(separator: "; "))")
    }

    func toggle(_ artifact: ProjectArtifact) {
        if artifactSelection.contains(artifact.id) { artifactSelection.remove(artifact.id) }
        else { artifactSelection.insert(artifact.id) }
    }

    func scanArtifacts() {
        artifactTask?.cancel()
        artifactsPhase = .scanning
        setArtifactNotice(nil)
        artifactProgress = ArtifactScanProgress(visited: 0, found: 0, currentFolder: "")

        artifactTask = Task { [weak self] in
            let found = await ArtifactScanner.scan { visited, discovered, folder in
                Task { @MainActor [weak self] in
                    self?.artifactProgress.visited += visited
                    self?.artifactProgress.found += discovered
                    if !folder.isEmpty { self?.artifactProgress.currentFolder = folder }
                }
            } onFound: { artifact in
                Task { @MainActor [weak self] in self?.mergeArtifact(artifact) }
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.artifacts = found
                self?.artifactSelection.formIntersection(Set(found.map(\.id)))
                self?.artifactsPhase = .ready
                self?.lastArtifactScan = Date()
            }
        }
    }

    func scanArtifactsIfNeeded() {
        guard artifactsPhase == .idle, lastArtifactScan == nil else { return }
        scanArtifacts()
    }

    private func mergeArtifact(_ artifact: ProjectArtifact) {
        if let index = artifacts.firstIndex(where: { $0.id == artifact.id }) { artifacts[index] = artifact }
        else { artifacts.append(artifact) }
        artifacts.sort { $0.bytes > $1.bytes }
    }

    func cancelArtifactScan() {
        artifactTask?.cancel(); artifactTask = nil
        artifactsPhase = artifacts.isEmpty ? .idle : .ready
    }

    func trashSelectedArtifacts() {
        let chosen = selectedArtifacts
        guard !chosen.isEmpty else { return }
        var removed = 0
        var freed: Int64 = 0
        var refused: [String] = []
        var affectedProjects: Set<URL> = []
        for artifact in chosen {
            let verdict = SafetyGuard.verdictForProjectArtifact(artifact.url)
            guard verdict.isAllowed else {
                refused.append("\(artifact.projectName): \(verdict.reason ?? "blocked")"); continue
            }
            do {
                try FileManager.default.trashItem(at: artifact.url, resultingItemURL: nil)
                removed += 1; freed += artifact.bytes
                affectedProjects.insert(artifact.projectPath.standardizedFileURL)
            } catch { refused.append("\(artifact.projectName): \(error.localizedDescription)") }
        }
        let fm = FileManager.default
        artifacts.removeAll { !fm.fileExists(atPath: $0.url.path) }
        artifactSelection.formIntersection(Set(artifacts.map(\.id)))
        disk = DiskSpace.snapshot()
        setArtifactNotice("Moved \(removed) \(removed == 1 ? "artifact" : "artifacts") to the Trash — \(freed.byteLabel)." +
            (refused.isEmpty ? "" : " \(refused.count) left alone: \(refused.prefix(2).joined(separator: "; "))"))
        refreshArtifacts(in: Array(affectedProjects))
    }

    private func setFileNotice(_ notice: String?) {
        fileNoticeTask?.cancel()
        fileNotice = notice
        guard notice != nil else { return }
        fileNoticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            self?.fileNotice = nil
        }
    }

    private func setArtifactNotice(_ notice: String?) {
        artifactNoticeTask?.cancel()
        artifactNotice = notice
        guard notice != nil else { return }
        artifactNoticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            self?.artifactNotice = nil
        }
    }

    private func refreshArtifacts(in projectDirectories: [URL]) {
        guard !projectDirectories.isEmpty else { return }
        artifactTask?.cancel()
        let scopes = Set(projectDirectories.map(\.standardizedFileURL))
        artifactTask = Task { [weak self] in
            let refreshed = await ArtifactScanner.scan(projectDirectories: Array(scopes))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                self.artifacts.removeAll { scopes.contains($0.projectPath.standardizedFileURL) }
                for artifact in refreshed { self.mergeArtifact(artifact) }
                self.artifactSelection.formIntersection(Set(self.artifacts.map(\.id)))
                self.lastArtifactScan = Date()
            }
        }
    }
}
