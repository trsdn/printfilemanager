import PrintFileManagerCore
import XCTest
@testable import PrintFileManager

/// Tests for the app layer, which owns the highest-risk behaviour: refusing to overwrite an
/// unreadable library, orchestrating file operations, and selection.
@MainActor
final class LibraryViewModelTests: XCTestCase {

    // MARK: - Persistence safety

    func testLoadFailureBlocksSavesInsteadOfOverwritingTheLibrary() async throws {
        let folderURL = try makeTemporaryDirectory()
        let indexURL = folderURL.appendingPathComponent("library-index.json")
        let corruptContents = Data("{ not json".utf8)
        try corruptContents.write(to: indexURL)

        let viewModel = makeViewModel(indexURL: indexURL, folderURL: folderURL)
        await viewModel.load()

        XCTAssertNotNil(viewModel.persistenceLockout)

        // The unreadable file must be preserved, not left in place to be overwritten.
        XCTAssertFalse(FileManager.default.fileExists(atPath: indexURL.path))
        let quarantinedURL = try XCTUnwrap(viewModel.persistenceLockout?.quarantinedFileURL)
        XCTAssertEqual(try Data(contentsOf: quarantinedURL), corruptContents)

        // Any further edit must not resurrect the index file while the lockout stands.
        viewModel.setManagedFolder(url: folderURL)
        viewModel.flushPendingSave()
        XCTAssertFalse(FileManager.default.fileExists(atPath: indexURL.path))
    }

    func testStartingAFreshLibraryClearsTheLockoutAndSavesAgain() async throws {
        let folderURL = try makeTemporaryDirectory()
        let indexURL = folderURL.appendingPathComponent("library-index.json")
        try Data("{ not json".utf8).write(to: indexURL)

        let viewModel = makeViewModel(indexURL: indexURL, folderURL: folderURL)
        await viewModel.load()
        XCTAssertNotNil(viewModel.persistenceLockout)

        viewModel.startFreshLibraryAfterLoadFailure()
        viewModel.flushPendingSave()

        XCTAssertNil(viewModel.persistenceLockout)
        XCTAssertTrue(FileManager.default.fileExists(atPath: indexURL.path))
    }

    func testSavesAreCoalescedRatherThanWrittenPerEdit() async throws {
        let folderURL = try makeTemporaryDirectory()
        let indexURL = folderURL.appendingPathComponent("library-index.json")
        let viewModel = makeViewModel(indexURL: indexURL, folderURL: folderURL)
        await viewModel.load()

        let record = makeRecord(fileName: "clip.3mf", url: folderURL.appendingPathComponent("clip.3mf"))
        viewModel.replaceSnapshotForTesting(LibrarySnapshot(records: [record]))
        try? FileManager.default.removeItem(at: indexURL)

        // Simulates typing: each keystroke asks to save.
        for index in 0..<10 {
            viewModel.updateNotes("note \(index)", for: record)
        }

        // Nothing has hit disk yet because the writes are coalesced.
        XCTAssertFalse(FileManager.default.fileExists(atPath: indexURL.path))

        viewModel.flushPendingSave()
        XCTAssertTrue(FileManager.default.fileExists(atPath: indexURL.path))
    }

    // MARK: - Selection

    func testShiftClickSelectsTheRangeBetweenTheAnchorAndTheClickedFile() async throws {
        let folderURL = try makeTemporaryDirectory()
        let viewModel = makeViewModel(indexURL: folderURL.appendingPathComponent("i.json"), folderURL: folderURL)
        let records = (0..<5).map { index in
            makeRecord(fileName: "file-\(index).3mf", url: folderURL.appendingPathComponent("file-\(index).3mf"))
        }
        viewModel.replaceSnapshotForTesting(LibrarySnapshot(records: records))

        viewModel.select(record: records[1], modifier: .replace)
        viewModel.select(record: records[3], modifier: .extendRange)

        XCTAssertEqual(viewModel.selectedRecordIDs, Set(records[1...3].map(\.id)))
        XCTAssertEqual(viewModel.selectedRecordID, records[3].id)
    }

    func testShiftClickBackwardsSelectsTheSameRange() async throws {
        let folderURL = try makeTemporaryDirectory()
        let viewModel = makeViewModel(indexURL: folderURL.appendingPathComponent("i.json"), folderURL: folderURL)
        let records = (0..<5).map { index in
            makeRecord(fileName: "file-\(index).3mf", url: folderURL.appendingPathComponent("file-\(index).3mf"))
        }
        viewModel.replaceSnapshotForTesting(LibrarySnapshot(records: records))

        viewModel.select(record: records[3], modifier: .replace)
        viewModel.select(record: records[1], modifier: .extendRange)

        XCTAssertEqual(viewModel.selectedRecordIDs, Set(records[1...3].map(\.id)))
    }

