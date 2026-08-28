@testable import PrintFileManagerCore
import CoreGraphics
import Foundation
import ImageIO
import ThreeMFKit
import UniformTypeIdentifiers
import XCTest
import ZIPFoundation

/// Scanning a folder, extracting metadata, and refusing malformed or oversized input.
final class IndexingTests: XCTestCase {
    func testIndexerDiscoversNestedThreeMFFilesAndExtractsMetadataAndPreview() throws {
        let rootURL = try makeTemporaryDirectory()
        let nestedURL = rootURL.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedURL, withIntermediateDirectories: true)
        let packageURL = nestedURL.appendingPathComponent("cable-clip.3mf")
        try makePackage(at: packageURL, entries: [
            "Metadata/plate_1.png": try makePNG(width: 32, height: 20),
            "3D/3dmodel.model": Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <model unit="millimeter" xml:lang="en-US">
              <metadata name="Title">Cable Clip</metadata>
                            <metadata name="SourceURL">https://makerworld.com/en/models/cable-clip</metadata>
                            <metadata name="Author">Test Designer</metadata>
                            <metadata name="License">CC-BY</metadata>
                            <metadata name="Application">Bambu Studio</metadata>
                            <resources>
                                <basematerials id="2">
                                    <base name="PLA" displaycolor="#ff0000" />
                                </basematerials>
                                <object id="1" type="model">
                                    <mesh>
                                        <vertices>
                                            <vertex x="0" y="0" z="0" />
                                            <vertex x="1" y="0" z="0" />
                                            <vertex x="0" y="1" z="0" />
                                        </vertices>
                                        <triangles>
                                            <triangle v1="0" v2="1" v3="2" />
                                        </triangles>
                                    </mesh>
                                </object>
                            </resources>
                            <build><item objectid="1" /></build>
            </model>
            """.utf8)
        ])

        let root = LibraryRoot(url: rootURL)
        let thumbnailStore = ThumbnailStore(directoryURL: rootURL.appendingPathComponent("Thumbnails", isDirectory: true))
        let result = try LibraryIndexer(thumbnailStore: thumbnailStore).scan(root: root)

        XCTAssertTrue(result.rootIsAvailable)
        XCTAssertEqual(result.records.count, 1)
        let record = try XCTUnwrap(result.records.first)
        XCTAssertEqual(record.relativePath, "Downloads/cable-clip.3mf")
        XCTAssertEqual(record.projectName, "Cable Clip")
        XCTAssertEqual(record.previewStatus, .available)
        XCTAssertEqual(record.metadata["plateCount"], "1")
        XCTAssertEqual(record.metadata["objectCount"], "1")
        XCTAssertEqual(record.projectKey, "cable-clip")
        XCTAssertEqual(record.category, "Functional Part")
        XCTAssertEqual(record.printability, .readyToPrint)
        XCTAssertEqual(record.sourceInfo?.platform, "MakerWorld")
        XCTAssertEqual(record.sourceInfo?.author, "Test Designer")
        XCTAssertEqual(record.sourceInfo?.license, "CC-BY")
        XCTAssertEqual(record.printDetails?.materials, ["PLA"])
        XCTAssertEqual(record.printDetails?.slicer, "Bambu Studio")
        XCTAssertTrue(record.sourceHints.contains("Bambu Studio / MakerWorld"))
        XCTAssertFalse(record.generatedTags.map(\.value).contains("bambu"))
        XCTAssertFalse(record.generatedTags.map(\.value).contains("multi-plate"))

        // The preview image is stored beside the index rather than inside the record.
        let thumbnailKey = try XCTUnwrap(record.thumbnailKey)
        XCTAssertTrue(thumbnailStore.contains(key: thumbnailKey))
        XCTAssertFalse(thumbnailStore.data(forKey: thumbnailKey)?.isEmpty ?? true)
    }

    func testLocalTagSuggestionsAvoidBroadMetadataTags() {
        let singlePlateTags = LocalTagSuggester().suggestTags(
            fileName: "Bambu MakerWorld 3MF Cable Clip",
            sourceHints: ["Bambu Studio / MakerWorld"],
            metadata: ["plateCount": "1"]
        ).map(\.value)
        XCTAssertFalse(singlePlateTags.contains("bambu"))
        XCTAssertFalse(singlePlateTags.contains("makerworld"))
        XCTAssertFalse(singlePlateTags.contains("3mf"))
        XCTAssertFalse(singlePlateTags.contains("multi-plate"))

        let multiPlateTags = LocalTagSuggester().suggestTags(
            fileName: "Organizer Tray",
            sourceHints: [],
            metadata: ["plateCount": "2"]
        ).map(\.value)
        XCTAssertFalse(multiPlateTags.contains("multi-plate"))
    }

    func testScanReusesRecordsForFilesThatHaveNotChanged() throws {
        let rootURL = try makeTemporaryDirectory()
        let packageURL = rootURL.appendingPathComponent("clip.3mf")
        try makePackage(at: packageURL, entries: [
            "Metadata/plate_1.png": try makePNG(width: 8, height: 8),
            "3D/3dmodel.model": Data("<model/>".utf8)
        ])
        let root = LibraryRoot(url: rootURL)
        let indexer = LibraryIndexer()

        let firstScan = try indexer.scan(root: root)
        let firstRecord = try XCTUnwrap(firstScan.records.first)

        let secondScan = try indexer.scan(root: root, previousRecords: firstScan.records)
        let secondRecord = try XCTUnwrap(secondScan.records.first)

        // A carried-over record keeps its original identity and indexing timestamp, which is what
        // proves the file was not re-hashed and re-parsed.
        XCTAssertEqual(secondRecord.id, firstRecord.id)
        XCTAssertEqual(secondRecord.indexedAt, firstRecord.indexedAt)
    }

    func testScanReindexesFilesWhoseContentChanged() throws {
        let rootURL = try makeTemporaryDirectory()
        let packageURL = rootURL.appendingPathComponent("clip.3mf")
        try makePackage(at: packageURL, entries: [
            "Metadata/plate_1.png": try makePNG(width: 8, height: 8),
            "3D/3dmodel.model": Data("<model/>".utf8)
        ])
        let root = LibraryRoot(url: rootURL)
        let indexer = LibraryIndexer()
        let firstScan = try indexer.scan(root: root)

        try FileManager.default.removeItem(at: packageURL)
        try makePackage(at: packageURL, entries: [
            "Metadata/plate_1.png": try makePNG(width: 16, height: 16),
            "3D/3dmodel.model": Data("<model><changed/></model>".utf8)
        ])
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(60)],
            ofItemAtPath: packageURL.path
        )

        let secondScan = try indexer.scan(root: root, previousRecords: firstScan.records)
        let secondRecord = try XCTUnwrap(secondScan.records.first)

        XCTAssertNotEqual(secondRecord.contentHash, firstScan.records.first?.contentHash)
    }

    func testPackageReaderRefusesEntriesLargerThanTheConfiguredLimit() throws {
        let packageURL = try makeTemporaryDirectory().appendingPathComponent("bomb.3mf")
        let payload = Data(repeating: 0, count: 64 * 1024)
        try makePackage(at: packageURL, entries: ["Metadata/plate_1.png": payload])

        let reader = ZIPFoundationThreeMFPackageReader(maximumEntrySize: 1_024)
        let entry = try XCTUnwrap(try reader.fileEntries(in: packageURL).first)

        XCTAssertThrowsError(try reader.data(for: entry, in: packageURL)) { error in
            XCTAssertEqual(
                error as? ThreeMFPackageReaderError,
                .entryTooLarge(path: entry.path, limit: 1_024)
            )
        }
    }

    func testMeshExtractorDropsTrianglesWithOutOfRangeIndices() throws {
        let packageURL = try makeTemporaryDirectory().appendingPathComponent("malformed.3mf")
        try makePackage(at: packageURL, entries: [
            "3D/3dmodel.model": Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <model unit="millimeter">
              <resources><object id="1" type="model"><mesh>
                <vertices>
                  <vertex x="0" y="0" z="0"/>
                  <vertex x="1" y="0" z="0"/>
                  <vertex x="0" y="1" z="0"/>
                </vertices>
                <triangles>
                  <triangle v1="0" v2="1" v3="2"/>
                  <triangle v1="0" v2="1" v3="99"/>
                  <triangle v1="-1" v2="1" v3="2"/>
                  <triangle v1="2147483647" v2="2147483647" v3="2147483647"/>
                </triangles>
              </mesh></object></resources>
            </model>
            """.utf8)
        ])

        let mesh = try XCTUnwrap(ThreeMFMeshExtractor().mesh(for: packageURL))

        XCTAssertEqual(mesh.vertices.count, 3)
        XCTAssertEqual(mesh.triangles, [ThreeMFTriangle(a: 0, b: 1, c: 2)])
        for triangle in mesh.triangles {
            for index in [triangle.a, triangle.b, triangle.c] {
                XCTAssertTrue((0..<Int32(mesh.vertices.count)).contains(index))
            }
        }
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
