import Foundation

/// Keeps sandboxed access to the folders the user picked.
///
/// Under the App Sandbox a stored path grants nothing after relaunch — only a security-scoped
/// bookmark resolved back to a URL does. This centralises creating those bookmarks, resolving them
/// at launch, and balancing the start/stop access calls so scopes are not leaked.
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
    public func beginAccess(to root: LibraryRoot) -> ResolvedRoot? {
        stopAccess(rootID: root.id)

        guard let bookmark = root.securityScopedBookmark else {
            // No bookmark: either a library from before sandboxing, or a non-sandboxed build.
            return ResolvedRoot(url: root.url, refreshedBookmark: nil)
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

    isolated deinit {
        stopAll()
    }
}
