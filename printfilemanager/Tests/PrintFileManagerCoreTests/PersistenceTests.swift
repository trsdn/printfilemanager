@testable import PrintFileManagerCore
import CoreGraphics
import Foundation
import ImageIO
import ThreeMFKit
import UniformTypeIdentifiers
import XCTest
import ZIPFoundation

/// The library index and thumbnail store, including migration and the data-loss guards.
final class PersistenceTests: XCTestCase {
    func testDatabaseMergePreservesUserTagsAndNotesAcrossRescan() throws {
        let root = LibraryRoot(url: try makeTemporaryDirectory())
        let recordID = UUID()
        let oldRecord = PrintFileRecord(
            id: recordID,
            rootID: root.id,
            url: root.url.appendingPathComponent("part.3mf"),
            fileName: "part.3mf",
            relativePath: "part.3mf",
            fileSize: 10,
            modifiedAt: nil,
            contentHash: "abc",
            userTags: ["fixture"],
            notes: "Keep this variant",
            reviewedAt: Date(timeIntervalSince1970: 42),
            reviewedIssueSignature: "old-review-signature"
        )
        let scannedRecord = PrintFileRecord(
            rootID: root.id,
            url: root.url.appendingPathComponent("part-renamed.3mf"),
            fileName: "part-renamed.3mf",
            relativePath: "part-renamed.3mf",
            fileSize: 10,
            modifiedAt: nil,
            contentHash: "abc"
        )
        let snapshot = LibrarySnapshot(roots: [root], records: [oldRecord])
        let result = LibraryScanResult(root: root, rootIsAvailable: true, records: [scannedRecord])

        let merged = LibraryDatabase(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
            .merge(scanResult: result, into: snapshot)

        let activeRecord = try XCTUnwrap(merged.records.first { $0.indexingStatus != .missing })
        XCTAssertEqual(activeRecord.id, recordID)
        XCTAssertEqual(activeRecord.userTags, ["fixture"])
        XCTAssertEqual(activeRecord.notes, "Keep this variant")
        XCTAssertEqual(activeRecord.reviewedAt, Date(timeIntervalSince1970: 42))
        XCTAssertEqual(activeRecord.reviewedIssueSignature, "old-review-signature")
    }

    func testDatabaseMergeRemovesStaleLocalSuggestedTags() throws {
        let root = LibraryRoot(url: try makeTemporaryDirectory())
        let recordID = UUID()
        let staleSuggestedTag = GeneratedTag(value: "bambu", confidence: 0.55, source: "local")
        var acceptedLocalTag = GeneratedTag(value: "fixture", confidence: 0.55, source: "local")
        acceptedLocalTag.state = .accepted
        let aiTag = GeneratedTag(value: "holder", confidence: 0.72, source: "ai")
        let existingRecord = PrintFileRecord(
            id: recordID,
            rootID: root.id,
            url: root.url.appendingPathComponent("part.3mf"),
            fileName: "part.3mf",
            relativePath: "part.3mf",
            fileSize: 10,
            modifiedAt: nil,
            generatedTags: [staleSuggestedTag, acceptedLocalTag, aiTag]
        )
        let scannedRecord = PrintFileRecord(
            rootID: root.id,
            url: root.url.appendingPathComponent("part.3mf"),
            fileName: "part.3mf",
            relativePath: "part.3mf",
            fileSize: 10,
            modifiedAt: nil,
            generatedTags: [GeneratedTag(value: "part", confidence: 0.55, source: "local")]
        )
        let snapshot = LibrarySnapshot(roots: [root], records: [existingRecord])
        let result = LibraryScanResult(root: root, rootIsAvailable: true, records: [scannedRecord])

        let merged = LibraryDatabase(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
            .merge(scanResult: result, into: snapshot)

        let tags = try XCTUnwrap(merged.records.first).generatedTags.map(\.value)
        XCTAssertFalse(tags.contains("bambu"))
        XCTAssertTrue(tags.contains("fixture"))
        XCTAssertTrue(tags.contains("holder"))
        XCTAssertTrue(tags.contains("part"))
    }

    func testDatabaseQuarantinesUnreadableIndexInsteadOfLosingIt() throws {
        let folderURL = try makeTemporaryDirectory()
        let indexURL = folderURL.appendingPathComponent("library-index.json")
        try Data("{ this is not valid json".utf8).write(to: indexURL)
        let database = LibraryDatabase(fileURL: indexURL)

        XCTAssertThrowsError(try database.load())

        let quarantinedURL = try database.quarantineUnreadableIndex()

        let unwrappedQuarantineURL = try XCTUnwrap(quarantinedURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: unwrappedQuarantineURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: indexURL.path))
        XCTAssertTrue(unwrappedQuarantineURL.lastPathComponent.contains("corrupt-"))
        XCTAssertEqual(try String(contentsOf: unwrappedQuarantineURL, encoding: .utf8), "{ this is not valid json")
    }

    func testDatabaseWritesOneBackupPerSessionBeforeOverwriting() throws {
        let folderURL = try makeTemporaryDirectory()
        let indexURL = folderURL.appendingPathComponent("library-index.json")
        let database = LibraryDatabase(fileURL: indexURL)

        try database.save(LibrarySnapshot(roots: [], records: [], managedFolderURL: nil))
        let firstGeneration = try Data(contentsOf: indexURL)

        try database.save(LibrarySnapshot(managedFolderURL: URL(fileURLWithPath: "/tmp/second")))
        try database.save(LibrarySnapshot(managedFolderURL: URL(fileURLWithPath: "/tmp/third")))

        // The backup must capture the last known-good state, not be overwritten by every save.
        let backupURL = indexURL.appendingPathExtension("bak")
        XCTAssertEqual(try Data(contentsOf: backupURL), firstGeneration)
    }

    func testSnapshotWithoutSchemaVersionDecodesAsVersionOne() throws {
        let folderURL = try makeTemporaryDirectory()
        let indexURL = folderURL.appendingPathComponent("library-index.json")
        try Data(#"{"roots":[],"records":[]}"#.utf8).write(to: indexURL)

        let snapshot = try LibraryDatabase(fileURL: indexURL).load()

        XCTAssertEqual(snapshot.schemaVersion, LibrarySnapshot.currentSchemaVersion)
        XCTAssertTrue(snapshot.records.isEmpty)
    }

    func testDatabaseRejectsIndexWrittenByANewerSchema() throws {
        let folderURL = try makeTemporaryDirectory()
        let indexURL = folderURL.appendingPathComponent("library-index.json")
        let futureVersion = LibrarySnapshot.currentSchemaVersion + 1
        try Data(#"{"schemaVersion":\#(futureVersion),"roots":[],"records":[]}"#.utf8).write(to: indexURL)

        XCTAssertThrowsError(try LibraryDatabase(fileURL: indexURL).load()) { error in
            XCTAssertEqual(
                error as? LibrarySchemaError,
                .unsupportedSchemaVersion(found: futureVersion, supported: LibrarySnapshot.currentSchemaVersion)
            )
        }
    }

    func testThumbnailStoreDeduplicatesIdenticalImages() throws {
        let store = ThumbnailStore(directoryURL: try makeTemporaryDirectory())
        let image = try makePNG(width: 8, height: 8)

        let firstKey = try store.store(image)
        let secondKey = try store.store(image)

        XCTAssertEqual(firstKey, secondKey)
        XCTAssertEqual(store.data(forKey: firstKey), image)
        XCTAssertTrue(store.contains(key: firstKey))
    }

    func testThumbnailStoreRemovesUnreferencedImages() throws {
        let store = ThumbnailStore(directoryURL: try makeTemporaryDirectory())
        let keptKey = try store.store(try makePNG(width: 8, height: 8))
        let orphanKey = try store.store(try makePNG(width: 16, height: 16))

        let removed = store.removeUnreferenced(keeping: [keptKey])

        XCTAssertEqual(removed, 1)
        XCTAssertTrue(store.contains(key: keptKey))
        XCTAssertFalse(store.contains(key: orphanKey))
    }

    func testLoadMigratesEmbeddedThumbnailsIntoTheStore() throws {
        let folderURL = try makeTemporaryDirectory()
        let indexURL = folderURL.appendingPathComponent("library-index.json")
        let store = ThumbnailStore(directoryURL: folderURL.appendingPathComponent("Thumbnails", isDirectory: true))
        let image = try makePNG(width: 12, height: 12)

        // A schema-1 index: no schemaVersion key, preview bytes embedded as base64.
        let legacyIndex: [String: Any] = [
            "roots": [],
            "records": [[
                "id": UUID().uuidString,
                "rootID": UUID().uuidString,
                "url": "file:///tmp/legacy.3mf",
                "fileName": "legacy.3mf",
                "relativePath": "legacy.3mf",
                "fileSize": 10,
                "indexingStatus": "indexed",
                "previewStatus": "available",
                "thumbnailData": image.base64EncodedString(),
                "sourceHints": [],
                "metadata": [:],
                "userTags": [],
                "generatedTags": [],
                "notes": ""
            ]]
        ]
        try JSONSerialization.data(withJSONObject: legacyIndex).write(to: indexURL)

        let snapshot = try LibraryDatabase(fileURL: indexURL, thumbnailStore: store).load()

        XCTAssertEqual(snapshot.schemaVersion, LibrarySnapshot.currentSchemaVersion)
        let record = try XCTUnwrap(snapshot.records.first)
        let key = try XCTUnwrap(record.thumbnailKey)
        XCTAssertEqual(store.data(forKey: key), image)
    }

    private func makePackage(at url: URL, entries: [String: Data]) throws {
        let archive = try Archive(url: url, accessMode: .create)

        for (path, data) in entries {
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count)) { position, size in
                let start = Int(position)
                return data.subdata(in: start..<(start + size))
            }
        }
    }

    private func makePNG(width: Int, height: Int) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw TestError.imageCreationFailed
        }

        context.setFillColor(CGColor(red: 0.16, green: 0.42, blue: 0.78, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        guard let image = context.makeImage() else {
            throw TestError.imageCreationFailed
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw TestError.imageCreationFailed
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw TestError.imageCreationFailed
        }
        return data as Data
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PrintFileManagerCoreTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private enum TestError: Error {
        case imageCreationFailed
    }
}
