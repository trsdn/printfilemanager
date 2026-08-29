import Foundation

/// Keeps sandboxed access to the folders the user picked.
///
/// Under the App Sandbox a stored path grants nothing after relaunch — only a security-scoped
/// bookmark resolved back to a URL does. This centralises creating those bookmarks, resolving them
/// at launch, and balancing the start/stop access calls so scopes are not leaked.
///
/// Scopes are released explicitly through `stopAccess(rootID:)` and `stopAll()` rather than in
/// `deinit`: releasing MainActor-isolated state from a deallocator needs an isolated `deinit`,
/// which is still behind an experimental flag on some Xcode versions. The coordinator lives as
/// long as the view model does, so the process exiting is what ends the last scope anyway.
@MainActor
public final class SecurityScopedAccessCoordinator {
    public init() {}

    private var activeURLs: [UUID: URL] = [:]

    /// Creates a bookmark for a folder the user has just chosen.
    public nonisolated static func makeBookmark(for url: URL) -> Data? {
        try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    public struct ResolvedRoot {
        public let url: URL
        public let refreshedBookmark: Data?
    }

    /// Resolves a stored bookmark and begins accessing it.
    ///
    /// - Returns: the resolved URL, plus a replacement bookmark when the old one went stale
    ///   (which happens when the user moves or renames the folder).
    @discardableResult
    /// Whether the folder can actually be listed, which under the App Sandbox is the only way to
    /// tell an accessible path from an inaccessible one. `isReadableFile` reports the metadata
    /// answer and can disagree with what an actual read is allowed to do.
    nonisolated static func isDirectoryReadable(_ url: URL) -> Bool {
        (try? FileManager.default.contentsOfDirectory(atPath: url.path)) != nil
    }

    public func beginAccess(to root: LibraryRoot) -> ResolvedRoot? {
        stopAccess(rootID: root.id)

        guard let bookmark = root.securityScopedBookmark else {
            // No bookmark: either a library carried over from before sandboxing, or a
            // non-sandboxed build. Those two look identical here and need opposite answers, so
            // the folder is asked rather than assumed.
            //
            // Reporting success without checking is what made a migrated library look healthy in
            // the sidebar while every file under it read as missing -- the user saw a folder with
            // a file count and no hint that the app could not open a single one of them.
            return Self.isDirectoryReadable(root.url)
                ? ResolvedRoot(url: root.url, refreshedBookmark: nil)
                : nil
        }

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }

        guard url.startAccessingSecurityScopedResource() else { return nil }
        activeURLs[root.id] = url

        return ResolvedRoot(
            url: url,
            refreshedBookmark: isStale ? Self.makeBookmark(for: url) : nil
        )
    }

    public func stopAccess(rootID: UUID) {
        guard let url = activeURLs.removeValue(forKey: rootID) else { return }
        url.stopAccessingSecurityScopedResource()
    }

    public func stopAll() {
        for url in activeURLs.values {
            url.stopAccessingSecurityScopedResource()
        }
        activeURLs.removeAll()
    }
}
