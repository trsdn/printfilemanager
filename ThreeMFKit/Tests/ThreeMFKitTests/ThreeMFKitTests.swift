import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
import ZIPFoundation
@testable import ThreeMFKit

final class ThreeMFKitTests: XCTestCase {
    func testBambuResolverPrefersAuxiliaryThumbnailOverPlateImage() throws {
        let resolver = BambuPreviewResolver()
        let entries = [
            ThreeMFPackageEntry(path: "Metadata/plate_1_small.png", uncompressedSize: 10),
            ThreeMFPackageEntry(path: "3D/3dmodel.model", uncompressedSize: 10),
            ThreeMFPackageEntry(path: "Metadata/plate_1.png", uncompressedSize: 10),
            ThreeMFPackageEntry(path: "Metadata/top_1.png", uncompressedSize: 10),
            ThreeMFPackageEntry(path: "Auxiliaries/.thumbnails/thumbnail_small.png", uncompressedSize: 10),
            ThreeMFPackageEntry(path: "Auxiliaries/.thumbnails/thumbnail_middle.png", uncompressedSize: 10),
            ThreeMFPackageEntry(path: "Auxiliaries/.thumbnails/thumbnail_3mf.png", uncompressedSize: 10)
        ]

        let candidates = resolver.orderedPreviewCandidates(in: entries)

        XCTAssertEqual(candidates.map(\.path), [
            "Auxiliaries/.thumbnails/thumbnail_middle.png",
            "Auxiliaries/.thumbnails/thumbnail_3mf.png",
            "Auxiliaries/.thumbnails/thumbnail_small.png",
            "Metadata/plate_1.png",
            "Metadata/plate_1_small.png",
            "Metadata/top_1.png"
        ])
    }

    func testBambuResolverPrefersPlateHeroImageOverTopDownView() throws {
        let resolver = BambuPreviewResolver()
        let entries = [
            ThreeMFPackageEntry(path: "Metadata/top_1.png", uncompressedSize: 10),
            ThreeMFPackageEntry(path: "Metadata/plate_no_light_1.png", uncompressedSize: 10),
            ThreeMFPackageEntry(path: "Metadata/plate_1.png", uncompressedSize: 10)
        ]

        let candidates = resolver.orderedPreviewCandidates(in: entries)

        XCTAssertEqual(candidates.map(\.path), [
            "Metadata/plate_1.png",
            "Metadata/plate_no_light_1.png",
            "Metadata/top_1.png"
        ])
    }

    func testBambuResolverExcludesObjectPickingMasks() throws {
        let resolver = BambuPreviewResolver()
        let entries = [
            ThreeMFPackageEntry(path: "Metadata/pick_1.png", uncompressedSize: 10),
            ThreeMFPackageEntry(path: "Metadata/top_pick_1.png", uncompressedSize: 10),
            ThreeMFPackageEntry(path: "Metadata/plate_1.png", uncompressedSize: 10)
        ]

        let candidates = resolver.orderedPreviewCandidates(in: entries)

        XCTAssertEqual(candidates.map(\.path), ["Metadata/plate_1.png"])
    }

    func testBambuResolverPrefersMetadataPreviewOverUnrelatedTexture() throws {
        let resolver = BambuPreviewResolver()
        let entries = [
            ThreeMFPackageEntry(path: "3D/textures/wood.png", uncompressedSize: 10),
            ThreeMFPackageEntry(path: "Metadata/plate_1.png", uncompressedSize: 10)
        ]

        let candidates = resolver.orderedPreviewCandidates(in: entries)

        XCTAssertEqual(candidates.map(\.path), [
            "Metadata/plate_1.png",
            "3D/textures/wood.png"
        ])
    }

    func testBambuResolverFindsGenericSlicerThumbnail() throws {
        let resolver = BambuPreviewResolver()
        let entries = [
            ThreeMFPackageEntry(path: "Metadata/thumbnail.png", uncompressedSize: 10),
            ThreeMFPackageEntry(path: "Metadata/top_1.png", uncompressedSize: 10)
        ]

        let candidates = resolver.orderedPreviewCandidates(in: entries)

        XCTAssertEqual(candidates.map(\.path), [
            "Metadata/thumbnail.png",
            "Metadata/top_1.png"
        ])
    }

    func testExtractorReturnsPreviewForSyntheticBambuPackage() throws {
        let packageURL = try makePackage(entries: [
            "Metadata/plate_1.png": try makePNG(width: 16, height: 10),
            "3D/3dmodel.model": Data("model".utf8)
        ])
        let extractor = ThreeMFPreviewExtractor()

        let result = extractor.preview(for: packageURL, maxPixelDimension: 8)

        guard case .preview(let image) = result else {
            return XCTFail("Expected preview, got \(result)")
        }
        XCTAssertEqual(image.contentTypeIdentifier, UTType.png.identifier)
        XCTAssertEqual(image.pixelSize.width, 8)
        XCTAssertEqual(image.pixelSize.height, 5)
        XCTAssertFalse(image.data.isEmpty)
    }

