import XCTest
@testable import PrintFileManagerCore

/// Enabling the App Sandbox pointed the app at an empty container and left the user's real library
/// -- 703 files, three folders, every tag and note -- invisible at the old path. From the user's
/// side that is indistinguishable from an update deleting their data. These tests pin the decision
/// that prevents it, including the ways it must refuse to act.
final class LegacyLibraryLocatorTests: XCTestCase {
    private let current = URL(fileURLWithPath: "/container/Print File Manager/library-index.json")
    private let legacy = URL(fileURLWithPath: "/home/Library/Application Support/Print File Manager")
    private var legacyIndex: URL { legacy.appendingPathComponent("library-index.json") }

    private func locator(
        _ contents: [URL: LegacyLibraryLocator.Content],
        settled: Bool = false
    ) -> LegacyLibraryLocator {
        LegacyLibraryLocator(
            content: { contents[$0] ?? .absent },
            hasSettledAdoption: { settled }
        )
    }

    func testAdoptsALegacyLibraryWhenTheCurrentOneIsAbsent() {
        let subject = locator([legacyIndex: .populated])

        XCTAssertEqual(subject.outcome(currentIndex: current, legacyFolder: legacy), .adopt(from: legacy))
    }

    func testAdoptsWhenTheCurrentIndexExistsButIsTheEmptyOneWrittenOnFirstLaunch() {
        // This is the real case. The sandboxed app starts, finds nothing, and writes an empty
        // index. Treating that as "already has data" would strand the user's library forever.
        let subject = locator([current: .empty, legacyIndex: .populated])

        XCTAssertEqual(subject.outcome(currentIndex: current, legacyFolder: legacy), .adopt(from: legacy))
    }

    func testNeverOverwritesACurrentLibraryThatHasContent() {
        let subject = locator([current: .populated, legacyIndex: .populated])

        XCTAssertEqual(subject.outcome(currentIndex: current, legacyFolder: legacy), .nothingToAdopt)
    }

    func testACurrentIndexThatCannotBeDecodedIsNeverReplaced() {
        // Failing closed. An index that will not decode may still hold every tag and note the
        // user has; the load path quarantines it for recovery, and adopting over it would not.
        let subject = locator([current: .unreadable, legacyIndex: .populated])

        XCTAssertEqual(subject.outcome(currentIndex: current, legacyFolder: legacy), .nothingToAdopt)
    }

    func testAsksTheUserWhenTheLegacyLibraryCannotBeRead() {
        // A path outside the container is exactly what the sandbox denies. Silently reporting
        // "nothing to adopt" there would hide the user's data from them.
        let subject = locator([legacyIndex: .unreadable])

        XCTAssertEqual(
            subject.outcome(currentIndex: current, legacyFolder: legacy),
            .needsUserConsent(suggested: legacy)
        )
    }

    func testIgnoresALegacyLibraryThatIsItselfEmpty() {
        let subject = locator([legacyIndex: .empty])

        XCTAssertEqual(subject.outcome(currentIndex: current, legacyFolder: legacy), .nothingToAdopt)
    }

    func testDoesNothingWhenThereIsNoLegacyLibraryAtAll() {
        XCTAssertEqual(locator([:]).outcome(currentIndex: current, legacyFolder: legacy), .nothingToAdopt)
    }

    func testASettledAdoptionIsNeverReconsidered() {        // The legacy folder is copied rather than moved, so it keeps looking adoptable forever.
        // Re-deciding on every launch is what would return a library the user chose to discard.
        let subject = locator([legacyIndex: .populated], settled: true)

        XCTAssertEqual(subject.outcome(currentIndex: current, legacyFolder: legacy), .nothingToAdopt)
    }

