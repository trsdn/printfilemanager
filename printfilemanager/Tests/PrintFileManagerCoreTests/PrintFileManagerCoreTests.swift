@testable import PrintFileManagerCore
import CoreGraphics
import Foundation
import ImageIO
import ThreeMFKit
import UniformTypeIdentifiers
import XCTest
import ZIPFoundation

/// Organization planning, execution and undo.
final class PrintFileManagerCoreTests: XCTestCase {
    func testExecuteContinuesPastAFailureAndReportsEachOutcome() throws {
        let sourceRoot = try makeTemporaryDirectory()
        let targetRoot = try makeTemporaryDirectory()

        let goodURL = sourceRoot.appendingPathComponent("good.3mf")
        let blockedURL = sourceRoot.appendingPathComponent("blocked.3mf")
        try Data("good".utf8).write(to: goodURL)
        try Data("blocked".utf8).write(to: blockedURL)

        let records = [goodURL, blockedURL].map { url in
            PrintFileRecord(
                rootID: UUID(),
                url: url,
                fileName: url.lastPathComponent,
                relativePath: url.lastPathComponent,
                fileSize: 4,
                modifiedAt: Date(),
                indexingStatus: .indexed
            )
        }

        let planner = OrganizationPlanner()
        let plan = planner.planMove(records: records, to: targetRoot)
        XCTAssertEqual(plan.actions.count, 2)

        // Occupy one destination so that action must fail while the other still succeeds.
        let blockedAction = try XCTUnwrap(plan.actions.first { $0.sourceURL.lastPathComponent == "blocked.3mf" })
        try FileManager.default.createDirectory(
            at: blockedAction.destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("occupied".utf8).write(to: blockedAction.destinationURL)

        let report = planner.execute(plan)

        XCTAssertEqual(report.succeededCount, 1)
        XCTAssertEqual(report.failedCount, 1)
        XCTAssertEqual(report.failures.first?.action.sourceURL.lastPathComponent, "blocked.3mf")

        // A failure must not abort the batch: the healthy file still moved.
        XCTAssertFalse(FileManager.default.fileExists(atPath: goodURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: blockedURL.path))
    }

    func testUndoMovesFilesBackToTheirOriginalLocation() throws {
        let sourceRoot = try makeTemporaryDirectory()
        let targetRoot = try makeTemporaryDirectory()
        let sourceURL = sourceRoot.appendingPathComponent("hook.3mf")
        try Data("fixture".utf8).write(to: sourceURL)

        let record = PrintFileRecord(
            rootID: UUID(),
            url: sourceURL,
            fileName: sourceURL.lastPathComponent,
            relativePath: sourceURL.lastPathComponent,
            fileSize: 7,
            modifiedAt: Date(),
            indexingStatus: .indexed
        )

        let planner = OrganizationPlanner()
        let report = planner.execute(planner.planMove(records: [record], to: targetRoot))
        let destination = try XCTUnwrap(report.successfulOutcomes.first?.action.destinationURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertTrue(report.isUndoable)

        let undoReport = planner.undo(report)

        XCTAssertEqual(undoReport.succeededCount, 1)
        XCTAssertEqual(undoReport.failedCount, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(try Data(contentsOf: sourceURL), Data("fixture".utf8))
    }

    func testUndoOfACopyRemovesTheCopyAndKeepsTheOriginal() throws {
        let sourceRoot = try makeTemporaryDirectory()
        let targetRoot = try makeTemporaryDirectory()
        let sourceURL = sourceRoot.appendingPathComponent("hook.3mf")
        try Data("fixture".utf8).write(to: sourceURL)

        let record = PrintFileRecord(
            rootID: UUID(),
            url: sourceURL,
            fileName: sourceURL.lastPathComponent,
            relativePath: sourceURL.lastPathComponent,
            fileSize: 7,
            modifiedAt: Date(),
            indexingStatus: .indexed
        )

        let planner = OrganizationPlanner()
        let report = planner.execute(planner.planCopy(records: [record], to: targetRoot))
        let destination = try XCTUnwrap(report.successfulOutcomes.first?.action.destinationURL)

        planner.undo(report)

        // Undoing a copy must never touch the user's original.
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
    }

    func testUndoSkipsActionsWhoseFilesTheUserAlreadyMovedAway() throws {
        let sourceRoot = try makeTemporaryDirectory()
        let targetRoot = try makeTemporaryDirectory()
        let sourceURL = sourceRoot.appendingPathComponent("hook.3mf")
        try Data("fixture".utf8).write(to: sourceURL)

        let record = PrintFileRecord(
            rootID: UUID(),
            url: sourceURL,
            fileName: sourceURL.lastPathComponent,
            relativePath: sourceURL.lastPathComponent,
            fileSize: 7,
            modifiedAt: Date(),
            indexingStatus: .indexed
        )

        let planner = OrganizationPlanner()
        let report = planner.execute(planner.planMove(records: [record], to: targetRoot))
        let destination = try XCTUnwrap(report.successfulOutcomes.first?.action.destinationURL)
        try FileManager.default.removeItem(at: destination)

        let undoReport = planner.undo(report)

        XCTAssertEqual(undoReport.succeededCount, 0)
        XCTAssertEqual(undoReport.failedCount, 0)
        XCTAssertEqual(undoReport.skippedCount, 1)
    }

    func testReportSummaryDescribesTheBatch() {
        let action = OrganizationAction(
            recordID: UUID(),
            sourceURL: URL(fileURLWithPath: "/tmp/a.3mf"),
            destinationURL: URL(fileURLWithPath: "/tmp/library/a.3mf"),
            kind: .move,
            reason: "test"
        )
        let report = OrganizationExecutionReport(
            targetRootURL: URL(fileURLWithPath: "/tmp/library"),
            outcomes: [
                OrganizationActionOutcome(action: action, result: .succeeded),
                OrganizationActionOutcome(action: action, result: .skipped),
                OrganizationActionOutcome(action: action, result: .failed("boom"))
            ]
        )

        XCTAssertEqual(report.summary, "1 moved · 1 skipped · 1 failed")
        XCTAssertEqual(report.kind, .move)
        XCTAssertTrue(report.isUndoable)
    }

    func testReportSummaryGroupsLargeNumbersForTheCurrentLocale() {
        // A four-figure batch is realistic for a large library, and "1234 moved" is wrong in every
        // locale that groups thousands. Interpolating the Int directly produced exactly that.
        let action = OrganizationAction(
            recordID: UUID(),
            sourceURL: URL(fileURLWithPath: "/tmp/a.3mf"),
            destinationURL: URL(fileURLWithPath: "/tmp/library/a.3mf"),
            kind: .move,
            reason: "test"
        )
        let report = OrganizationExecutionReport(
            targetRootURL: URL(fileURLWithPath: "/tmp/library"),
            outcomes: Array(repeating: OrganizationActionOutcome(action: action, result: .succeeded), count: 1234)
        )

        let grouped = 1234.formatted()
        XCTAssertTrue(report.summary.contains(grouped), "expected \(grouped) in \(report.summary)")
        // Only meaningful where the locale actually groups; asserting it unconditionally would
        // fail in locales that do not.
        if grouped != "1234" {
            XCTAssertFalse(report.summary.contains("1234"))
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

/// A root with no security-scoped bookmark used to be reported as accessible without asking.
/// That is right for a non-sandboxed build and wrong for a library carried into a sandbox, where
/// it left folders looking healthy while every file under them read as missing.
final class UnbookmarkedRootAccessTests: XCTestCase {
    func testAReadableFolderWithoutABookmarkIsStillUsable() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertTrue(SecurityScopedAccessCoordinator.isDirectoryReadable(directory))
    }

    func testAFolderThatCannotBeListedIsReportedAsUnreadable() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
        // Standing in for the sandbox denial, which a test process cannot produce directly.
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: directory.path)

        XCTAssertFalse(SecurityScopedAccessCoordinator.isDirectoryReadable(directory))
    }

    func testAFolderThatDoesNotExistIsReportedAsUnreadable() {
        let missing = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")

        XCTAssertFalse(SecurityScopedAccessCoordinator.isDirectoryReadable(missing))
    }
}