    func testCommandClickTogglesIndividualFiles() async throws {
        let folderURL = try makeTemporaryDirectory()
        let viewModel = makeViewModel(indexURL: folderURL.appendingPathComponent("i.json"), folderURL: folderURL)
        let records = (0..<3).map { index in
            makeRecord(fileName: "file-\(index).3mf", url: folderURL.appendingPathComponent("file-\(index).3mf"))
        }
        viewModel.replaceSnapshotForTesting(LibrarySnapshot(records: records))

        viewModel.select(record: records[0], modifier: .replace)
        viewModel.select(record: records[2], modifier: .toggle)
        XCTAssertEqual(viewModel.selectedRecordIDs, Set([records[0].id, records[2].id]))

        viewModel.select(record: records[2], modifier: .toggle)
        XCTAssertEqual(viewModel.selectedRecordIDs, Set([records[0].id]))
    }

    func testSelectAllSelectsOnlyTheVisibleRecords() async throws {
        let folderURL = try makeTemporaryDirectory()
        let viewModel = makeViewModel(indexURL: folderURL.appendingPathComponent("i.json"), folderURL: folderURL)
        let matching = makeRecord(fileName: "cable-clip.3mf", url: folderURL.appendingPathComponent("cable-clip.3mf"))
        let other = makeRecord(fileName: "spool-holder.3mf", url: folderURL.appendingPathComponent("spool-holder.3mf"))
        viewModel.replaceSnapshotForTesting(LibrarySnapshot(records: [matching, other]))
        viewModel.searchText = "cable"
        // Search is debounced, so wait for it to reach the grid before selecting.
        try await waitUntil { viewModel.filteredRecords.count == 1 }

        viewModel.selectAllVisibleRecords()

        XCTAssertEqual(viewModel.selectedRecordIDs, Set([matching.id]))
    }

    func testClearingTheSearchAppliesImmediately() async throws {
        let folderURL = try makeTemporaryDirectory()
        let viewModel = makeViewModel(indexURL: folderURL.appendingPathComponent("i.json"), folderURL: folderURL)
        let matching = makeRecord(fileName: "cable-clip.3mf", url: folderURL.appendingPathComponent("cable-clip.3mf"))
        let other = makeRecord(fileName: "spool-holder.3mf", url: folderURL.appendingPathComponent("spool-holder.3mf"))
        viewModel.replaceSnapshotForTesting(LibrarySnapshot(records: [matching, other]))

        viewModel.searchText = "cable"
        try await waitUntil { viewModel.filteredRecords.count == 1 }

        // Clearing must not wait out the debounce; the user expects everything back at once.
        viewModel.searchText = ""
        XCTAssertEqual(viewModel.filteredRecords.count, 2)
    }

    // MARK: - Root management