    func testAnIndexIsNeverAdoptedOntoItself() {
        // A build that is not sandboxed resolves Application Support to the legacy folder, so both
        // paths name the same file. That is not a migration, and treating it as one would run a
        // copy-and-replace over the only copy there is.
        let sameIndex = legacy.appendingPathComponent("library-index.json")
        let subject = locator([sameIndex: .populated])

        XCTAssertEqual(subject.outcome(currentIndex: sameIndex, legacyFolder: legacy), .nothingToAdopt)
    }

    func testTheCurrentIndexIsNotReadWhenThereIsNoLegacyLibrary() {
        // The steady state on every launch forever after: it must not cost a read of a library
        // that can run to a hundred megabytes.
        var readURLs: [URL] = []
        let subject = LegacyLibraryLocator(content: { url in
            readURLs.append(url)
            return .absent
        })

        _ = subject.outcome(currentIndex: current, legacyFolder: legacy)

        XCTAssertEqual(readURLs, [legacyIndex])
    }

    func testTheRealHomeIsResolvedIndependentlyOfTheSandboxContainer() {
        // Inside a sandbox NSHomeDirectory() is the container, so looking for the old library
        // relative to it would always search inside the container and always find nothing.
        let real = LegacyLibraryLocator.realHomeDirectory().path
        XCTAssertFalse(real.contains("/Library/Containers/"), "resolved \(real)")
        XCTAssertTrue(real.hasPrefix("/"))
    }

    func testTheLegacyFolderIsTheOneTheAppUsedBeforeSandboxing() {
        let folder = LegacyLibraryLocator.legacyFolder(realHome: URL(fileURLWithPath: "/home"))

        XCTAssertEqual(folder.path, "/home/Library/Application Support/Print File Manager")
    }
}

/// Exercises the locator against a real filesystem laid out exactly as the failure looked on the
/// machine where it happened: an empty container index beside a populated pre-sandbox library.
final class LegacyLibraryLocatorLiveTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testTheRealFilesystemCaseThatWasMissedInProduction() throws {
        let container = root.appendingPathComponent("Container/Print File Manager", isDirectory: true)
        let legacy = root.appendingPathComponent("Home/Library/Application Support/Print File Manager", isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)

        try LegacyLibraryFixture.writeIndex(recordCount: 0, to: container.appendingPathComponent("library-index.json"))
        try LegacyLibraryFixture.writeIndex(recordCount: 703, to: legacy.appendingPathComponent("library-index.json"))

