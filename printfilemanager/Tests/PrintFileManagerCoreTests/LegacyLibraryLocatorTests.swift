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
        existing: Set<URL>,
        sizes: [URL: Int],
        readable: Set<URL>
    ) -> LegacyLibraryLocator {
        LegacyLibraryLocator(
            fileExists: { existing.contains($0) },
            isReadable: { readable.contains($0) },
            fileSize: { sizes[$0] }
        )
    }

    func testAdoptsALegacyLibraryWhenTheCurrentOneIsAbsent() {
        let subject = locator(
            existing: [legacyIndex],
            sizes: [legacyIndex: 113_973_669],
            readable: [legacyIndex]
        )

        XCTAssertEqual(subject.outcome(currentIndex: current, legacyFolder: legacy), .adopt(from: legacy))
    }

    func testAdoptsWhenTheCurrentIndexExistsButIsTheEmptyOneWrittenOnFirstLaunch() {
        // This is the real case. The sandboxed app starts, finds nothing, and writes an empty
        // index. Treating that as "already has data" would strand the user's library forever.
        let subject = locator(
            existing: [current, legacyIndex],
            sizes: [current: 220, legacyIndex: 113_973_669],
            readable: [legacyIndex]
        )

        XCTAssertEqual(subject.outcome(currentIndex: current, legacyFolder: legacy), .adopt(from: legacy))
    }

    func testNeverOverwritesACurrentLibraryThatHasContent() {
        let subject = locator(
            existing: [current, legacyIndex],
            sizes: [current: 3_000_000, legacyIndex: 113_973_669],
            readable: [legacyIndex]
        )

        XCTAssertEqual(subject.outcome(currentIndex: current, legacyFolder: legacy), .nothingToAdopt)
    }

    func testAsksTheUserWhenTheLegacyLibraryCannotBeRead() {
        // A path outside the container is exactly what the sandbox denies. Silently reporting
        // "nothing to adopt" there would hide the user's data from them.
        let subject = locator(
            existing: [legacyIndex],
            sizes: [legacyIndex: 113_973_669],
            readable: []
        )

        XCTAssertEqual(
            subject.outcome(currentIndex: current, legacyFolder: legacy),
            .needsUserConsent(suggested: legacy)
        )
    }

    func testIgnoresALegacyLibraryThatIsItselfEmpty() {
        let subject = locator(
            existing: [legacyIndex],
            sizes: [legacyIndex: 220],
            readable: [legacyIndex]
        )

        XCTAssertEqual(subject.outcome(currentIndex: current, legacyFolder: legacy), .nothingToAdopt)
    }

    func testDoesNothingWhenThereIsNoLegacyLibraryAtAll() {
        let subject = locator(existing: [], sizes: [:], readable: [])

        XCTAssertEqual(subject.outcome(currentIndex: current, legacyFolder: legacy), .nothingToAdopt)
    }

    func testAnUnreadableSizeIsTreatedAsNoDataRatherThanAdopted() {
        // If the size cannot be determined, adopting would risk overwriting something with nothing.
        let subject = locator(existing: [legacyIndex], sizes: [:], readable: [legacyIndex])

        XCTAssertEqual(subject.outcome(currentIndex: current, legacyFolder: legacy), .nothingToAdopt)
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

        // What the sandboxed app writes on first launch when it finds nothing.
        let currentIndex = container.appendingPathComponent("library-index.json")
        try Data(#"{"records":[],"roots":[],"schemaVersion":2}"#.utf8).write(to: currentIndex)

        // What the user actually has.
        let legacyIndex = legacy.appendingPathComponent("library-index.json")
        try Data(repeating: 0x20, count: 500_000).write(to: legacyIndex)

        let outcome = LegacyLibraryLocator.live().outcome(currentIndex: currentIndex, legacyFolder: legacy)

        XCTAssertEqual(outcome, .adopt(from: legacy))
    }

    func testAPopulatedCurrentLibraryIsLeftAloneOnARealFilesystem() throws {
        let container = root.appendingPathComponent("Container", isDirectory: true)
        let legacy = root.appendingPathComponent("Legacy", isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)

        let currentIndex = container.appendingPathComponent("library-index.json")
        try Data(repeating: 0x20, count: 500_000).write(to: currentIndex)
        try Data(repeating: 0x20, count: 900_000)
            .write(to: legacy.appendingPathComponent("library-index.json"))

        XCTAssertEqual(
            LegacyLibraryLocator.live().outcome(currentIndex: currentIndex, legacyFolder: legacy),
            .nothingToAdopt
        )
    }

    func testAnUnreadableLegacyIndexAsksForConsentRatherThanFailingSilently() throws {
        let legacy = root.appendingPathComponent("Legacy", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        let legacyIndex = legacy.appendingPathComponent("library-index.json")
        try Data(repeating: 0x20, count: 500_000).write(to: legacyIndex)
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