    func testRemovingARootDropsItsRecordsButNotTheFilesOnDisk() async throws {
        let folderURL = try makeTemporaryDirectory()
        let viewModel = makeViewModel(indexURL: folderURL.appendingPathComponent("i.json"), folderURL: folderURL)

        let fileURL = folderURL.appendingPathComponent("clip.3mf")
        try Data("fixture".utf8).write(to: fileURL)

        let root = LibraryRoot(url: folderURL)
        let otherRoot = LibraryRoot(url: folderURL.appendingPathComponent("other", isDirectory: true))
        let record = makeRecord(fileName: "clip.3mf", url: fileURL, rootID: root.id)
        let keptRecord = makeRecord(fileName: "keep.3mf", url: folderURL.appendingPathComponent("keep.3mf"), rootID: otherRoot.id)
        viewModel.replaceSnapshotForTesting(LibrarySnapshot(roots: [root, otherRoot], records: [record, keptRecord]))

        viewModel.removeRoot(root)

        XCTAssertEqual(viewModel.snapshot.roots.map(\.id), [otherRoot.id])
        XCTAssertEqual(viewModel.snapshot.records.map(\.id), [keptRecord.id])
        XCTAssertNil(viewModel.removeRootRequest)
        // The user's file must survive removing the folder from the library.
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    // MARK: - Enrichment gating

    func testEnrichDoesNotRunSourceLookupWhenWebLookupIsDisabled() async throws {
        let folderURL = try makeTemporaryDirectory()
        let enrichment = StubEnrichmentClient()
        let lookup = StubSourceLookupClient()
        let viewModel = makeViewModel(
            indexURL: folderURL.appendingPathComponent("i.json"),
            folderURL: folderURL,
            enrichmentClient: enrichment,
            sourceLookupClient: lookup
        )
        let record = makeRecord(fileName: "clip.3mf", url: folderURL.appendingPathComponent("clip.3mf"))
        viewModel.replaceSnapshotForTesting(LibrarySnapshot(records: [record]))

        viewModel.enrich(record: record, settings: makeSettings(), allowSourceLookup: false)
        try await waitUntil { !viewModel.isEnriching }

        XCTAssertEqual(enrichment.enrichCallCount, 1)
        XCTAssertEqual(lookup.lookupCallCount, 0, "Web lookup must not run when the user has not enabled it")
    }

    func testEnrichRunsSourceLookupWhenWebLookupIsEnabled() async throws {
        let folderURL = try makeTemporaryDirectory()
        let enrichment = StubEnrichmentClient()
        let lookup = StubSourceLookupClient()
        let viewModel = makeViewModel(
            indexURL: folderURL.appendingPathComponent("i.json"),
            folderURL: folderURL,
            enrichmentClient: enrichment,
            sourceLookupClient: lookup
        )
        let record = makeRecord(fileName: "clip.3mf", url: folderURL.appendingPathComponent("clip.3mf"))
        viewModel.replaceSnapshotForTesting(LibrarySnapshot(records: [record]))

        viewModel.enrich(record: record, settings: makeSettings(), allowSourceLookup: true)
        try await waitUntil { !viewModel.isEnriching }

        XCTAssertEqual(lookup.lookupCallCount, 1)
    }

    func testLookupSourceRefusesToRunWhenDisabled() async throws {
        let folderURL = try makeTemporaryDirectory()
        let lookup = StubSourceLookupClient()
        let viewModel = makeViewModel(
            indexURL: folderURL.appendingPathComponent("i.json"),
            folderURL: folderURL,
            sourceLookupClient: lookup
        )
        let record = makeRecord(fileName: "clip.3mf", url: folderURL.appendingPathComponent("clip.3mf"))
        viewModel.replaceSnapshotForTesting(LibrarySnapshot(records: [record]))

        viewModel.lookupSource(record: record, settings: nil, isEnabled: false)

        XCTAssertEqual(lookup.lookupCallCount, 0)
        XCTAssertTrue(viewModel.statusMessage.contains("disabled"))
    }

    func testEnrichmentFailureSurfacesTheProviderMessage() async throws {
        let folderURL = try makeTemporaryDirectory()
        let enrichment = StubEnrichmentClient()
        enrichment.enrichError = AIEnrichmentError.httpError(statusCode: 401, message: "Invalid API key")
        let viewModel = makeViewModel(
            indexURL: folderURL.appendingPathComponent("i.json"),
            folderURL: folderURL,
            enrichmentClient: enrichment
        )
        let record = makeRecord(fileName: "clip.3mf", url: folderURL.appendingPathComponent("clip.3mf"))
        viewModel.replaceSnapshotForTesting(LibrarySnapshot(records: [record]))

        viewModel.enrich(record: record, settings: makeSettings(), allowSourceLookup: false)
        try await waitUntil { !viewModel.isEnriching }

        XCTAssertTrue(viewModel.statusMessage.contains("401"), "Got: \(viewModel.statusMessage)")
    }

    // MARK: - Organization

    func testExecutingAPlanReportsResultsAndKeepsTheIndexInStep() async throws {
        let sourceRoot = try makeTemporaryDirectory()
        let targetRoot = try makeTemporaryDirectory()
        let sourceURL = sourceRoot.appendingPathComponent("hook.3mf")
        try Data("fixture".utf8).write(to: sourceURL)

        let viewModel = makeViewModel(indexURL: sourceRoot.appendingPathComponent("i.json"), folderURL: sourceRoot)
        let record = makeRecord(fileName: "hook.3mf", url: sourceURL)
        viewModel.replaceSnapshotForTesting(LibrarySnapshot(records: [record]))

        let plan = OrganizationPlanner().planMove(records: [record], to: targetRoot)
        viewModel.executeOrganizationPlan(plan)
        try await waitUntil { !viewModel.isOrganizing }

        let report = try XCTUnwrap(viewModel.lastOrganizationReport)
        XCTAssertEqual(report.succeededCount, 1)
        XCTAssertNil(viewModel.organizationPlan)

        // The index must point at the file's new location, not its old one.
        let moved = try XCTUnwrap(viewModel.snapshot.records.first)
        XCTAssertNotEqual(moved.url, sourceURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: moved.url.path))
    }

    func testUndoRestoresTheFileAndTheIndexEntry() async throws {
        let sourceRoot = try makeTemporaryDirectory()
        let targetRoot = try makeTemporaryDirectory()
        let sourceURL = sourceRoot.appendingPathComponent("hook.3mf")
        try Data("fixture".utf8).write(to: sourceURL)

        let viewModel = makeViewModel(indexURL: sourceRoot.appendingPathComponent("i.json"), folderURL: sourceRoot)
        let record = makeRecord(fileName: "hook.3mf", url: sourceURL)
        viewModel.replaceSnapshotForTesting(LibrarySnapshot(records: [record]))

        viewModel.executeOrganizationPlan(OrganizationPlanner().planMove(records: [record], to: targetRoot))
        try await waitUntil { !viewModel.isOrganizing }

        viewModel.undoLastOrganization()
        try await waitUntil { !viewModel.isOrganizing }

        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertEqual(viewModel.snapshot.records.first?.url, sourceURL.standardizedFileURL)
        XCTAssertNil(viewModel.lastOrganizationReport)
    }

