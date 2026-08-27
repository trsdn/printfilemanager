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
}

public struct ZIPFoundationThreeMFPackageReader: ThreeMFPackageReading {
    public init() {}

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

        var data = Data()
        _ = try archive.extract(archiveEntry) { chunk in
            data.append(chunk)
        }
        return data
    }
}
