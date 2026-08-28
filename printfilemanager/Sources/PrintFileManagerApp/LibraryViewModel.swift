import AppKit
import Foundation
import PrintFileManagerCore

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published private(set) var snapshot = LibrarySnapshot() {
        didSet { snapshotRevision &+= 1 }
    }
    @Published var selectedCollection: SmartCollection? = .all
    @Published var selectedRootID: UUID?
    @Published var selectedRecordID: UUID?
    @Published var selectedRecordIDs: Set<UUID> = []
    @Published var searchText = ""
    @Published var sortOption: SortOption = .name
    @Published var sortAscending = true
    @Published var selectedTags: Set<String> = []
    @Published var selectedPrintabilities: Set<PrintabilityStatus> = []
    @Published var selectedMaterials: Set<String> = []
    @Published var selectedPrinters: Set<String> = []
    @Published var selectedSourcePlatforms: Set<String> = []
    @Published var selectedSourceVersionStatuses: Set<SourceVersionStatus> = []
    @Published private(set) var isScanning = false
    @Published private(set) var isEnriching = false
    @Published private(set) var isLookingUpSource = false
    @Published private(set) var isOrganizing = false
    @Published var organizationPlan: OrganizationPlan?

    /// The most recent completed batch, kept so its result can be shown and undone.
    @Published var lastOrganizationReport: OrganizationExecutionReport?

    @Published var deleteCandidate: PrintFileRecord?
    @Published private(set) var statusMessage = ""

    /// Set when the library file exists but could not be decoded. While this holds a value the
    /// in-memory snapshot does not represent the user's library, so persistence is refused to
    /// avoid overwriting a recoverable file with empty data.
    @Published private(set) var persistenceLockout: PersistenceLockout?

    struct PersistenceLockout: Equatable {
        let reason: String
        let quarantinedFileURL: URL?
    }

    private let database: LibraryDatabase
    private let thumbnails: ThumbnailStore
    private let search = LibrarySearch()
    private let folderWatcher = FolderWatcher()
    private let isUsingVolatileFallbackStore: Bool

    /// How long mutations are batched before the library file is rewritten.
    private static let saveCoalescingDelayMilliseconds = 600

    private var pendingSaveTask: Task<Void, Never>?

    private var snapshotRevision: UInt64 = 0
    private var cachedFilterKey: FilterCacheKey?
    private var cachedFilteredRecords: [PrintFileRecord] = []
    private var cachedCollectionCounts: CollectionCounts?

    /// Decoded preview images, keyed by thumbnail key. Bounded so a large library does not pull
    /// every preview into memory just because it was scrolled past once.
    private let thumbnailCache: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.countLimit = 400
        return cache
    }()

    init(database: LibraryDatabase? = nil, thumbnailStore: ThumbnailStore? = nil) {
        if let database {
            self.database = database
            isUsingVolatileFallbackStore = false
        } else if let database = try? LibraryDatabase.applicationSupport() {
            self.database = database
            isUsingVolatileFallbackStore = false
        } else {
            // Application Support is unavailable. The temporary directory is purgeable, so the
            // user must be told that this index is not durable rather than losing it silently.
            let fallbackURL = FileManager.default.temporaryDirectory.appendingPathComponent("print-file-manager-index.json")
            self.database = LibraryDatabase(fileURL: fallbackURL)
            isUsingVolatileFallbackStore = true
        }

        if let thumbnailStore {
            thumbnails = thumbnailStore
        } else if let thumbnailStore = try? ThumbnailStore.applicationSupport() {
            thumbnails = thumbnailStore
        } else {
            thumbnails = ThumbnailStore(
                directoryURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("print-file-manager-thumbnails", isDirectory: true)
            )
        }
    }

    /// Loads a record's preview image on demand. Previews live on disk rather than in the index,
    /// so this is the only place they are read into memory.
    func thumbnail(for record: PrintFileRecord) -> Data? {
        guard let key = record.thumbnailKey else { return nil }

        if let cached = thumbnailCache.object(forKey: key as NSString) {
            return cached as Data
        }

        guard let data = thumbnails.data(forKey: key) else { return nil }
        thumbnailCache.setObject(data as NSData, forKey: key as NSString)
        return data
    }

    var filteredRecords: [PrintFileRecord] {
        let query = currentQuery()
        let key = FilterCacheKey(snapshotRevision: snapshotRevision, query: query)
        if let cachedFilterKey, cachedFilterKey == key {
            return cachedFilteredRecords
        }

        let records = search.records(in: snapshot, matching: query)
        cachedFilterKey = key
        cachedFilteredRecords = records
        return records
    }

    private func currentQuery() -> LibraryQuery {
        LibraryQuery(
            text: searchText,
            smartCollection: selectedCollection,
            rootID: selectedRootID,
            selectedTags: selectedTags,
            selectedPrintabilities: selectedPrintabilities,
            selectedMaterials: selectedMaterials,
            selectedPrinters: selectedPrinters,
            selectedSourcePlatforms: selectedSourcePlatforms,
            selectedSourceVersionStatuses: selectedSourceVersionStatuses,
            sortOption: sortOption,
            sortAscending: sortAscending
        )
    }

    /// SwiftUI re-reads `filteredRecords` on every body pass, so without this the whole library is
    /// filtered and sorted many times per frame. The cache is invalidated by any snapshot mutation
    /// (via `snapshotRevision`) or any change to the query itself.
    private struct FilterCacheKey: Equatable {
        let snapshotRevision: UInt64
        let query: LibraryQuery
    }

    var selectedRecord: PrintFileRecord? {
        guard let selectedRecordID else { return nil }
        return snapshot.records.first { $0.id == selectedRecordID }
    }

    var selectedRecordsForOrganization: [PrintFileRecord] {
        guard !selectedRecordIDs.isEmpty else { return [] }
        return filteredRecords.filter { selectedRecordIDs.contains($0.id) }
    }

    var selectedRecordCount: Int {
        selectedRecordsForOrganization.count
    }

    var allTags: [String] {
        let tags = snapshot.records.flatMap { record in
            record.userTags + record.generatedTags.filter { $0.state == .accepted }.map(\.value)
        }
        return Array(Set(tags)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    var allMaterials: [String] {
        let values = snapshot.records.flatMap { record in
            var materials = record.printDetails?.materials ?? []
            if let aiMaterialHints = record.metadata["ai.materialHints"] {
                materials.append(contentsOf: aiMaterialHints.components(separatedBy: ","))
            }
            return materials
        }
        return normalizedFacetValues(values)
    }

    var allPrinters: [String] {
        let values = snapshot.records.flatMap { record in
            var printers: [String] = []
            if let printer = record.printDetails?.printer {
                printers.append(printer)
            }
            if let history = record.printHistory {
                printers.append(contentsOf: history.map(\.printer))
            }
            return printers
        }
        return normalizedFacetValues(values)
    }

    var allSourcePlatforms: [String] {
        normalizedFacetValues(snapshot.records.compactMap { $0.sourceInfo?.platform })
    }

    var availableSourceVersionStatuses: [SourceVersionStatus] {
        let statuses = Set(snapshot.records.map(sourceVersionStatus(for:)))
        return SourceVersionStatus.allCases.filter { statuses.contains($0) }
    }

    var activeFilterCount: Int {
        selectedTags.count
            + selectedPrintabilities.count
            + selectedMaterials.count
            + selectedPrinters.count
            + selectedSourcePlatforms.count
            + selectedSourceVersionStatuses.count
    }

    var managedFolderURL: URL? {
        snapshot.managedFolderURL
    }

    func clearFilters() {
        selectedTags.removeAll()
        selectedPrintabilities.removeAll()
        selectedMaterials.removeAll()
        selectedPrinters.removeAll()
        selectedSourcePlatforms.removeAll()
        selectedSourceVersionStatuses.removeAll()
    }

    func toggleTagFilter(_ tag: String) {
        toggleTrimmedString(tag, in: &selectedTags)
    }

    func toggleMaterialFilter(_ material: String) {
        toggleTrimmedString(material, in: &selectedMaterials)
    }

    func togglePrinterFilter(_ printer: String) {
        toggleTrimmedString(printer, in: &selectedPrinters)
    }

    func toggleSourcePlatformFilter(_ platform: String) {
        toggleTrimmedString(platform, in: &selectedSourcePlatforms)
    }

    func togglePrintabilityFilter(_ printability: PrintabilityStatus) {
        if selectedPrintabilities.contains(printability) {
            selectedPrintabilities.remove(printability)
        } else {
            selectedPrintabilities.insert(printability)
        }
    }

    func toggleSourceVersionStatusFilter(_ status: SourceVersionStatus) {
        if selectedSourceVersionStatuses.contains(status) {
            selectedSourceVersionStatuses.remove(status)
        } else {
            selectedSourceVersionStatuses.insert(status)
        }
    }

    func reviewReasons(for record: PrintFileRecord) -> [ReviewReason] {
        search.reviewReasons(for: record, in: snapshot)
    }

    func isReviewDismissed(for record: PrintFileRecord) -> Bool {
        guard let signature = search.reviewSignature(for: record, in: snapshot) else { return false }
        return record.reviewedIssueSignature == signature
    }

    func markReviewed(_ record: PrintFileRecord) {
        guard let signature = search.reviewSignature(for: record, in: snapshot) else {
            statusMessage = "No review items for \(record.fileName)"
            return
        }

        update(record) { mutableRecord in
            mutableRecord.reviewedAt = Date()
            mutableRecord.reviewedIssueSignature = signature
        }
        statusMessage = "Marked \(record.fileName) reviewed"
    }

    func reopenReview(_ record: PrintFileRecord) {
        update(record) { mutableRecord in
            mutableRecord.reviewedAt = nil
            mutableRecord.reviewedIssueSignature = nil
        }
        statusMessage = "Reopened review for \(record.fileName)"
    }

    func load() async {
        do {
            let loadedSnapshot = try database.load()
            snapshot = promoteAcceptedGeneratedTags(in: pruneGeneratedTagState(in: loadedSnapshot))
            persistenceLockout = nil
            if snapshot != loadedSnapshot {
                try? database.save(snapshot)
            }
            statusMessage = snapshot.records.isEmpty ? "No files indexed" : "\(snapshot.records.count) files indexed"
            if isUsingVolatileFallbackStore {
                statusMessage += " — warning: Application Support is unavailable, this index is stored in a temporary location and may be purged."
            }
            startWatchingFolders()
        } catch {
            // The library file exists but is unusable. Preserve it and refuse to write until the
            // user has decided what to do, otherwise the next edit would destroy it.
            let quarantinedURL = try? database.quarantineUnreadableIndex()
            persistenceLockout = PersistenceLockout(
                reason: error.localizedDescription,
                quarantinedFileURL: quarantinedURL
            )
            statusMessage = quarantinedURL == nil
                ? "Library index could not be loaded — changes will not be saved."
                : "Library index could not be loaded. A copy was preserved; changes will not be saved until you resolve it."
        }
    }

    /// Discards the unreadable library and starts over, releasing the write lock.
    func startFreshLibraryAfterLoadFailure() {
        guard persistenceLockout != nil else { return }
        snapshot = LibrarySnapshot()
        persistenceLockout = nil
        statusMessage = "Started a new library index"
        saveSnapshot()
    }

    func addFolderFromPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add Folder"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        addRoot(url: url)
    }

    func setManagedFolderFromPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Set Managed Folder"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        setManagedFolder(url: url)
    }

    func setManagedFolder(url: URL) {
        var next = snapshot
        next.managedFolderURL = url.standardizedFileURL
        snapshot = database.upsert(
            root: LibraryRoot(url: url, displayName: "Managed Library", isWatched: true),
            into: next
        )
        saveSnapshot()
        startWatchingFolders()
        if let root = snapshot.roots.first(where: { $0.url == url.standardizedFileURL }) {
            scan(root: root)
        }
    }

    func addRoot(url: URL) {
        let root = LibraryRoot(url: url, isWatched: true)
        snapshot = database.upsert(root: root, into: snapshot)
        saveSnapshot()
        startWatchingFolders()

        if let storedRoot = snapshot.roots.first(where: { $0.url == root.url }) {
            scan(root: storedRoot)
        }
    }

    func rescanAllRoots() {
        for root in snapshot.roots {
            scan(root: root)
        }
    }

    func count(for collection: SmartCollection) -> Int {
        cachedCounts(for: snapshotRevision).collections[collection] ?? 0
    }

    func count(for root: LibraryRoot) -> Int {
        cachedCounts(for: snapshotRevision).roots[root.id] ?? 0
    }

    /// Every sidebar badge asks for a count on each render. Computing them all once per snapshot
    /// change replaces roughly a dozen full library scans per frame with one pass.
    private func cachedCounts(for revision: UInt64) -> CollectionCounts {
        if let cachedCollectionCounts, cachedCollectionCounts.snapshotRevision == revision {
            return cachedCollectionCounts
        }

        var collections: [SmartCollection: Int] = [:]
        for collection in SmartCollection.allCases {
            collections[collection] = search.records(
                in: snapshot,
                matching: LibraryQuery(text: "", smartCollection: collection, sortOption: .name)
            ).count
        }

        var roots: [UUID: Int] = [:]
        for root in snapshot.roots {
            roots[root.id] = search.records(
                in: snapshot,
                matching: LibraryQuery(text: "", smartCollection: nil, rootID: root.id, sortOption: .name)
            ).count
        }

        let counts = CollectionCounts(snapshotRevision: revision, collections: collections, roots: roots)
        cachedCollectionCounts = counts
        return counts
    }

    private struct CollectionCounts {
        let snapshotRevision: UInt64
        let collections: [SmartCollection: Int]
        let roots: [UUID: Int]
    }

    func select(collection: SmartCollection) {
        selectedCollection = collection
        selectedRootID = nil
        selectedRecordID = nil
        selectedRecordIDs.removeAll()
        sortOption = collection.defaultSortOption
        sortAscending = collection.defaultSortAscending
    }

    func select(root: LibraryRoot) {
        selectedCollection = nil
        selectedRootID = root.id
        selectedRecordID = nil
        selectedRecordIDs.removeAll()
        sortOption = .name
        sortAscending = true
    }

    func select(record: PrintFileRecord, extendingSelection: Bool) {
        if extendingSelection {
            if selectedRecordIDs.contains(record.id) {
                selectedRecordIDs.remove(record.id)
                selectedRecordID = firstVisibleSelectedRecordID()
            } else {
                selectedRecordIDs.insert(record.id)
                selectedRecordID = record.id
            }
        } else {
            selectedRecordIDs = [record.id]
            selectedRecordID = record.id
        }
    }

    func scan(root: LibraryRoot) {
        isScanning = true
        statusMessage = "Scanning \(root.displayName)"

        Task {
            do {
                let knownRecords = snapshot.records.filter { $0.rootID == root.id }
                let thumbnailStore = thumbnails
                let result = try await Task.detached(priority: .userInitiated) {
                    try LibraryIndexer(thumbnailStore: thumbnailStore).scan(root: root, previousRecords: knownRecords)
                }.value

                snapshot = database.merge(scanResult: result, into: snapshot)
                saveSnapshot()
                startWatchingFolders()
                statusMessage = "\(result.records.count) files indexed in \(root.displayName)"
            } catch {
                statusMessage = "Scan failed for \(root.displayName)"
            }
            isScanning = false
        }
    }

    func acceptGeneratedTag(_ tag: GeneratedTag, for record: PrintFileRecord) {
        guard !suppressedVisibleTagValues.contains(tag.value.lowercased()) else {
            rejectGeneratedTag(tag, for: record)
            return
        }

        update(record) { mutableRecord in
            guard let index = mutableRecord.generatedTags.firstIndex(where: { $0.id == tag.id }) else { return }
            mutableRecord.generatedTags[index].state = .accepted
            addVisibleTag(tag.value, to: &mutableRecord)
        }
        statusMessage = "Accepted tag \(tag.value)"
    }

    func rejectGeneratedTag(_ tag: GeneratedTag, for record: PrintFileRecord) {
        update(record) { mutableRecord in
            guard let index = mutableRecord.generatedTags.firstIndex(where: { $0.id == tag.id }) else { return }
            mutableRecord.generatedTags[index].state = .rejected
        }
        statusMessage = "Rejected tag \(tag.value)"
    }

    func addUserTag(_ value: String, to record: PrintFileRecord) {
        let tag = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else { return }

        update(record) { mutableRecord in
            addVisibleTag(tag, to: &mutableRecord)
        }
    }

    func removeUserTag(_ value: String, from record: PrintFileRecord) {
        update(record) { mutableRecord in
            mutableRecord.userTags.removeAll { $0.caseInsensitiveCompare(value) == .orderedSame }
            for index in mutableRecord.generatedTags.indices where mutableRecord.generatedTags[index].value.caseInsensitiveCompare(value) == .orderedSame && mutableRecord.generatedTags[index].state == .accepted {
                mutableRecord.generatedTags[index].state = .rejected
            }
        }
    }

    func updateNotes(_ notes: String, for record: PrintFileRecord) {
        update(record) { mutableRecord in
            mutableRecord.notes = notes
        }
    }

    func enrich(record: PrintFileRecord, settings: AIEnrichmentSettings, allowSourceLookup: Bool) {
        isEnriching = true
        isLookingUpSource = allowSourceLookup
        statusMessage = allowSourceLookup ? "AI enrichment and source lookup running" : "AI enrichment running"

        Task {
            do {
                let result = try await AIEnrichmentClient().enrich(
                    record: record,
                    settings: settings,
                    thumbnailData: thumbnail(for: record)
                )
                var lookupRecord = record
                if let sourceInfo = result.sourceInfo {
                    lookupRecord.sourceInfo = mergeSourceInfo(existing: lookupRecord.sourceInfo, incoming: sourceInfo)
                }
                // Web lookup is a separate provider and a separate consent decision, so it only
                // runs when the user has explicitly enabled it.
                let sourceResult = allowSourceLookup
                    ? try? await SourceLookupClient().lookup(record: lookupRecord, settings: settings)
                    : nil

                update(record) { mutableRecord in
                    applyAIEnrichmentResult(result, to: &mutableRecord)
                    if let sourceResult {
                        applySourceLookupResult(sourceResult, to: &mutableRecord)
                    }
                }
                statusMessage = sourceResult == nil ? "AI suggestions added" : "AI suggestions and source details added"
            } catch {
                statusMessage = "AI enrichment failed: \(Self.errorMessage(for: error))"
            }

            isLookingUpSource = false
            isEnriching = false
        }
    }

    func lookupSource(record: PrintFileRecord, settings: AIEnrichmentSettings?, isEnabled: Bool) {
        guard isEnabled else {
            statusMessage = "Web source lookup is disabled. Enable it in Settings to search for the original model page."
            return
        }

        isLookingUpSource = true
        statusMessage = "Source lookup running"

        Task {
            do {
                let result = try await SourceLookupClient().lookup(record: record, settings: settings)
                update(record) { mutableRecord in
                    applySourceLookupResult(result, to: &mutableRecord)
                }
                statusMessage = "Source details updated"
            } catch {
                statusMessage = "Source lookup failed: \(Self.errorMessage(for: error))"
            }

            isLookingUpSource = false
        }
    }

    private static func errorMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }
        return error.localizedDescription
    }

    func updateDomainFields(
        category: String,
        variantName: String,
        printability: PrintabilityStatus?,
        for record: PrintFileRecord
    ) {
        update(record) { mutableRecord in
            mutableRecord.category = trimmedOptional(category)
            mutableRecord.variantName = trimmedOptional(variantName)
            mutableRecord.printability = printability
        }
    }

    func updateSourceInfo(
        platform: String,
        author: String,
        license: String,
        url: String,
        for record: PrintFileRecord
    ) {
        update(record) { mutableRecord in
            mutableRecord.sourceInfo = PrintSourceInfo(
                platform: trimmedOptional(platform),
                author: trimmedOptional(author),
                license: trimmedOptional(license),
                url: trimmedOptional(url),
                downloadedAt: mutableRecord.sourceInfo?.downloadedAt
            )
        }
    }

    func addPrintHistoryEntry(printer: String, material: String, result: String, notes: String, to record: PrintFileRecord) {
        let entry = PrintHistoryEntry(
            printer: printer.trimmingCharacters(in: .whitespacesAndNewlines),
            material: material.trimmingCharacters(in: .whitespacesAndNewlines),
            result: result.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        guard !entry.printer.isEmpty || !entry.material.isEmpty || !entry.result.isEmpty || !entry.notes.isEmpty else { return }

        update(record) { mutableRecord in
            var history = mutableRecord.printHistory ?? []
            history.insert(entry, at: 0)
            mutableRecord.printHistory = history
        }
    }

    func removePrintHistoryEntry(_ entry: PrintHistoryEntry, from record: PrintFileRecord) {
        update(record) { mutableRecord in
            mutableRecord.printHistory?.removeAll { $0.id == entry.id }
        }
    }

    func requestDelete(record: PrintFileRecord) {
        deleteCandidate = record
    }

    func openInDefaultApp(record: PrintFileRecord) {
        guard FileManager.default.fileExists(atPath: record.url.path) else {
            statusMessage = "File is missing"
            return
        }

        NSWorkspace.shared.open(record.url)
        statusMessage = "Opening \(record.fileName)"
    }

    func openInBambuStudio(record: PrintFileRecord) {
        guard FileManager.default.fileExists(atPath: record.url.path) else {
            statusMessage = "File is missing"
            return
        }

        guard let appURL = bambuStudioURL() else {
            NSWorkspace.shared.open(record.url)
            statusMessage = "Bambu Studio not found; opened with default app"
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([record.url], withApplicationAt: appURL, configuration: configuration) { [weak self] _, error in
            Task { @MainActor in
                self?.statusMessage = error == nil ? "Opening in Bambu Studio" : "Could not open in Bambu Studio"
            }
        }
    }

    func moveDeleteCandidateToTrash() {
        guard let record = deleteCandidate else { return }
        deleteCandidate = nil
        moveToTrash(record: record)
    }

    private func moveToTrash(record: PrintFileRecord) {
        guard FileManager.default.fileExists(atPath: record.url.path) else {
            removeRecordFromIndex(record)
            statusMessage = "Removed missing file from library"
            return
        }

        statusMessage = "Moving \(record.fileName) to Trash"
        NSWorkspace.shared.recycle([record.url]) { [weak self] _, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.statusMessage = "Could not move \(record.fileName) to Trash: \(error.localizedDescription)"
                } else {
                    self.removeRecordFromIndex(record)
                    self.statusMessage = "Moved \(record.fileName) to Trash"
                }
            }
        }
    }

    private func removeRecordFromIndex(_ record: PrintFileRecord) {
        snapshot.records.removeAll { $0.id == record.id }
        selectedRecordIDs.remove(record.id)
        if selectedRecordID == record.id {
            selectedRecordID = firstVisibleSelectedRecordID()
        }
        // The file is gone from disk, so the index must not lag behind it.
        flushPendingSave()
    }

    private func bambuStudioURL() -> URL? {
        let workspace = NSWorkspace.shared
        let bundleIdentifiers = [
            "com.bambulab.bambu-studio",
            "com.bambulab.BambuStudio",
            "com.bambulab.bambustudio"
        ]

        for bundleIdentifier in bundleIdentifiers {
            if let url = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                return url
            }
        }

        let candidatePaths = [
            "/Applications/Bambu Studio.app",
            "\(NSHomeDirectory())/Applications/Bambu Studio.app"
        ]

        return candidatePaths
            .map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    func prepareOrganizationPlan(settings: AIEnrichmentSettings? = nil) {
        prepareOrganizationPlan(kind: .copy, settings: settings)
    }

    func prepareMoveOrganizationPlan(settings: AIEnrichmentSettings? = nil) {
        prepareOrganizationPlan(kind: .move, settings: settings)
    }

    func prepareCopyPlan(for record: PrintFileRecord, settings: AIEnrichmentSettings? = nil) {
        prepareOrganizationPlan(records: [record], kind: .copy, settings: settings)
    }

    func prepareMovePlan(for record: PrintFileRecord, settings: AIEnrichmentSettings? = nil) {
        prepareOrganizationPlan(records: [record], kind: .move, settings: settings)
    }

    private func prepareOrganizationPlan(kind: OrganizationActionKind, settings: AIEnrichmentSettings?) {
        let records = selectedRecordsForOrganization
        guard !records.isEmpty else {
            statusMessage = "Select files to auto sort"
            return
        }

        prepareOrganizationPlan(records: records, kind: kind, settings: settings)
    }

    private func prepareOrganizationPlan(records: [PrintFileRecord], kind: OrganizationActionKind, settings: AIEnrichmentSettings?) {
        guard let managedFolderURL else {
            statusMessage = "Set a managed folder first"
            return
        }

        let activeRecords = records.filter { $0.indexingStatus != .missing }
        guard !activeRecords.isEmpty else {
            statusMessage = "No available files to organize"
            return
        }

        if let settings {
            prepareAIOrganizationPlan(records: activeRecords, kind: kind, managedFolderURL: managedFolderURL, settings: settings)
            return
        }

        let planner = OrganizationPlanner()
        let plan = kind == .move
            ? planner.planMove(records: activeRecords, to: managedFolderURL)
            : planner.planCopy(records: activeRecords, to: managedFolderURL)
        organizationPlan = plan
        statusMessage = "Prepared \(plan.actions.count) \(kind.rawValue) actions"
    }

    private func prepareAIOrganizationPlan(
        records: [PrintFileRecord],
        kind: OrganizationActionKind,
        managedFolderURL: URL,
        settings: AIEnrichmentSettings
    ) {
        isOrganizing = true
        statusMessage = "AI is planning folders for \(records.count) files"

        Task {
            let folderContext = await Self.organizationFolderContext(for: managedFolderURL)
            let suggestions = await organizationSuggestions(for: records, settings: settings, folderContext: folderContext)
            let planner = OrganizationPlanner()
            let plan = kind == .move
                ? planner.planMove(records: records, to: managedFolderURL, suggestions: suggestions)
                : planner.planCopy(records: records, to: managedFolderURL, suggestions: suggestions)

            organizationPlan = plan
            statusMessage = suggestions.isEmpty
                ? "Prepared \(plan.actions.count) \(kind.rawValue) actions with local fallback"
                : "Prepared \(plan.actions.count) AI-assisted \(kind.rawValue) actions"
            isOrganizing = false
        }
    }

    private func organizationSuggestions(
        for records: [PrintFileRecord],
        settings: AIEnrichmentSettings,
        folderContext: OrganizationFolderContext
    ) async -> [OrganizationSuggestion] {
        var suggestions: [OrganizationSuggestion] = []
        var runningFolderContext = folderContext
        let client = AIEnrichmentClient()

        for record in records {
            do {
                let suggestion = try await client.organizationSuggestion(for: record, settings: settings, folderContext: runningFolderContext)
                if !suggestion.relativePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    suggestions.append(suggestion)
                    runningFolderContext.insertDirectory((suggestion.relativePath as NSString).deletingLastPathComponent)
                }
            } catch {
                statusMessage = "AI folder planning skipped \(record.fileName): \(Self.errorMessage(for: error))"
            }
        }

        return suggestions
    }

    private nonisolated static func organizationFolderContext(for rootURL: URL) async -> OrganizationFolderContext {
        await Task.detached(priority: .userInitiated) {
            let root = rootURL.standardizedFileURL
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                return OrganizationFolderContext()
            }

            var directories: [String] = []
            while let url = enumerator.nextObject() as? URL {
                guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                let relativePath = Self.relativeDirectoryPath(for: url.standardizedFileURL, root: root)
                if !relativePath.isEmpty {
                    directories.append(relativePath)
                }
            }

            return OrganizationFolderContext(existingDirectories: directories)
        }.value
    }

    private nonisolated static func relativeDirectoryPath(for url: URL, root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else { return "" }
        let startIndex = path.index(path.startIndex, offsetBy: rootPath.count + 1)
        return String(path[startIndex...])
    }

    func executeOrganizationPlan(_ plan: OrganizationPlan) {
        isOrganizing = true
        let isMovePlan = plan.actions.contains { $0.kind == .move }
        statusMessage = isMovePlan ? "Moving files into managed library" : "Copying files into managed library"

        Task {
            let report = await Task.detached(priority: .userInitiated) {
                OrganizationPlanner().execute(plan)
            }.value

            // Only the moves that actually happened may update the index.
            applyMovedRecords(from: report)
            organizationPlan = nil
            lastOrganizationReport = report
            statusMessage = report.summary
            rescanManagedFolder()
            isOrganizing = false
        }
    }

    /// Reverses the most recent organization batch: moves go back, copies are deleted from the
    /// destination. The user's originals are never removed.
    func undoLastOrganization() {
        guard let report = lastOrganizationReport, report.isUndoable else { return }

        isOrganizing = true
        statusMessage = "Undoing \(report.kind == .move ? "move" : "copy")"

        Task {
            let undoReport = await Task.detached(priority: .userInitiated) {
                OrganizationPlanner().undo(report)
            }.value

            // Undoing a move puts each file back at its original path.
            for outcome in undoReport.outcomes where outcome.result == .succeeded && outcome.action.kind == .move {
                guard let index = snapshot.records.firstIndex(where: { $0.id == outcome.action.recordID }) else { continue }
                snapshot.records[index].url = outcome.action.sourceURL.standardizedFileURL
                snapshot.records[index].fileName = outcome.action.sourceURL.lastPathComponent
            }
            flushPendingSave()

            lastOrganizationReport = nil
            statusMessage = undoReport.failedCount == 0
                ? "Undo complete — \(undoReport.succeededCount) files restored"
                : "Undo finished with problems — \(undoReport.summary)"
            rescanManagedFolder()
            isOrganizing = false
        }
    }

    func dismissOrganizationReport() {
        lastOrganizationReport = nil
    }

    private func rescanManagedFolder() {
        guard let managedFolderURL,
              let root = snapshot.roots.first(where: { $0.url == managedFolderURL.standardizedFileURL }) else {
            return
        }
        scan(root: root)
    }

    private func applyMovedRecords(from report: OrganizationExecutionReport) {
        let targetRoot = snapshot.roots.first { $0.url == report.targetRootURL.standardizedFileURL }

        for outcome in report.successfulOutcomes where outcome.action.kind == .move {
            let action = outcome.action
            guard let index = snapshot.records.firstIndex(where: { $0.id == action.recordID }) else { continue }
            snapshot.records[index].rootID = targetRoot?.id ?? snapshot.records[index].rootID
            snapshot.records[index].url = action.destinationURL.standardizedFileURL
            snapshot.records[index].fileName = action.destinationURL.lastPathComponent
            snapshot.records[index].relativePath = relativePath(for: action.destinationURL, rootURL: report.targetRootURL)
            snapshot.records[index].indexingStatus = .indexed
            snapshot.records[index].errorMessage = nil
        }

        // Files have physically moved; persist immediately so a crash cannot strand the index
        // pointing at the old paths.
        flushPendingSave()
    }

    private func relativePath(for url: URL, rootURL: URL) -> String {
        let rootPath = rootURL.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath + "/") else { return url.lastPathComponent }
        let startIndex = filePath.index(filePath.startIndex, offsetBy: rootPath.count + 1)
        return String(filePath[startIndex...])
    }

    private func firstVisibleSelectedRecordID() -> UUID? {
        filteredRecords.first { selectedRecordIDs.contains($0.id) }?.id
    }

    private func update(_ record: PrintFileRecord, mutation: (inout PrintFileRecord) -> Void) {
        guard let index = snapshot.records.firstIndex(where: { $0.id == record.id }) else { return }
        mutation(&snapshot.records[index])
        saveSnapshot()
    }

    private func applyAIEnrichmentResult(_ result: AIEnrichmentResult, to mutableRecord: inout PrintFileRecord) {
        if !result.description.isEmpty {
            mutableRecord.metadata["ai.description"] = result.description
        }
        if let category = result.category {
            mutableRecord.category = category
        }
        if let variantName = result.variantName {
            mutableRecord.variantName = variantName
        }
        if let printability = result.printability {
            mutableRecord.printability = printability
        }
        if let sourceInfo = result.sourceInfo {
            mutableRecord.sourceInfo = mergeSourceInfo(existing: mutableRecord.sourceInfo, incoming: sourceInfo)
        }
        if !result.materialHints.isEmpty {
            let existingHints = Set((mutableRecord.metadata["ai.materialHints"] ?? "")
                .components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty })
            mutableRecord.metadata["ai.materialHints"] = existingHints.union(result.materialHints).sorted().joined(separator: ", ")
        }
        if let workflowNotes = result.workflowNotes {
            mutableRecord.metadata["ai.workflowNotes"] = workflowNotes
        }

        for tag in result.tags {
            let knownTags = mutableRecord.generatedTags.map { $0.value.lowercased() }
            if !knownTags.contains(tag.lowercased()) {
                mutableRecord.generatedTags.append(GeneratedTag(value: tag, confidence: 0.72, source: "ai"))
            }
        }
        mutableRecord.generatedTags.sort { $0.value.localizedStandardCompare($1.value) == .orderedAscending }
    }

    private func applySourceLookupResult(_ result: SourceLookupResult, to mutableRecord: inout PrintFileRecord) {
        if let sourceInfo = result.sourceInfo {
            mutableRecord.sourceInfo = mergeSourceInfo(existing: mutableRecord.sourceInfo, incoming: sourceInfo, preferIncoming: true)
        }
        if let title = result.title, !title.isEmpty {
            mutableRecord.metadata["source.title"] = title
        }
        if let description = result.description, !description.isEmpty {
            mutableRecord.metadata["source.description"] = description
        }
        if let latestVersion = result.latestVersion, !latestVersion.isEmpty {
            mutableRecord.metadata["source.latestVersion"] = latestVersion
        }
        mutableRecord.metadata["source.versionStatus"] = result.versionStatus.rawValue
        if let updatedAt = result.updatedAt {
            mutableRecord.metadata["source.updatedAt"] = Self.metadataDateString(updatedAt)
        }
        mutableRecord.metadata["source.checkedAt"] = Self.metadataDateString(result.checkedAt)
        if let searchQuery = result.searchQuery, !searchQuery.isEmpty {
            mutableRecord.metadata["source.searchQuery"] = searchQuery
        }
        if let matchConfidence = result.matchConfidence {
            mutableRecord.metadata["source.matchConfidence"] = String(format: "%.2f", matchConfidence)
        }
    }

    private func mergeSourceInfo(existing: PrintSourceInfo?, incoming: PrintSourceInfo, preferIncoming: Bool = false) -> PrintSourceInfo {
        PrintSourceInfo(
            platform: preferIncoming ? incoming.platform ?? existing?.platform : existing?.platform ?? incoming.platform,
            author: preferIncoming ? incoming.author ?? existing?.author : existing?.author ?? incoming.author,
            license: existing?.license ?? incoming.license,
            url: preferIncoming ? incoming.url ?? existing?.url : existing?.url ?? incoming.url,
            downloadedAt: existing?.downloadedAt ?? incoming.downloadedAt
        )
    }

    private static func metadataDateString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private func pruneGeneratedTagState(in snapshot: LibrarySnapshot) -> LibrarySnapshot {
        var next = snapshot
        next.records = snapshot.records.map { record in
            let validLocalSuggestions = Set(LocalTagSuggester()
                .suggestTags(
                    fileName: record.url.deletingPathExtension().lastPathComponent,
                    sourceHints: record.sourceHints,
                    metadata: record.metadata
                )
                .map { $0.value.lowercased() })
            var mutableRecord = record
            mutableRecord.userTags.removeAll { suppressedVisibleTagValues.contains($0.lowercased()) }
            mutableRecord.generatedTags = record.generatedTags.filter { tag in
                let value = tag.value.lowercased()
                guard !suppressedVisibleTagValues.contains(value) else { return false }
                return tag.source != "local" || tag.state != .suggested || validLocalSuggestions.contains(value)
            }
            return mutableRecord
        }
        return next
    }

    private func promoteAcceptedGeneratedTags(in snapshot: LibrarySnapshot) -> LibrarySnapshot {
        var next = snapshot
        next.records = snapshot.records.map { record in
            var mutableRecord = record
            for tag in record.generatedTags where tag.state == .accepted {
                addVisibleTag(tag.value, to: &mutableRecord)
            }
            return mutableRecord
        }
        return next
    }

    private func addVisibleTag(_ value: String, to record: inout PrintFileRecord) {
        let tag = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty, !suppressedVisibleTagValues.contains(tag.lowercased()) else { return }
        if !record.userTags.map({ $0.lowercased() }).contains(tag.lowercased()) {
            record.userTags.append(tag)
            record.userTags.sort { $0.localizedStandardCompare($1) == .orderedAscending }
        }
    }

    private let suppressedVisibleTagValues: Set<String> = ["3mf", "makerworld", "multi-plate"]

    private func trimmedOptional(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func toggleTrimmedString(_ value: String, in set: inout Set<String>) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let existing = set.first(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            set.remove(existing)
        } else {
            set.insert(trimmed)
        }
    }

    private func normalizedFacetValues(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0.lowercased()).inserted }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func sourceVersionStatus(for record: PrintFileRecord) -> SourceVersionStatus {
        guard let rawStatus = record.metadata["source.versionStatus"] else { return .unknown }
        return SourceVersionStatus(rawValue: rawStatus) ?? .unknown
    }

    private func saveSnapshot() {
        // Coalesced rather than immediate: the library is persisted as a single file, so writing
        // it on every mutation would rewrite the whole index on each keystroke in the notes field.
        pendingSaveTask?.cancel()
        pendingSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Self.saveCoalescingDelayMilliseconds))
            guard !Task.isCancelled else { return }
            self?.writeSnapshotNow()
        }
    }

    /// Persists any coalesced changes immediately. Call before the app terminates or whenever the
    /// index must match the file system right away.
    func flushPendingSave() {
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        writeSnapshotNow()
    }

    private func writeSnapshotNow() {
        if let lockout = persistenceLockout {
            statusMessage = "Changes are not being saved: \(lockout.reason)"
            return
        }

        do {
            try database.save(snapshot)
        } catch {
            statusMessage = "Library index could not be saved: \(error.localizedDescription)"
        }
    }

    private func startWatchingFolders() {
        folderWatcher.update(roots: snapshot.roots) { [weak self] root in
            self?.scan(root: root)
        }
    }
}