    // MARK: - Sandboxed folder access

    func testAddingARootStoresASecurityScopedBookmark() async throws {
        let folderURL = try makeTemporaryDirectory()
        let libraryFolder = try makeTemporaryDirectory()
        let viewModel = makeViewModel(indexURL: libraryFolder.appendingPathComponent("i.json"), folderURL: libraryFolder)

        viewModel.addRoot(url: folderURL)
        try await waitUntil { !viewModel.isScanning }

        // Without a bookmark the folder would be inaccessible after the next launch under sandbox.
        let root = try XCTUnwrap(viewModel.snapshot.roots.first)
        XCTAssertNotNil(root.securityScopedBookmark)
    }

    func testRootsFromBeforeBookmarksStillLoad() async throws {
        let libraryFolder = try makeTemporaryDirectory()
        let indexURL = libraryFolder.appendingPathComponent("library-index.json")
        let watchedFolder = try makeTemporaryDirectory()

        // A schema-2 index written before bookmarks existed: the key is simply absent.
        let legacyIndex: [String: Any] = [
            "schemaVersion": 2,
            "roots": [[
                "id": UUID().uuidString,
                "url": watchedFolder.absoluteString,
                "displayName": watchedFolder.lastPathComponent,
                "isWatched": true,
                "isAvailable": true
            ]],
            "records": []
        ]
        try JSONSerialization.data(withJSONObject: legacyIndex).write(to: indexURL)

        let viewModel = makeViewModel(indexURL: indexURL, folderURL: libraryFolder)
        await viewModel.load()

        XCTAssertNil(viewModel.persistenceLockout)
        XCTAssertEqual(viewModel.snapshot.roots.count, 1)
        XCTAssertNil(viewModel.snapshot.roots.first?.securityScopedBookmark)
    }

    // MARK: - Helpers

    private func makeViewModel(
        indexURL: URL,
        folderURL: URL,
        enrichmentClient: any AIEnriching = StubEnrichmentClient(),
        sourceLookupClient: any SourceLooking = StubSourceLookupClient()
    ) -> LibraryViewModel {
        LibraryViewModel(
            database: LibraryDatabase(fileURL: indexURL),
            thumbnailStore: ThumbnailStore(directoryURL: folderURL.appendingPathComponent("Thumbnails", isDirectory: true)),
            enrichmentClient: enrichmentClient,
            sourceLookupClient: sourceLookupClient
        )
    }

    private func makeRecord(fileName: String, url: URL, rootID: UUID = UUID()) -> PrintFileRecord {
        PrintFileRecord(
            rootID: rootID,
            url: url,
            fileName: fileName,
            relativePath: fileName,
            fileSize: 7,
            modifiedAt: Date(),
            indexingStatus: .indexed
        )
    }

    private func makeSettings() -> AIEnrichmentSettings {
        AIEnrichmentSettings(
            endpointURL: URL(string: "https://example.invalid/v1/chat/completions")!,
            apiKey: "",
            model: "test-model",
            includeThumbnail: false
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PrintFileManagerAppTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Polls until the view model reports it has finished, so tests do not depend on fixed sleeps.
    private func waitUntil(
        timeout: TimeInterval = 5,
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { XCTFail("Timed out waiting for the view model to settle"); return }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

// MARK: - Stubs

private final class StubEnrichmentClient: AIEnriching, @unchecked Sendable {
    var enrichCallCount = 0
    var enrichError: (any Error)?
    var suggestion = OrganizationSuggestion(recordID: UUID(), relativePath: "Stub/stub.3mf", rationale: "stub")

    func enrich(
        record: PrintFileRecord,
        settings: AIEnrichmentSettings,
        thumbnailData: Data?
    ) async throws -> AIEnrichmentResult {
        enrichCallCount += 1
        if let enrichError { throw enrichError }
        return AIEnrichmentResult(description: "stub description", tags: [])
    }

    func organizationSuggestion(
        for record: PrintFileRecord,
        settings: AIEnrichmentSettings,
        folderContext: OrganizationFolderContext
    ) async throws -> OrganizationSuggestion {
        suggestion
    }
}

private final class StubSourceLookupClient: SourceLooking, @unchecked Sendable {
    var lookupCallCount = 0
    var result = SourceLookupResult(versionStatus: .unknown)

    func lookup(record: PrintFileRecord, settings: AIEnrichmentSettings?) async throws -> SourceLookupResult {
        lookupCallCount += 1
        return result
    }
}
