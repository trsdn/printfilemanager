import Foundation

/// Decides where this app keeps its own files, and refuses to answer with the user's real library
/// when the process has no business writing to it.
///
/// The app-hosted test suite launches the real app as its test host. The app builds its view model
/// from `@StateObject` before any test runs, and that view model resolves Application Support and
/// loads whatever it finds. Under `xcodebuild test` the host is built without entitlements, so it
/// is not sandboxed and `.applicationSupportDirectory` resolves to the user's real
/// `~/Library/Application Support/Print File Manager` — the pre-sandbox library, with every tag,
/// note and print history in it. A test run then reads it, migrates it and writes it back.
///
/// That happened. It was survivable only by luck: the migration it performed was schema 1 to 2,
/// which moves preview images into a content-addressed store rather than discarding them, and the
/// images were already extracted so nothing had to be rewritten. A run that saved an empty
/// snapshot, or one interrupted mid-write, would not have been survivable.
///
/// So the location is no longer taken on trust. A process hosting tests is given a throwaway
/// directory, and it cannot opt back in.
public enum ApplicationSupportLocation {
    /// Points the app at a different Application Support root. Set by the test scheme, and usable
    /// by hand to run against a disposable copy of a library.
    public static let overrideEnvironmentKey = "PFM_APPLICATION_SUPPORT"

    public static let folderName = "Print File Manager"

    /// Whether the real library is being deliberately avoided.
    public static var isRedirected: Bool {
        redirectRoot != nil
    }

    /// Whether a test bundle is loaded into this process.
    ///
    /// Checked by environment *and* by the runtime: the environment keys have changed across Xcode
    /// versions, and a wrong answer here writes to the user's library.
    public static var isHostingTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        let keys = ["XCTestConfigurationFilePath", "XCTestBundlePath", "XCTestSessionIdentifier"]
        if keys.contains(where: { environment[$0]?.isEmpty == false }) { return true }
        return NSClassFromString("XCTestCase") != nil
    }

    /// Where the library index and preview store live.
    public static func supportDirectory() throws -> URL {
        let base: URL
        if let redirectRoot {
            base = redirectRoot
        } else {
            base = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        }

        let folderURL = base.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        return folderURL
    }

    /// The home directory to search for a library left behind before the app was sandboxed.
    ///
    /// Redirected alongside the support directory. Otherwise a redirected process would still find
    /// the user's real pre-sandbox library and copy it into the throwaway one, which is reading
    /// their data for no reason and is the failure this type exists to prevent.
    public static func legacyHomeDirectory() -> URL {
        redirectRoot.map { $0.appendingPathComponent("PreSandboxHome", isDirectory: true) }
            ?? LegacyLibraryLocator.realHomeDirectory()
    }

    /// The real location, regardless of any redirect. Only for saying what is being avoided.
    public static func realSupportDirectory() -> URL? {
        try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ).appendingPathComponent(folderName, isDirectory: true)
    }

    private static var redirectRoot: URL? {
        if let path = ProcessInfo.processInfo.environment[overrideEnvironmentKey], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        // The scheme sets the variable above, but a scheme is a thing someone can forget to copy
        // into a new target. This is the part that cannot be forgotten.
        return isHostingTests ? testRoot : nil
    }

    /// One throwaway root per test process, so an index and its previews still agree with each
    /// other and two concurrent runs cannot collide.
    private static let testRoot: URL = FileManager.default.temporaryDirectory
        .appendingPathComponent("PrintFileManager-TestSupport", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
}