        XCTAssertEqual(
            LegacyLibraryLocator.live().outcome(
                currentIndex: container.appendingPathComponent("library-index.json"),
                legacyFolder: legacy
            ),
            .adopt(from: legacy)
        )
    }

    func testASmallButRealLibraryIsNotMistakenForAnEmptyOne() throws {
        // The bug this replaced: "has content" was decided by byte size against a 4 KB ceiling.
        // A handful of records encodes to well under that, so a real library of a few files was
        // deleted and overwritten by the legacy one.
        let currentIndex = root.appendingPathComponent("current.json")
        let legacy = root.appendingPathComponent("Legacy", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try LegacyLibraryFixture.writeIndex(recordCount: 3, to: currentIndex)
        try LegacyLibraryFixture.writeIndex(recordCount: 703, to: legacy.appendingPathComponent("library-index.json"))

        let size = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: currentIndex.path)[.size] as? Int)
        XCTAssertLessThan(size, 4_096, "the case only bites while the index is under the old ceiling")
        XCTAssertEqual(
            LegacyLibraryLocator.live().outcome(currentIndex: currentIndex, legacyFolder: legacy),
            .nothingToAdopt
        )
    }

    func testAnEmptyLibraryWithSeveralAuthorisedFoldersIsStillEmpty() throws {
        // The mirror image: a security-scoped bookmark is around 900 bytes, so an index holding no
        // records at all could clear the old ceiling and suppress a migration that was due.
        let currentIndex = root.appendingPathComponent("current.json")
        let legacy = root.appendingPathComponent("Legacy", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)

        let snapshot = LibrarySnapshot(
            roots: (0..<4).map { index in
                LibraryRoot(
                    url: self.root.appendingPathComponent("folder-\(index)"),
                    securityScopedBookmark: Data(repeating: 0x41, count: 900)
                )
            },
            records: []
        )
        try LegacyLibraryFixture.encoder().encode(snapshot).write(to: currentIndex)
        try LegacyLibraryFixture.writeIndex(recordCount: 703, to: legacy.appendingPathComponent("library-index.json"))

        let size = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: currentIndex.path)[.size] as? Int)
        XCTAssertGreaterThan(size, 4_096, "the case only bites while the index is over the old ceiling")
        XCTAssertEqual(
            LegacyLibraryLocator.live().outcome(currentIndex: currentIndex, legacyFolder: legacy),
            .adopt(from: legacy)
        )
    }

    func testAnUnreadableCurrentIndexIsLeftAloneRatherThanReplaced() throws {
        let currentIndex = root.appendingPathComponent("current.json")
        let legacy = root.appendingPathComponent("Legacy", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: currentIndex)
        try LegacyLibraryFixture.writeIndex(recordCount: 703, to: legacy.appendingPathComponent("library-index.json"))

        XCTAssertEqual(
            LegacyLibraryLocator.live().outcome(currentIndex: currentIndex, legacyFolder: legacy),
            .nothingToAdopt
        )
    }

    func testAnUnreadableLegacyIndexAsksForConsentRatherThanFailingSilently() throws {
        let legacy = root.appendingPathComponent("Legacy", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        let legacyIndex = legacy.appendingPathComponent("library-index.json")
        try LegacyLibraryFixture.writeIndex(recordCount: 703, to: legacyIndex)
        // Standing in for the sandbox denial, which cannot be produced inside a test process.
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: legacyIndex.path)

        let outcome = LegacyLibraryLocator.live().outcome(
            currentIndex: root.appendingPathComponent("absent.json"),
            legacyFolder: legacy
        )

        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: legacyIndex.path)
        XCTAssertEqual(outcome, .needsUserConsent(suggested: legacy))
    }
}

final class LegacyAdoptionLedgerTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "LegacyAdoptionLedgerTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    func testAnUnsettledLedgerLetsTheMigrationRun() {
        XCTAssertFalse(LegacyAdoptionLedger(defaults: defaults).isSettled)
    }

    func testADeclinedAdoptionSurvivesIntoTheNextLaunch() {
        LegacyAdoptionLedger(defaults: defaults).settle(.declined)

        // A second ledger stands in for the next launch reading the same defaults.
        let next = LegacyAdoptionLedger(defaults: defaults)
        XCTAssertTrue(next.isSettled)
        XCTAssertEqual(next.resolution, .declined)
    }

    func testAnAdoptedLibraryIsRecordedAsSuch() {
        LegacyAdoptionLedger(defaults: defaults).settle(.adopted)

        XCTAssertEqual(LegacyAdoptionLedger(defaults: defaults).resolution, .adopted)
    }
}

/// Writes indexes the way the app writes them, so a test measures the real encoded shape rather
/// than a hand-written approximation of it.
enum LegacyLibraryFixture {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    @discardableResult
    static func writeIndex(recordCount: Int, to url: URL) throws -> LibrarySnapshot {
        let folder = url.deletingLastPathComponent()
        let rootID = UUID()
        let snapshot = LibrarySnapshot(
            roots: [LibraryRoot(id: rootID, url: folder)],
            records: (0..<recordCount).map { index in
                PrintFileRecord(
                    rootID: rootID,
                    url: folder.appendingPathComponent("file-\(index).3mf"),
                    fileName: "file-\(index).3mf",
                    relativePath: "file-\(index).3mf",
                    fileSize: 1_024,
                    modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
                    indexingStatus: .indexed
                )
            }
        )
        try encoder().encode(snapshot).write(to: url)
        return snapshot
    }
}
