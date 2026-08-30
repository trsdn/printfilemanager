import XCTest
@testable import PrintFileManagerCore

/// The migration handles the only copy of a library that cannot be recreated from the user's files
/// -- their tags, notes and print history. These tests pin the property that matters: whatever
/// goes wrong, the user is never left holding less than they started with.
final class LegacyLibraryAdoptionTests: XCTestCase {
    private var root: URL!
    private var legacy: URL!
    private var container: URL!
    private var destinationIndex: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        legacy = root.appendingPathComponent("Legacy", isDirectory: true)
        container = root.appendingPathComponent("Container", isDirectory: true)
        destinationIndex = container.appendingPathComponent("library-index.json")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private var legacyIndex: URL { legacy.appendingPathComponent("library-index.json") }
    private var containerThumbnails: URL { container.appendingPathComponent("Thumbnails", isDirectory: true) }

    private func writeLegacyThumbnail(named name: String = "a.png") throws {
        let folder = legacy.appendingPathComponent("Thumbnails", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("preview".utf8).write(to: folder.appendingPathComponent(name))
    }

    func testAdoptionBringsBackTheIndexAndItsPreviews() throws {
        try LegacyLibraryFixture.writeIndex(recordCount: 703, to: legacyIndex)
        try writeLegacyThumbnail()

        let count = try LegacyLibraryAdoption.perform(from: legacy, toIndex: destinationIndex)

        XCTAssertEqual(count, 703)
        XCTAssertEqual(LegacyLibraryLocator.recordCount(at: destinationIndex), 703)
        XCTAssertTrue(FileManager.default.fileExists(atPath: containerThumbnails.appendingPathComponent("a.png").path))
    }

    func testTheOriginalIsCopiedRatherThanMoved() throws {
        try LegacyLibraryFixture.writeIndex(recordCount: 12, to: legacyIndex)

        try LegacyLibraryAdoption.perform(from: legacy, toIndex: destinationIndex)

        XCTAssertEqual(LegacyLibraryLocator.recordCount(at: legacyIndex), 12)
    }

    func testAFailedCopyLeavesTheExistingIndexExactlyAsItWas() throws {
        // The shape of the bug: the destination was removed first and copied second, so every way
        // the copy could fail -- a denial, a full disk, the source vanishing -- ended with the
        // user holding no index at all.
        let before = Data("{\"records\":[],\"roots\":[],\"schemaVersion\":2}".utf8)
        try before.write(to: destinationIndex)

        XCTAssertThrowsError(try LegacyLibraryAdoption.perform(from: legacy, toIndex: destinationIndex)) { _ in }

        XCTAssertEqual(try Data(contentsOf: destinationIndex), before)
    }

    func testAnIndexThatDoesNotSurviveTheCopyIsNeverCommitted() throws {
        // Readability was previously established by opening the source and reading one byte, which
        // says nothing about the rest of it. Truncated JSON stands in for that.
        try Data("{\"records\": [{\"id\":".utf8).write(to: legacyIndex)
        let before = Data("{\"records\":[],\"roots\":[],\"schemaVersion\":2}".utf8)
        try before.write(to: destinationIndex)

        XCTAssertThrowsError(try LegacyLibraryAdoption.perform(from: legacy, toIndex: destinationIndex)) { error in
            XCTAssertEqual(error as? LegacyLibraryAdoption.Failure, .copyDidNotSurvive)
        }
        XCTAssertEqual(try Data(contentsOf: destinationIndex), before)
    }

    func testAnEmptyLegacyIndexIsRefusedRatherThanCommitted() throws {
        try LegacyLibraryFixture.writeIndex(recordCount: 0, to: legacyIndex)
        try LegacyLibraryFixture.writeIndex(recordCount: 4, to: destinationIndex)

        XCTAssertThrowsError(try LegacyLibraryAdoption.perform(from: legacy, toIndex: destinationIndex)) { error in
            XCTAssertEqual(error as? LegacyLibraryAdoption.Failure, .legacyIndexHasNoRecords)
        }
        XCTAssertEqual(LegacyLibraryLocator.recordCount(at: destinationIndex), 4)
    }

    func testNothingIsLeftBehindWhenTheAdoptionFails() throws {
        XCTAssertThrowsError(try LegacyLibraryAdoption.perform(from: legacy, toIndex: destinationIndex)) { _ in }

        // A half-written staging directory would be indistinguishable from a real library folder
        // to anyone looking, and would accumulate on every launch that failed.
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: container.path)
        XCTAssertEqual(leftovers, [])
    }

    func testPreviewsAreInstalledBeforeTheIndexThatMakesThemVisible() throws {
        // Ordering the other way is what could leave the container holding an index that reports
        // content -- which suppresses this migration for good -- beside previews that never
        // arrived. With previews first, a failure leaves nothing claiming to be a library.
        try LegacyLibraryFixture.writeIndex(recordCount: 5, to: legacyIndex)
        try writeLegacyThumbnail()

        let failing = FailingFileManager(refusingToCommit: destinationIndex)
        XCTAssertThrowsError(
            try LegacyLibraryAdoption.perform(from: legacy, toIndex: destinationIndex, fileManager: failing)
        ) { _ in }

        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationIndex.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: containerThumbnails.appendingPathComponent("a.png").path))
    }

    func testAFailedCommitLeavesTheNextAttemptAbleToFinish() throws {
        try LegacyLibraryFixture.writeIndex(recordCount: 5, to: legacyIndex)
        try writeLegacyThumbnail()

        let failing = FailingFileManager(refusingToCommit: destinationIndex)
        XCTAssertThrowsError(
            try LegacyLibraryAdoption.perform(from: legacy, toIndex: destinationIndex, fileManager: failing)
        ) { _ in }

        XCTAssertEqual(try LegacyLibraryAdoption.perform(from: legacy, toIndex: destinationIndex), 5)
    }

    func testExistingPreviewsAreNotReplaced() throws {
        try LegacyLibraryFixture.writeIndex(recordCount: 5, to: legacyIndex)
        try writeLegacyThumbnail(named: "legacy.png")
        try FileManager.default.createDirectory(at: containerThumbnails, withIntermediateDirectories: true)
        try Data("kept".utf8).write(to: containerThumbnails.appendingPathComponent("existing.png"))

        try LegacyLibraryAdoption.perform(from: legacy, toIndex: destinationIndex)

        XCTAssertTrue(FileManager.default.fileExists(atPath: containerThumbnails.appendingPathComponent("existing.png").path))
    }

    func testAdoptingTwiceIsHarmless() throws {
        try LegacyLibraryFixture.writeIndex(recordCount: 9, to: legacyIndex)
        try writeLegacyThumbnail()

        try LegacyLibraryAdoption.perform(from: legacy, toIndex: destinationIndex)
        let second = try LegacyLibraryAdoption.perform(from: legacy, toIndex: destinationIndex)

        XCTAssertEqual(second, 9)
        XCTAssertEqual(LegacyLibraryLocator.recordCount(at: destinationIndex), 9)
    }
}

/// Stands in for the ways a commit fails on a real machine -- a denial, a full disk -- which cannot
/// be produced inside a test process.
private final class FailingFileManager: FileManager {
    private let refused: URL

    init(refusingToCommit url: URL) {
        refused = url.standardizedFileURL
        super.init()
    }

    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        guard dstURL.standardizedFileURL != refused else {
            throw CocoaError(.fileWriteNoPermission)
        }
        try super.moveItem(at: srcURL, to: dstURL)
    }
}
