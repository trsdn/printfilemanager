import CryptoKit
import Foundation

/// Content-addressed store for preview images, kept outside the library index.
///
/// Thumbnails used to live inside `PrintFileRecord` and were therefore base64-encoded into the
/// single JSON index, which made the index enormous (109 MB for ~650 files on a real installation)
/// and meant every mutation rewrote every image. Storing them as separate files keeps the index
/// small, lets previews load lazily, and deduplicates identical images for free — re-downloads of
/// the same model share one file.
public final class ThumbnailStore: Sendable {
    public enum StoreError: Error, Equatable {
        case emptyImageData
    }

    public let directoryURL: URL

    public init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    public static func applicationSupport() throws -> ThumbnailStore {
        let folderURL = try ApplicationSupportLocation.supportDirectory()
            .appendingPathComponent("Thumbnails", isDirectory: true)
        return ThumbnailStore(directoryURL: folderURL)
    }

    /// Writes image data and returns the key used to read it back.
    ///
    /// The key is the SHA-256 of the contents, so storing the same image twice is a no-op.
    @discardableResult
    public func store(_ data: Data) throws -> String {
        guard !data.isEmpty else { throw StoreError.emptyImageData }

        let key = Self.key(for: data)
        let fileURL = url(forKey: key)
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { return key }

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try data.write(to: fileURL, options: [.atomic])
        return key
    }

    public func data(forKey key: String) -> Data? {
        try? Data(contentsOf: url(forKey: key))
    }

    public func contains(key: String) -> Bool {
        FileManager.default.fileExists(atPath: url(forKey: key).path)
    }

    /// Deletes stored images that no record refers to any more.
    @discardableResult
    public func removeUnreferenced(keeping referencedKeys: Set<String>) -> Int {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        ) else {
            return 0
        }

        var removed = 0
        for entry in entries where !referencedKeys.contains(entry.deletingPathExtension().lastPathComponent) {
            if (try? FileManager.default.removeItem(at: entry)) != nil {
                removed += 1
            }
        }
        return removed
    }

    private func url(forKey key: String) -> URL {
        directoryURL.appendingPathComponent(key).appendingPathExtension("png")
    }

    private static func key(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
