import PrintFileManagerCore
import SwiftUI
import XCTest
@testable import PrintFileManager

/// The grid lays tiles out at a 176pt minimum. A tile that cannot be drawn that narrow overflows
/// into its neighbour, which is what made the library look broken after a window resize.
@MainActor
final class FileTileLayoutTests: XCTestCase {
    /// `LibraryBrowserView` lays out with `GridItem(.adaptive(minimum: 176, ...))`.
    private let narrowestColumn: CGFloat = 176

    func testATileFullOfBadgesStillFitsTheNarrowestColumn() throws {
        let hostingView = NSHostingView(rootView: tile(for: mostCrowdedRecord()))

        let fitting = hostingView.fittingSize

        XCTAssertLessThanOrEqual(
            fitting.width,
            narrowestColumn,
            "a tile demanding \(fitting.width)pt cannot be laid out in a \(narrowestColumn)pt column"
        )
    }

    func testTheTileStillLaysItsRowOutInsideTheColumn() throws {
        let hostingView = NSHostingView(rootView: tile(for: mostCrowdedRecord()))
        hostingView.frame = NSRect(x: 0, y: 0, width: narrowestColumn, height: 320)
        hostingView.layoutSubtreeIfNeeded()

        // Nothing may be drawn outside the tile: the badges are clipped instead.
        for subview in hostingView.subviews {
            XCTAssertLessThanOrEqual(subview.frame.maxX, narrowestColumn + 0.5, "\(subview) escaped the column")
        }
    }

    // MARK: - Helpers

    /// Every badge at once plus the three fixed-width buttons, which is the widest a tile gets.
    private func mostCrowdedRecord() -> PrintFileRecord {
        PrintFileRecord(
            rootID: UUID(),
            url: URL(fileURLWithPath: "/tmp/a-rather-long-project-name/part.3mf"),
            fileName: "part.3mf",
            relativePath: "a-rather-long-project-name/part.3mf",
            fileSize: 1_024,
            modifiedAt: Date(),
            indexingStatus: .missing,
            previewStatus: .missing,
            projectName: "A Rather Long Project Name",
            userTags: ["one", "two", "three"],
            printability: .needsReview
        )
    }

    private func tile(for record: PrintFileRecord) -> some View {
        let libraryFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileTileLayoutTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        return FileTile(record: record, isSelected: false)
            .environmentObject(
                LibraryViewModel(
                    database: LibraryDatabase(fileURL: libraryFolder.appendingPathComponent("i.json")),
                    thumbnailStore: ThumbnailStore(directoryURL: libraryFolder.appendingPathComponent("Thumbnails", isDirectory: true)),
                    legacyLibraryFolder: libraryFolder.appendingPathComponent("no-legacy-library", isDirectory: true)
                )
            )
            .environmentObject(AISettingsStore(defaults: UserDefaults(suiteName: "FileTileLayoutTests") ?? .standard))
            .frame(width: narrowestColumn)
    }
}
