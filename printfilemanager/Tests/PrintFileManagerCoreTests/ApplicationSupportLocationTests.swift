import XCTest
@testable import PrintFileManagerCore

/// The app-hosted test suite launches the real app, which loads a library before any test runs.
/// Unsandboxed, that resolved to the user's own pre-sandbox library and rewrote it. These pin the
/// rule that stops it, from the side of the code that decides.
final class ApplicationSupportLocationTests: XCTestCase {

    func testATestProcessIsRecognisedAsOne() {
        // Everything else here depends on this being true, and it has to stay true across Xcode
        // versions that rename the environment keys — hence the runtime check behind them.
        XCTAssertTrue(ApplicationSupportLocation.isHostingTests)
    }

    func testATestProcessIsPointedAwayFromTheRealLibrary() throws {
        XCTAssertTrue(ApplicationSupportLocation.isRedirected)

        let resolved = try ApplicationSupportLocation.supportDirectory().standardizedFileURL.path
        let real = try XCTUnwrap(ApplicationSupportLocation.realSupportDirectory()).standardizedFileURL.path

        XCTAssertNotEqual(resolved, real)
        XCTAssertFalse(resolved.hasPrefix(real + "/"))
    }

    func testTheSearchForAPreSandboxLibraryIsRedirectedWithIt() {
        let legacy = LegacyLibraryLocator.legacyFolder().standardizedFileURL.path
        let realHome = LegacyLibraryLocator.realHomeDirectory().standardizedFileURL.path

        XCTAssertFalse(legacy.hasPrefix(realHome + "/Library/Application Support"))
    }

    func testTheRedirectedDirectoryIsUsable() throws {
        // A location that cannot be written to would send the app to its volatile fallback and
        // report the index as impermanent, which is a different failure with the same look.
        let directory = try ApplicationSupportLocation.supportDirectory()
        let probe = directory.appendingPathComponent("probe-\(UUID().uuidString)")

        XCTAssertNoThrow(try Data("x".utf8).write(to: probe))
        try? FileManager.default.removeItem(at: probe)
    }

    func testTheSameAnswerIsGivenEveryTime() throws {
        // The index and the preview store resolve separately. If the answer moved between calls
        // they would end up in different directories.
        let first = try ApplicationSupportLocation.supportDirectory()
        let second = try ApplicationSupportLocation.supportDirectory()

        XCTAssertEqual(first.standardizedFileURL, second.standardizedFileURL)
    }

    func testTheRealLocationIsStillNameableSoItCanBeAvoided() throws {
        let real = try XCTUnwrap(ApplicationSupportLocation.realSupportDirectory())

        XCTAssertEqual(real.lastPathComponent, ApplicationSupportLocation.folderName)
        XCTAssertTrue(real.path.contains("Application Support"))
    }
}
