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
    /// What a library index at a given path amounts to.
    public enum Content: Equatable, Sendable {
        case absent
        /// Decoded, and holds no records. The app writes one of these on first launch, before
        /// anything has been scanned.
        case empty
        case populated
        /// Exists, but could not be read or decoded, so what it holds is unknown.
        case unreadable
    }

    /// What the app should do at startup.
    public enum Outcome: Equatable, Sendable {
        /// Nothing to do: the current library already has content, or no legacy library exists.
        case nothingToAdopt
        /// A legacy library exists and the current one is empty. Adopt it from this folder.
        case adopt(from: URL)
        /// A legacy library is known to exist but could not be read, which is what the sandbox
        /// does to a path outside the container. The user has to point at it themselves.
        case needsUserConsent(suggested: URL)
    }

    public static let indexFileName = "library-index.json"

    private let content: (URL) -> Content
    private let hasSettledAdoption: () -> Bool

    public init(
        content: @escaping (URL) -> Content,
        hasSettledAdoption: @escaping () -> Bool = { false }
    ) {
        self.content = content
        self.hasSettledAdoption = hasSettledAdoption
    }

    /// The real home directory, which inside a sandbox is *not* what `NSHomeDirectory()` returns.
    public static func realHomeDirectory() -> URL {
        guard let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir else {
            return URL(fileURLWithPath: NSHomeDirectory())
        }
        return URL(fileURLWithPath: String(cString: directory))
    }

    /// Where the library lived before the app was sandboxed.
    ///
    /// The default home is redirected along with the support directory, so a process that has been
    /// pointed away from the real library cannot reach it through this door instead.
    public static func legacyFolder(realHome: URL = ApplicationSupportLocation.legacyHomeDirectory()) -> URL {
        realHome
            .appendingPathComponent("Library/Application Support/Print File Manager", isDirectory: true)
    }

    /// - Parameters:
    ///   - currentIndex: the index the app is about to use, inside the container.
    ///   - legacyFolder: where a pre-sandbox library would be.
    public func outcome(currentIndex: URL, legacyFolder: URL) -> Outcome {
        // Adoption copies rather than moves, so the legacy folder keeps looking adoptable on
        // every subsequent launch. Without a record of the decision, a user who chose to start
        // fresh finds the old library back the next time they open the app.
        guard !hasSettledAdoption() else { return .nothingToAdopt }

        let legacyIndex = legacyFolder.appendingPathComponent(Self.indexFileName)

        // A non-sandboxed build resolves Application Support to the legacy folder itself, so both
        // paths name the same file. Adopting an index onto itself is not a migration, and the
        // copy-then-commit would be operating on the only copy there is.
        guard legacyIndex.standardizedFileURL != currentIndex.standardizedFileURL else {
            return .nothingToAdopt
        }

        let legacy = content(legacyIndex)
        // Asked first because it is a single stat in the case that holds forever after: no
        // legacy library, nothing to decide, and no reason to read the current index at all.
        guard legacy != .absent, legacy != .empty else { return .nothingToAdopt }

        switch content(currentIndex) {
        case .populated:
            return .nothingToAdopt
        case .unreadable:
            // An index that will not decode may still hold every tag and note the user has.
            // The load path quarantines it for recovery; overwriting it here would not.
            return .nothingToAdopt
        case .absent, .empty:
            break
        }

        return legacy == .populated ? .adopt(from: legacyFolder) : .needsUserConsent(suggested: legacyFolder)
    }
}

extension LegacyLibraryLocator {
    /// The real filesystem. Split out so tests never touch one.
    public static func live(ledger: LegacyAdoptionLedger = LegacyAdoptionLedger()) -> LegacyLibraryLocator {
        LegacyLibraryLocator(
            content: { contentOfIndex(at: $0) },
            hasSettledAdoption: { ledger.isSettled }
        )
    }

    /// Reads an index far enough to answer whether it holds any records, and no further.
    ///
    /// Byte size cannot answer this. An empty index is around 84 bytes, one record around 530,
    /// and a single security-scoped bookmark is around 900 -- so any threshold that clears a
    /// bookmarked empty library also clears a library with several real files in it, and
    /// adopting over one of those destroys it.
    public static func contentOfIndex(at url: URL) -> Content {
        guard FileManager.default.fileExists(atPath: url.path) else { return .absent }
        guard let count = recordCount(at: url) else { return .unreadable }
        return count == 0 ? .empty : .populated
    }

    /// How many records an index holds, or nil when it could not be read or decoded.
    ///
    /// Decoding the full `LibrarySnapshot` would reject an index this build cannot represent, and
    /// would build the whole object graph of a library that can run to a hundred megabytes. Only
    /// the number of records is needed, so only that is decoded.
    public static func recordCount(at url: URL) -> Int? {
        struct IndexShape: Decodable {
            /// Decodes any record shape, present or future, into nothing.
            struct AnyRecord: Decodable {}
            let records: [AnyRecord]
        }

        // Reading the bytes is also the readability probe: a sandbox denial fails the open,
        // which is what tells an inaccessible legacy library from an empty one.
        guard let data = try? Data(contentsOf: url),
              let shape = try? JSONDecoder().decode(IndexShape.self, from: data) else {
            return nil
        }
        return shape.records.count
    }

    /// Which records an index holds, or nil when it could not be read or decoded.
    ///
    /// Used to decide whether one index carries everything another one did. Only the identifiers
    /// are decoded, so this does not depend on the record shape of the build that wrote the file.
    public static func recordIdentifiers(at url: URL) -> Set<String>? {
        struct IndexShape: Decodable {
            struct Identified: Decodable { let id: String }
            let records: [Identified]
        }

        guard let data = try? Data(contentsOf: url),
              let shape = try? JSONDecoder().decode(IndexShape.self, from: data) else {
            return nil
        }
        return Set(shape.records.map(\.id))
    }
}

/// Remembers that the one-time adoption of a pre-sandbox library has been settled.
///
/// The doc comment on the adoption path said "once" while nothing enforced it: the decision was
/// re-derived from the filesystem on every launch, and the legacy folder is copied rather than
/// moved, so it never stopped looking adoptable.
/// `@unchecked` only because `UserDefaults` is not annotated `Sendable` while being documented as
/// thread-safe; the ledger itself holds nothing else.
public struct LegacyAdoptionLedger: @unchecked Sendable {
    public enum Resolution: String, Sendable {
        /// The legacy library was copied into the container and the copy loaded.
        case adopted
        /// The user chose a library that is not the legacy one, and must not have it returned.
        case declined
    }

    private static let key = "legacyLibrary.adoptionResolution"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var resolution: Resolution? {
        defaults.string(forKey: Self.key).flatMap(Resolution.init(rawValue:))
    }

    public var isSettled: Bool {
        resolution != nil
    }

    public func settle(_ resolution: Resolution) {
        defaults.set(resolution.rawValue, forKey: Self.key)
    }
}
