import PrintFileManagerCore
import XCTest
@testable import PrintFileManager

/// Fails if a test run could touch the user's real library.
///
/// This is not hypothetical. The app-hosted suite launches the real app as its test host; the host
/// builds `LibraryViewModel` from `@StateObject` and loads a library before any test runs, and
/// built without entitlements it is not sandboxed, so Application Support resolved to the user's
/// real `~/Library/Application Support/Print File Manager`. A run of this suite read a 703-file
/// pre-sandbox library, migrated it from schema 1 to 2 and wrote it back.
///
/// It cost nothing that time — that migration moves preview images into the content-addressed
/// store rather than discarding them, and every image was verified still readable afterwards — but
/// nothing about the arrangement guaranteed that. These assertions are what makes the guarantee.
@MainActor
final class ApplicationSupportIsolationTests: XCTestCase {

    /// Resolved from the password database rather than from the code under test, so this cannot
    /// agree with a bug by sharing it.
    private var realSupportDirectory: URL {
        let home: URL
        if let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir {
            home = URL(fileURLWithPath: String(cString: directory))
        } else {
            home = URL(fileURLWithPath: NSHomeDirectory())
        }
        return home.appendingPathComponent("Library/Application Support/Print File Manager", isDirectory: true)
    }

    private func assertOutsideTheRealLibrary(_ url: URL, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        let real = realSupportDirectory.standardizedFileURL.path
        let candidate = url.standardizedFileURL.path
        XCTAssertFalse(
            candidate == real || candidate.hasPrefix(real + "/"),
            "\(what) resolves inside the user's real library at \(candidate)",
            file: file,
            line: line
        )
    }

    func testTheProcessKnowsItMustNotUseTheRealLibrary() {
        XCTAssertTrue(ApplicationSupportLocation.isHostingTests)
        XCTAssertTrue(ApplicationSupportLocation.isRedirected)
    }

    func testTheLibraryIndexIsNotTheUsersOwn() throws {
        assertOutsideTheRealLibrary(try LibraryDatabase.applicationSupport().fileURL, "the library index")
    }

    func testThePreviewStoreIsNotTheUsersOwn() throws {
        assertOutsideTheRealLibrary(try ThumbnailStore.applicationSupport().directoryURL, "the preview store")
    }

    func testTheIndexAndItsPreviewsStayTogether() throws {
        // Redirecting one and not the other would write previews the index cannot find, and would
        // put half a library in the user's real folder.
        let indexFolder = try LibraryDatabase.applicationSupport().fileURL.deletingLastPathComponent()
        let previews = try ThumbnailStore.applicationSupport().directoryURL

        XCTAssertEqual(previews.deletingLastPathComponent().standardizedFileURL, indexFolder.standardizedFileURL)
    }

    func testTheSearchForAPreSandboxLibraryIsRedirectedToo() {
        // Otherwise a redirected process still finds the user's real pre-sandbox library and
        // copies it into the throwaway one — reading their data for no reason.
        assertOutsideTheRealLibrary(LegacyLibraryLocator.legacyFolder(), "the pre-sandbox library search")
    }

    func testHostingTestsInsideTheShippingContainerIsRefused() {
        // A container is claimed in dyld, before any code here runs, so this cannot prevent the
        // claim -- only report it. It is worth reporting: an ad-hoc signed test host carrying the
        // shipping entitlements claims the shipping container, and `secinitd` answers that with a
        // consent prompt on a serial per-bundle-identifier queue. If nothing renders the prompt --
        // a sleeping display is enough -- the daemon blocks on it and every later launch of the
        // real app queues behind it until `secinitd` is restarted. That happened.
        //
        // `scripts/ci-local.sh` builds with CODE_SIGNING_ALLOWED=NO, which is what keeps the test
        // host out of the container. This fails if someone overrides that.
        let container = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"]

        XCTAssertNotEqual(
            container,
            "com.printfilemanager.PrintFileManager",
            "the test host is running inside the shipping app's sandbox container; build tests with CODE_SIGNING_ALLOWED=NO"
        )
    }

    func testTheAppsOwnViewModelWritesSomewhereDisposable() throws {
        // The host app builds this before any test runs, so this is the object that actually
        // touched the real library.
        let viewModel = LibraryViewModel()

        assertOutsideTheRealLibrary(viewModel.storageLocations.index, "the running app's index")
        assertOutsideTheRealLibrary(viewModel.storageLocations.thumbnails, "the running app's previews")
    }

    func testTheRealLibraryIsNotReadDuringATestRun() async throws {
        // The read itself is the hazard: loading is what migrates, and migrating is what writes.
        let real = realSupportDirectory.appendingPathComponent("library-index.json")
        guard FileManager.default.fileExists(atPath: real.path) else {
            throw XCTSkip("no real library on this machine to be protected from")
        }

        let before = try FileManager.default.attributesOfItem(atPath: real.path)
        await LibraryViewModel().load()
        let after = try FileManager.default.attributesOfItem(atPath: real.path)

        XCTAssertEqual(before[.modificationDate] as? Date, after[.modificationDate] as? Date)
        XCTAssertEqual(before[.size] as? Int, after[.size] as? Int)
    }
}