    func testExtractorFallsBackWhenPackageHasNoSupportedImage() throws {
        let packageURL = try makePackage(entries: [
            "3D/3dmodel.model": Data("model".utf8)
        ])
        let extractor = ThreeMFPreviewExtractor()

        let result = extractor.preview(for: packageURL)

        XCTAssertEqual(result, .fallback(PreviewFallback(reason: .noSupportedImage, fileName: packageURL.lastPathComponent)))
    }

    func testExtractorRejectsOrdinaryZipArchivesThatAreNotThreeMFPackages() throws {
        // The extensions also register for public.zip-archive so they still fire when a slicer
        // owns the .3mf type; a plain zip must be handed back rather than previewed.
        let packageURL = try makePackage(entries: [
            "photos/holiday.png": try makePNG(width: 16, height: 16),
            "notes.txt": Data("hello".utf8)
        ])
        let extractor = ThreeMFPreviewExtractor()

        let result = extractor.preview(for: packageURL)

        XCTAssertEqual(
            result,
            .fallback(PreviewFallback(reason: .notAThreeMFPackage, fileName: packageURL.lastPathComponent))
        )
    }

    func testExtractorAcceptsPackagesWhoseModelPartHasANonStandardName() throws {
        let packageURL = try makePackage(entries: [
            "Metadata/plate_1.png": try makePNG(width: 16, height: 16),
            "3D/Objects.model": Data("model".utf8)
        ])
        let extractor = ThreeMFPreviewExtractor()

        guard case .preview = extractor.preview(for: packageURL) else {
            return XCTFail("Expected a preview for a valid 3MF package")
        }
    }

    func testExtractorFallsBackForUnreadablePackage() throws {
        let fileURL = try makeTemporaryDirectory().appendingPathComponent("broken.3mf")
        try Data("not a zip".utf8).write(to: fileURL)
        let extractor = ThreeMFPreviewExtractor()

        let result = extractor.preview(for: fileURL)

        XCTAssertEqual(result, .fallback(PreviewFallback(reason: .unreadablePackage, fileName: "broken.3mf")))
    }

    func testExtractorReturnsPreviewForExternalRealFixtureWhenProvided() throws {
        guard let fixtureURL = try externalRealFixtureURL() else {
            throw XCTSkip("Set THREEMF_REAL_FIXTURE or Quicklook/.local-fixtures/real-fixture-path.txt to run this integration test.")
        }
        let extractor = ThreeMFPreviewExtractor()

        let result = extractor.preview(for: fixtureURL, maxPixelDimension: 512)

        guard case .preview(let image) = result else {
            return XCTFail("Expected preview for real fixture, got \(result)")
        }

        XCTAssertEqual(image.contentTypeIdentifier, UTType.png.identifier)
        XCTAssertGreaterThan(image.data.count, 0)
        XCTAssertGreaterThan(image.pixelSize.width, 0)
        XCTAssertGreaterThan(image.pixelSize.height, 0)
        XCTAssertLessThanOrEqual(max(image.pixelSize.width, image.pixelSize.height), 512)
    }

    private func externalRealFixtureURL() throws -> URL? {
        if let fixturePath = ProcessInfo.processInfo.environment["THREEMF_REAL_FIXTURE"], !fixturePath.isEmpty {
            return existingFileURL(atPath: fixturePath)
        }

        let testFileURL = URL(fileURLWithPath: #filePath)
        let projectRootURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let pathFileURL = projectRootURL.appendingPathComponent(".local-fixtures/real-fixture-path.txt")

        guard FileManager.default.fileExists(atPath: pathFileURL.path) else {
            return nil
        }

        let fixturePath = try String(contentsOf: pathFileURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return fixturePath.isEmpty ? nil : existingFileURL(atPath: fixturePath)
    }

    /// The pointer file may outlive the file it points at, so the target itself must be checked —
    /// otherwise a fixture that has since been deleted fails the test instead of skipping it.
    private func existingFileURL(atPath path: String) -> URL? {
        FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
    }

    private func makePackage(entries: [String: Data]) throws -> URL {
        let url = try makeTemporaryDirectory().appendingPathComponent(UUID().uuidString).appendingPathExtension("3mf")
        let archive = try Archive(url: url, accessMode: .create)

        for (path, data) in entries {
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count)) { position, size in
                let start = Int(position)
                return data.subdata(in: start..<(start + size))
            }
        }

        return url
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

        context.setFillColor(CGColor(red: 0.12, green: 0.44, blue: 0.86, alpha: 1))
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
            .appendingPathComponent("ThreeMFCoreTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private enum TestError: Error {
        case imageCreationFailed
    }
}
