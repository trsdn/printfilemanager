import Foundation

/// Finds a library left behind outside the App Sandbox container.
///
/// Enabling the App Sandbox silently moved where this app reads and writes. `FileManager`'s
/// `.applicationSupportDirectory` resolves to the container from that point on, and macOS only
/// migrates existing data into a new container for paths keyed by bundle identifier. This app used
/// a human-readable folder name — `Application Support/Print File Manager` — so nothing was
/// migrated and the app started against an empty index.
///
/// The user does not experience that as a sandbox change. They experience it as their entire
/// library, folders, tags, notes and print history having been deleted by an update. The data is
/// untouched at the old path; the app simply stops being able to see it.
///
/// This type decides whether such a library exists and is worth adopting. It is deliberately free
/// of `FileManager` singletons and of any UI, so the decision can be tested without a sandbox.
public struct LegacyLibraryLocator {
    /// What the app should do at startup.
    public enum Outcome: Equatable {
        /// Nothing to do: the current library already has content, or no legacy library exists.
        case nothingToAdopt
        /// A legacy library exists and the current one is empty. Adopt it from this folder.
        case adopt(from: URL)
        /// A legacy library is known to exist but could not be read, which is what the sandbox
        /// does to a path outside the container. The user has to point at it themselves.
        case needsUserConsent(suggested: URL)
    }

    private let fileExists: (URL) -> Bool
    private let isReadable: (URL) -> Bool
    private let fileSize: (URL) -> Int?

    public init(
        fileExists: @escaping (URL) -> Bool,
        isReadable: @escaping (URL) -> Bool,
        fileSize: @escaping (URL) -> Int?
    ) {
        self.fileExists = fileExists
        self.isReadable = isReadable
        self.fileSize = fileSize
    }

    /// The real home directory, which inside a sandbox is *not* what `NSHomeDirectory()` returns.
    public static func realHomeDirectory() -> URL {
        guard let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir else {
            return URL(fileURLWithPath: NSHomeDirectory())
        }
        return URL(fileURLWithPath: String(cString: directory))
    }

    /// Where the library lived before the app was sandboxed.
    public static func legacyFolder(realHome: URL = realHomeDirectory()) -> URL {
        realHome
            .appendingPathComponent("Library/Application Support/Print File Manager", isDirectory: true)
    }

    /// - Parameters:
    ///   - currentIndex: the index the app is about to use, inside the container.
    ///   - legacyFolder: where a pre-sandbox library would be.
    public func outcome(currentIndex: URL, legacyFolder: URL) -> Outcome {
        let legacyIndex = legacyFolder.appendingPathComponent("library-index.json")

        // Never overwrite a library that already has something in it. An empty file counts as
        // empty: the app writes one on first launch before anything is scanned, and treating that
        // as "already has content" is exactly what would leave the user staring at nothing.
        if fileExists(currentIndex), let size = fileSize(currentIndex), size > Self.emptyIndexCeiling {
            return .nothingToAdopt
        }

        guard fileExists(legacyIndex) else { return .nothingToAdopt }
        guard let legacySize = fileSize(legacyIndex), legacySize > Self.emptyIndexCeiling else {
            return .nothingToAdopt
        }

        return isReadable(legacyIndex) ? .adopt(from: legacyFolder) : .needsUserConsent(suggested: legacyFolder)
    }

    /// A freshly written index of an empty library is a few hundred bytes of JSON scaffolding.
    /// Anything at or below this is treated as carrying no user data.
    static let emptyIndexCeiling = 4_096
}

extension LegacyLibraryLocator {
    /// The real filesystem. Split out so tests never touch one.
    public static func live() -> LegacyLibraryLocator {
        LegacyLibraryLocator(
            fileExists: { FileManager.default.fileExists(atPath: $0.path) },
            isReadable: { url in
                // `isReadableFile` reports the sandbox's answer, but only actually opening the file
                // proves it: a denied read can still be reported as readable by the metadata call.
                guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
                defer { try? handle.close() }
                return (try? handle.read(upToCount: 1)) != nil
            },
            fileSize: { url in
                (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? nil
            }
        )
    }
}
