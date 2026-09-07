@testable import PrintFileManagerCore
import Foundation
import XCTest
import ZIPFoundation

final class RescanIdentityTests: XCTestCase {
    func testCachedCopiesHealDuplicateIDsAndRemainStableAcrossRescans() throws {
        let folder = try makeTemporaryDirectory()
        let root = LibraryRoot(url: folder)
        let original = folder.appendingPathComponent("holder.3mf")
        let archive = try Archive(url: original, accessMode: .create)
        let model = Data("<model/>".utf8)
        try archive.addEntry(with: "3D/3dmodel.model", type: .file, uncompressedSize: Int64(model.count)) { position, size in
            let start = Int(position)
            return model.subdata(in: start..<(start + size))
        }
        for name in ["holder.copy.3mf", "#holder.3mf", "holder fresh.3mf", "holder-new.3mf"] {
            try FileManager.default.copyItem(at: original, to: folder.appendingPathComponent(name))
        }

        let indexer = LibraryIndexer()
        let database = LibraryDatabase(fileURL: folder.appendingPathComponent("index.json"))
        let sharedID = UUID()
        let stored = try indexer.scan(root: root).records.map { record in
            var duplicate = record
            duplicate.id = sharedID
            duplicate.userTags = [record.relativePath]
            duplicate.notes = "Notes for \(record.relativePath)"
            duplicate.reviewedAt = Date(timeIntervalSince1970: 42)
            duplicate.reviewedIssueSignature = record.relativePath
            return duplicate
        }
        XCTAssertEqual(stored.count, 5)
        XCTAssertTrue(stored.allSatisfy { $0.indexingStatus == .indexed && $0.contentHash != nil })
        XCTAssertEqual(Set(stored.compactMap(\.contentHash)).count, 1)
        var snapshot = LibrarySnapshot(roots: [root], records: stored)
        var repairedIDs: [String: UUID]?

        for _ in 0..<3 {
            try database.save(snapshot)
            snapshot = try database.load()
            let scan = try indexer.scan(root: root, previousRecords: snapshot.records)
            // Exercise the cached path that the original merge-only regression omitted.
            for record in scan.records {
                XCTAssertEqual(record, snapshot.records.first { $0.relativePath == record.relativePath })
            }
            snapshot = database.merge(scanResult: scan, into: snapshot)
            XCTAssertEqual(snapshot.records.count, 5)
            XCTAssertEqual(Set(snapshot.records.map(\.id)).count, 5)
            for record in snapshot.records {
                let previous = try XCTUnwrap(stored.first { $0.relativePath == record.relativePath })
                XCTAssertEqual(record.userTags, previous.userTags)
                XCTAssertEqual(record.notes, previous.notes)
                XCTAssertEqual(record.reviewedAt, previous.reviewedAt)
                XCTAssertEqual(record.reviewedIssueSignature, previous.reviewedIssueSignature)
            }
            let currentIDs = Dictionary(uniqueKeysWithValues: snapshot.records.map { ($0.relativePath, $0.id) })
            if let repairedIDs {
                XCTAssertEqual(currentIDs, repairedIDs)
            } else {
                repairedIDs = currentIDs
            }
        }
    }

    func testRescanPreservesOtherRootsWithSharedIDsAndHashes() throws {
        let folder = try makeTemporaryDirectory()
        let root = LibraryRoot(url: folder.appendingPathComponent("scanned"))
        var other = LibraryRoot(url: folder.appendingPathComponent("other"))
        let scanned = record(in: root, path: "part.3mf")
        var foreign = record(in: other, path: "copy.3mf")
        foreign.id = scanned.id
        foreign.userTags = ["foreign"]
        foreign.notes = "Do not change this root"
        let database = LibraryDatabase(fileURL: folder.appendingPathComponent("index.json"))

        for available in [true, false] {
            other.isAvailable = available
            let snapshot = LibrarySnapshot(roots: [root, other], records: [scanned, foreign])
            let result = database.merge(
                scanResult: LibraryScanResult(root: root, rootIsAvailable: true, records: [scanned]),
                into: snapshot
            )
            XCTAssertEqual(result.records.count, 2)
            XCTAssertEqual(Set(result.records.map(\.id)).count, 2)
            XCTAssertEqual(result.records.first { $0.rootID == other.id }, foreign)
            XCTAssertEqual(result.roots.first { $0.id == other.id }, other)
            XCTAssertEqual(result.records.first { $0.rootID == root.id }?.userTags, scanned.userTags)
        }
    }

