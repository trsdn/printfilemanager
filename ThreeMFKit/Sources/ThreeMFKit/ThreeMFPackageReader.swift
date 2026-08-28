import Foundation
import ZIPFoundation

public struct ThreeMFPackageEntry: Equatable, Hashable, Sendable {
    public let path: String
    public let uncompressedSize: UInt64

    public init(path: String, uncompressedSize: UInt64) {
        self.path = path
        self.uncompressedSize = uncompressedSize
    }
}

public protocol ThreeMFPackageReading: Sendable {
    func fileEntries(in packageURL: URL) throws -> [ThreeMFPackageEntry]
    func data(for entry: ThreeMFPackageEntry, in packageURL: URL) throws -> Data
}

public enum ThreeMFPackageReaderError: Error, Equatable {
    case unreadableArchive(URL)
    case entryNotFound(String)
    case entryTooLarge(path: String, limit: UInt64)
}

public struct ZIPFoundationThreeMFPackageReader: ThreeMFPackageReading {
    /// Upper bound on the decompressed size of a single entry.
    ///
    /// A `.3mf` is an untrusted ZIP that is frequently downloaded from the internet, and DEFLATE
    /// reaches compression ratios around 1000:1. Without a ceiling, a small crafted package can
    /// expand to gigabytes in memory — fatal in a memory-constrained Quick Look extension and an
    /// easy way to take down the indexer during a background scan.
    public static let defaultMaximumEntrySize: UInt64 = 256 * 1024 * 1024

    private let maximumEntrySize: UInt64

    public init(maximumEntrySize: UInt64 = ZIPFoundationThreeMFPackageReader.defaultMaximumEntrySize) {
        self.maximumEntrySize = maximumEntrySize
    }

    public func fileEntries(in packageURL: URL) throws -> [ThreeMFPackageEntry] {
        let archive: Archive
        do {
            archive = try Archive(url: packageURL, accessMode: .read)
        } catch {
            throw ThreeMFPackageReaderError.unreadableArchive(packageURL)
        }

        var entries: [ThreeMFPackageEntry] = []
        for entry in archive where entry.type == .file {
            entries.append(ThreeMFPackageEntry(path: entry.path, uncompressedSize: entry.uncompressedSize))
        }
        return entries
    }

    public func data(for entry: ThreeMFPackageEntry, in packageURL: URL) throws -> Data {
        let archive: Archive
        do {
            archive = try Archive(url: packageURL, accessMode: .read)
        } catch {
            throw ThreeMFPackageReaderError.unreadableArchive(packageURL)
        }

        guard let archiveEntry = archive[entry.path] else {
            throw ThreeMFPackageReaderError.entryNotFound(entry.path)
        }

        guard archiveEntry.uncompressedSize <= maximumEntrySize else {
            throw ThreeMFPackageReaderError.entryTooLarge(path: entry.path, limit: maximumEntrySize)
        }

        // The declared size lives in the archive metadata and can lie, so the stream is also
        // budgeted and aborted the moment it exceeds the limit.
        var data = Data()
        var extractedBytes: UInt64 = 0
        _ = try archive.extract(archiveEntry) { chunk in
            extractedBytes += UInt64(chunk.count)
            guard extractedBytes <= maximumEntrySize else {
                throw ThreeMFPackageReaderError.entryTooLarge(path: entry.path, limit: maximumEntrySize)
            }
            data.append(chunk)
        }
        return data
    }
}
