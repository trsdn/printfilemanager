import Foundation

/// Brings a pre-sandbox library into the container without ever leaving the user without one.
///
/// The first version of this removed the destination index and then copied the legacy one over
/// it. Every way that copy can fail -- a sandbox denial, a full disk, the source disappearing
/// between the check and the read -- ended with the user holding no index at all. Nothing proved
/// the copy was complete either: readability was established by opening the source and reading a
/// single byte, which says nothing about the remaining hundred megabytes.
///
/// So the work happens beside the destination and is only swapped in once it has been read back
/// and found to hold records. Previews are committed before the index, because an index that
/// reports content is what stops this migration from ever being attempted again.
public enum LegacyLibraryAdoption {
    public enum Failure: LocalizedError, Equatable {
        case legacyIndexHasNoRecords
        case copyDidNotSurvive
        case committedIndexUnreadable

        public var errorDescription: String? {
            switch self {
            case .legacyIndexHasNoRecords:
                return "the older library holds no files"
            case .copyDidNotSurvive:
                return "the copy could not be read back"
            case .committedIndexUnreadable:
                return "the restored library could not be read back"
            }
        }
    }

    public static let thumbnailFolderName = "Thumbnails"

    /// - Returns: how many records the committed index holds, read back from the committed file.
    @discardableResult
    public static func perform(
        from legacyFolder: URL,
        toIndex destinationIndex: URL,
        fileManager: FileManager = .default
    ) throws -> Int {
        let destinationFolder = destinationIndex.deletingLastPathComponent()
        try fileManager.createDirectory(at: destinationFolder, withIntermediateDirectories: true)

        // Staging sits inside the destination folder so committing is a rename on one volume,
        // rather than a second copy that can fail after the first one has been trusted.
        let staging = destinationFolder
            .appendingPathComponent(".adopting-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        let stagedIndex = staging.appendingPathComponent(LegacyLibraryLocator.indexFileName)
        try fileManager.copyItem(
            at: legacyFolder.appendingPathComponent(LegacyLibraryLocator.indexFileName),
            to: stagedIndex
        )

        guard let staged = LegacyLibraryLocator.recordCount(at: stagedIndex) else {
            throw Failure.copyDidNotSurvive
        }
        guard staged > 0 else { throw Failure.legacyIndexHasNoRecords }

        let legacyThumbnails = legacyFolder
            .appendingPathComponent(thumbnailFolderName, isDirectory: true)
        let destinationThumbnails = destinationFolder
            .appendingPathComponent(thumbnailFolderName, isDirectory: true)
        let stagedThumbnails = staging.appendingPathComponent(thumbnailFolderName, isDirectory: true)

        let installsThumbnails = fileManager.fileExists(atPath: legacyThumbnails.path)
            && !fileManager.fileExists(atPath: destinationThumbnails.path)
        if installsThumbnails {
            try fileManager.copyItem(at: legacyThumbnails, to: stagedThumbnails)
            try fileManager.moveItem(at: stagedThumbnails, to: destinationThumbnails)
        }

        if fileManager.fileExists(atPath: destinationIndex.path) {
            _ = try fileManager.replaceItemAt(destinationIndex, withItemAt: stagedIndex)
        } else {
            try fileManager.moveItem(at: stagedIndex, to: destinationIndex)
        }

        guard let committed = LegacyLibraryLocator.recordCount(at: destinationIndex), committed > 0 else {
            throw Failure.committedIndexUnreadable
        }
        return committed
    }
}
