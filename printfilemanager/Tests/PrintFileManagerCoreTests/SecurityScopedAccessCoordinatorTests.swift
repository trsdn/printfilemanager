import XCTest
@testable import PrintFileManagerCore

/// Under the App Sandbox a folder that cannot be listed is indistinguishable from one that can,
/// unless it is asked. Reporting availability without asking is what left a migrated library
/// showing a healthy file count in the sidebar while every file under it read as missing.
final class SecurityScopedAccessCoordinatorTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SecurityScopedAccessCoordinatorTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        try? FileManager.default.removeItem(at: root)
    }

    func testAListableFolderIsReadable() throws {
        try Data("x".utf8).write(to: root.appendingPathComponent("a.3mf"))

        XCTAssertTrue(SecurityScopedAccessCoordinator.isDirectoryReadable(root))
    }

    func testAnEmptyFolderIsReadable() {
        // An empty listing and a refused one both come back as "no entries", and only errno tells
        // them apart. Confusing the two would mark every newly created folder inaccessible.
        XCTAssertTrue(SecurityScopedAccessCoordinator.isDirectoryReadable(root))
    }

    func testAFolderThatCannotBeListedIsNotReadable() throws {
        // Standing in for the sandbox denial, which cannot be produced inside a test process.
        try Data("x".utf8).write(to: root.appendingPathComponent("a.3mf"))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: root.path)

        XCTAssertFalse(SecurityScopedAccessCoordinator.isDirectoryReadable(root))
    }

    func testAFolderThatIsNotThereIsNotReadable() {
        XCTAssertFalse(SecurityScopedAccessCoordinator.isDirectoryReadable(root.appendingPathComponent("absent")))
    }

    func testAFileIsNotAReadableDirectory() throws {
        let file = root.appendingPathComponent("a.3mf")
        try Data("x".utf8).write(to: file)

        XCTAssertFalse(SecurityScopedAccessCoordinator.isDirectoryReadable(file))
    }

    func testALargeFolderStillAnswersFromItsFirstEntry() throws {
        // The reason the probe stopped using `contentsOfDirectory`: it runs once per unbookmarked
        // root at launch, and collecting every child name is a long stall on a network volume for
        // an answer the first entry already gives.
        for index in 0..<2_000 {
            try Data("x".utf8).write(to: root.appendingPathComponent("file-\(index).3mf"))
        }

        XCTAssertTrue(SecurityScopedAccessCoordinator.isDirectoryReadable(root))
    }
}
