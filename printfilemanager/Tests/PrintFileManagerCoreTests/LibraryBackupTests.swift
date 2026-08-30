import XCTest
@testable import PrintFileManagerCore

/// The `.bak` beside the index is the last copy of a state the app has since moved past. It is
/// written once per process, so exactly one bad session stands between a good backup and no backup
/// — which is what nearly happened when a test run rewrote a real library and the next run would
/// have replaced the only pre-migration copy of it.
final class LibraryBackupTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibraryBackupTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private var indexURL: URL { folder.appendingPathComponent("library-index.json") }
    private var backupURL: URL { folder.appendingPathComponent("library-index.json.bak") }

    private func snapshot(recordCount: Int, padding: Int = 0) -> LibrarySnapshot {
        let rootID = UUID()
        return LibrarySnapshot(
            roots: [LibraryRoot(id: rootID, url: folder)],
            records: (0..<recordCount).map { index in
                PrintFileRecord(
                    id: Self.identifier(index),
                    rootID: rootID,
                    url: folder.appendingPathComponent("file-\(index).3mf"),
                    fileName: "file-\(index).3mf",
                    relativePath: "file-\(index).3mf",
                    fileSize: 1_024,
                    modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
                    // Stands in for the inline preview images schema 1 carried: bytes that leave
                    // the index without any record leaving with them.
                    notes: String(repeating: "x", count: padding)
                )
            }
        )
    }

    /// Stable per index, so "the same records" survives being rewritten.
    private static func identifier(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index))!
    }

    private func write(_ snapshot: LibrarySnapshot, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(snapshot).write(to: url)
    }

    func testTheFirstSaveOfASessionBacksUpWhatWasThere() throws {
        try write(snapshot(recordCount: 5), to: indexURL)

        try LibraryDatabase(fileURL: indexURL).save(snapshot(recordCount: 6))

        XCTAssertEqual(LegacyLibraryLocator.recordCount(at: backupURL), 5)
    }

    func testOnlyTheFirstSaveOfASessionWritesABackup() throws {
        try write(snapshot(recordCount: 5), to: indexURL)
        let database = LibraryDatabase(fileURL: indexURL)

        try database.save(snapshot(recordCount: 6))
        try database.save(snapshot(recordCount: 7))

        // Otherwise the backup tracks the index and stops being a way back.
        XCTAssertEqual(LegacyLibraryLocator.recordCount(at: backupURL), 5)
    }

    func testABackupIsNotReplacedByOneThatHasForgottenRecords() throws {
        try write(snapshot(recordCount: 40), to: backupURL)
        try write(snapshot(recordCount: 3), to: indexURL)

        try LibraryDatabase(fileURL: indexURL).save(snapshot(recordCount: 3))

        XCTAssertEqual(LegacyLibraryLocator.recordCount(at: backupURL), 40)
    }

    func testABackupIsReplacedWhenNothingWouldBeLost() throws {
        try write(snapshot(recordCount: 5), to: backupURL)
        try write(snapshot(recordCount: 9), to: indexURL)

        try LibraryDatabase(fileURL: indexURL).save(snapshot(recordCount: 9))

        XCTAssertEqual(LegacyLibraryLocator.recordCount(at: backupURL), 9)
    }

    func testAnIndexThatShrankWithoutLosingRecordsStillReplacesTheBackup() throws {
        // Bytes are not the test. Moving preview images out of the index into the content-addressed
        // store took a real library from 114 MB to 3 MB without dropping one of its 703 records, and
        // a size rule would freeze the backup at the first migration and never update it again.
        try write(snapshot(recordCount: 12, padding: 4_000), to: backupURL)
        try write(snapshot(recordCount: 12), to: indexURL)
        let backupSize = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: backupURL.path)[.size] as? Int)
        let indexSize = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: indexURL.path)[.size] as? Int)
        XCTAssertLessThan(indexSize, backupSize, "the case only bites while the index is the smaller file")

        try LibraryDatabase(fileURL: indexURL).save(snapshot(recordCount: 12))

        let replaced = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: backupURL.path)[.size] as? Int)
        XCTAssertLessThan(replaced, backupSize)
    }

    func testAnUnreadableBackupProtectsNothingAndIsReplaced() throws {
        try Data("{ not json".utf8).write(to: backupURL)
        try write(snapshot(recordCount: 4), to: indexURL)

        try LibraryDatabase(fileURL: indexURL).save(snapshot(recordCount: 4))

        XCTAssertEqual(LegacyLibraryLocator.recordCount(at: backupURL), 4)
    }

    func testAnUnreadableIndexNeverReplacesAReadableBackup() throws {
        try write(snapshot(recordCount: 40), to: backupURL)
        try Data("{ not json".utf8).write(to: indexURL)

        try LibraryDatabase(fileURL: indexURL).save(snapshot(recordCount: 1))

        XCTAssertEqual(LegacyLibraryLocator.recordCount(at: backupURL), 40)
    }

    func testRefusingToReplaceTheBackupStillSavesTheIndex() throws {
        // Protecting the backup must not turn into refusing the user's edit.
        try write(snapshot(recordCount: 40), to: backupURL)
        try write(snapshot(recordCount: 2), to: indexURL)

        try LibraryDatabase(fileURL: indexURL).save(snapshot(recordCount: 2))

        XCTAssertEqual(LegacyLibraryLocator.recordCount(at: indexURL), 2)
        XCTAssertEqual(LegacyLibraryLocator.recordCount(at: backupURL), 40)
    }
}