    func testNewCopyDoesNotAdoptIdentityOrAnnotationsFromAnotherRoot() throws {
        let folder = try makeTemporaryDirectory()
        let root = LibraryRoot(url: folder.appendingPathComponent("scanned"))
        let other = LibraryRoot(url: folder.appendingPathComponent("other"))
        let foreign = record(in: other, path: "part.3mf")
        let scanned = record(in: root, path: "copy.3mf")
        let result = LibraryDatabase(fileURL: folder.appendingPathComponent("index.json")).merge(
            scanResult: LibraryScanResult(root: root, rootIsAvailable: true, records: [scanned]),
            into: LibrarySnapshot(roots: [root, other], records: [foreign])
        )
        XCTAssertEqual(result.records.count, 2)
        XCTAssertTrue(result.records.contains(foreign))
        XCTAssertTrue(result.records.contains(scanned))
    }

    func testMissingRecordWithSharedIDIsPreservedWithItsAnnotations() throws {
        let folder = try makeTemporaryDirectory()
        let root = LibraryRoot(url: folder)
        let scanned = record(in: root, path: "live.3mf")
        var missing = record(in: root, path: "missing.3mf")
        missing.id = scanned.id
        let result = LibraryDatabase(fileURL: folder.appendingPathComponent("index.json")).merge(
            scanResult: LibraryScanResult(root: root, rootIsAvailable: true, records: [scanned]),
            into: LibrarySnapshot(roots: [root], records: [scanned, missing])
        )
        XCTAssertEqual(result.records.count, 2)
        XCTAssertEqual(Set(result.records.map(\.id)).count, 2)
        let retained = try XCTUnwrap(result.records.first { $0.relativePath == missing.relativePath })
        XCTAssertEqual(retained.indexingStatus, .missing)
        XCTAssertEqual(retained.userTags, missing.userTags)
        XCTAssertEqual(retained.notes, missing.notes)
        XCTAssertEqual(result.records.first { $0.relativePath == scanned.relativePath }?.id, scanned.id)
    }

    func testMovedCopiesWithSharedIDsAreMatchedByPathNotIdentity() throws {
        let folder = try makeTemporaryDirectory()
        let root = LibraryRoot(url: folder)
        let first = record(in: root, path: "first.3mf")
        var second = record(in: root, path: "second.3mf")
        second.id = first.id
        let moved = record(in: root, path: "moved.3mf")
        let result = LibraryDatabase(fileURL: folder.appendingPathComponent("index.json")).merge(
            scanResult: LibraryScanResult(root: root, rootIsAvailable: true, records: [moved, first]),
            into: LibrarySnapshot(roots: [root], records: [first, second])
        )
        XCTAssertEqual(result.records.count, 2)
        XCTAssertEqual(Set(result.records.map(\.id)).count, 2)
        XCTAssertEqual(result.records.first { $0.relativePath == first.relativePath }?.userTags, first.userTags)
        XCTAssertEqual(result.records.first { $0.relativePath == moved.relativePath }?.userTags, second.userTags)
        XCTAssertTrue(result.records.allSatisfy { $0.indexingStatus == .indexed })
    }

    private func record(in root: LibraryRoot, path: String) -> PrintFileRecord {
        PrintFileRecord(
            rootID: root.id, url: root.url.appendingPathComponent(path),
            fileName: path, relativePath: path, fileSize: 10, modifiedAt: nil,
            contentHash: "same-content", indexingStatus: .indexed,
            userTags: [path], notes: "Notes for \(path)"
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("RescanIdentityTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock {
            try FileManager.default.removeItem(at: folder)
        }
        return folder
    }
}
