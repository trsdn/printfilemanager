@testable import PrintFileManagerCore
import CoreGraphics
import Foundation
import ImageIO
import ThreeMFKit
import UniformTypeIdentifiers
import XCTest
import ZIPFoundation

/// Filtering, smart collections, the review queue, and search matching.
final class SearchTests: XCTestCase {
    func testSearchMatchesMetadataTagsAndDuplicateCandidates() {
        let root = LibraryRoot(url: URL(fileURLWithPath: "/tmp/library"))
        let first = PrintFileRecord(
            rootID: root.id,
            url: URL(fileURLWithPath: "/tmp/library/cable.3mf"),
            fileName: "cable.3mf",
            relativePath: "cable.3mf",
            fileSize: 1,
            modifiedAt: Date(),
            contentHash: "same",
            projectName: "Cable Clip",
            metadata: ["Title": "Cable Clip"],
            userTags: ["desk"]
        )
        let second = PrintFileRecord(
            rootID: root.id,
            url: URL(fileURLWithPath: "/tmp/library/cable-copy.3mf"),
            fileName: "cable-copy.3mf",
            relativePath: "cable-copy.3mf",
            fileSize: 1,
            modifiedAt: Date(),
            contentHash: "same"
        )
        let snapshot = LibrarySnapshot(roots: [root], records: [first, second])
        let search = LibrarySearch()

        XCTAssertEqual(search.records(in: snapshot, matching: LibraryQuery(text: "clip", smartCollection: .all)).map(\.id), [first.id])
        XCTAssertEqual(search.records(in: snapshot, matching: LibraryQuery(text: "", smartCollection: .duplicateCandidates)).count, 2)
        XCTAssertEqual(search.records(in: snapshot, matching: LibraryQuery(text: "", smartCollection: .all, selectedTags: ["desk"])).map(\.id), [first.id])
    }

    func testSearchCanFilterByRootFolder() {
        let downloadsRoot = LibraryRoot(url: URL(fileURLWithPath: "/tmp/downloads"), displayName: "Downloads")
        let managedRoot = LibraryRoot(url: URL(fileURLWithPath: "/tmp/managed"), displayName: "Managed Library")
        let downloadsRecord = PrintFileRecord(
            rootID: downloadsRoot.id,
            url: downloadsRoot.url.appendingPathComponent("cable.3mf"),
            fileName: "cable.3mf",
            relativePath: "cable.3mf",
            fileSize: 1,
            modifiedAt: Date()
        )
        let managedRecord = PrintFileRecord(
            rootID: managedRoot.id,
            url: managedRoot.url.appendingPathComponent("hook.3mf"),
            fileName: "hook.3mf",
            relativePath: "hook.3mf",
            fileSize: 1,
            modifiedAt: Date()
        )
        let snapshot = LibrarySnapshot(roots: [downloadsRoot, managedRoot], records: [downloadsRecord, managedRecord])

        let records = LibrarySearch().records(
            in: snapshot,
            matching: LibraryQuery(text: "", smartCollection: nil, rootID: managedRoot.id)
        )

        XCTAssertEqual(records.map(\.id), [managedRecord.id])
    }

    func testSearchFiltersByPrintProfileSourceAndVersionStatus() {
        let root = LibraryRoot(url: URL(fileURLWithPath: "/tmp/library"))
        let plaRecord = PrintFileRecord(
            rootID: root.id,
            url: URL(fileURLWithPath: "/tmp/library/pla-holder.3mf"),
            fileName: "pla-holder.3mf",
            relativePath: "pla-holder.3mf",
            fileSize: 1,
            modifiedAt: Date(),
            userTags: ["garage"],
            printability: .readyToPrint,
            sourceInfo: PrintSourceInfo(platform: "MakerWorld", url: "https://makerworld.com/en/models/123"),
            printDetails: PrintDetails(materials: ["PLA"], printer: "Bambu P1S")
        )
        let petgRecord = PrintFileRecord(
            rootID: root.id,
            url: URL(fileURLWithPath: "/tmp/library/petg-hook.3mf"),
            fileName: "petg-hook.3mf",
            relativePath: "petg-hook.3mf",
            fileSize: 1,
            modifiedAt: Date(),
            metadata: ["source.versionStatus": SourceVersionStatus.possibleUpdateAvailable.rawValue],
            printability: .needsReview,
            sourceInfo: PrintSourceInfo(platform: "Printables", url: "https://www.printables.com/model/456"),
            printDetails: PrintDetails(materials: ["PETG"], printer: "Prusa MK4")
        )
        var currentPlaRecord = plaRecord
        currentPlaRecord.metadata["source.versionStatus"] = SourceVersionStatus.current.rawValue
        let snapshot = LibrarySnapshot(roots: [root], records: [currentPlaRecord, petgRecord])

        let records = LibrarySearch().records(
            in: snapshot,
            matching: LibraryQuery(
                text: "",
                smartCollection: .all,
                selectedTags: ["garage"],
                selectedPrintabilities: [.readyToPrint],
                selectedMaterials: ["PLA"],
                selectedPrinters: ["Bambu P1S"],
                selectedSourcePlatforms: ["MakerWorld"],
                selectedSourceVersionStatuses: [.current]
            )
        )

        XCTAssertEqual(records.map(\.id), [currentPlaRecord.id])
    }

    func testNeedsReviewCollectionIncludesIncompleteUpdatedAndDuplicateRecords() {
        let root = LibraryRoot(url: URL(fileURLWithPath: "/tmp/library"))
        let complete = PrintFileRecord(
            rootID: root.id,
            url: URL(fileURLWithPath: "/tmp/library/complete.3mf"),
            fileName: "complete.3mf",
            relativePath: "complete.3mf",
            fileSize: 1,
            modifiedAt: Date(),
            contentHash: "complete",
            indexingStatus: .indexed,
            previewStatus: .available,
            printability: .readyToPrint,
            sourceInfo: PrintSourceInfo(url: "https://makerworld.com/en/models/complete"),
            printDetails: PrintDetails(materials: ["PLA"], printer: "Bambu P1S")
        )
        let missingSource = PrintFileRecord(
            rootID: root.id,
            url: URL(fileURLWithPath: "/tmp/library/missing-source.3mf"),
            fileName: "missing-source.3mf",
            relativePath: "missing-source.3mf",
            fileSize: 1,
            modifiedAt: Date(),
            contentHash: "missing-source",
            indexingStatus: .indexed,
            previewStatus: .available,
            printability: .readyToPrint,
            printDetails: PrintDetails(materials: ["PLA"], printer: "Bambu P1S")
        )
        let possibleUpdate = PrintFileRecord(
            rootID: root.id,
            url: URL(fileURLWithPath: "/tmp/library/update.3mf"),
            fileName: "update.3mf",
            relativePath: "update.3mf",
            fileSize: 1,
            modifiedAt: Date(),
            contentHash: "update",
            indexingStatus: .indexed,
            previewStatus: .available,
            metadata: ["source.versionStatus": SourceVersionStatus.possibleUpdateAvailable.rawValue],
            printability: .readyToPrint,
            sourceInfo: PrintSourceInfo(url: "https://makerworld.com/en/models/update"),
            printDetails: PrintDetails(materials: ["PLA"], printer: "Bambu P1S")
        )
        let firstDuplicate = PrintFileRecord(
            rootID: root.id,
            url: URL(fileURLWithPath: "/tmp/library/duplicate-a.3mf"),
            fileName: "duplicate-a.3mf",
            relativePath: "duplicate-a.3mf",
            fileSize: 1,
            modifiedAt: Date(),
            contentHash: "same",
            indexingStatus: .indexed,
            previewStatus: .available,
            printability: .readyToPrint,
            sourceInfo: PrintSourceInfo(url: "https://makerworld.com/en/models/duplicate"),
            printDetails: PrintDetails(materials: ["PLA"], printer: "Bambu P1S")
        )
        let secondDuplicate = PrintFileRecord(
            rootID: root.id,
            url: URL(fileURLWithPath: "/tmp/library/duplicate-b.3mf"),
            fileName: "duplicate-b.3mf",
            relativePath: "duplicate-b.3mf",
            fileSize: 1,
            modifiedAt: Date(),
            contentHash: "same",
            indexingStatus: .indexed,
            previewStatus: .available,
            printability: .readyToPrint,
            sourceInfo: PrintSourceInfo(url: "https://makerworld.com/en/models/duplicate"),
            printDetails: PrintDetails(materials: ["PLA"], printer: "Bambu P1S")
        )
        let snapshot = LibrarySnapshot(roots: [root], records: [complete, missingSource, possibleUpdate, firstDuplicate, secondDuplicate])

        let records = LibrarySearch().records(in: snapshot, matching: LibraryQuery(text: "", smartCollection: .needsReview))

        XCTAssertEqual(Set(records.map(\.id)), [missingSource.id, possibleUpdate.id, firstDuplicate.id, secondDuplicate.id])
    }

    func testReviewReasonsAndSignaturesExplainDismissedReviewItems() throws {
        let root = LibraryRoot(url: URL(fileURLWithPath: "/tmp/library"))
        let record = PrintFileRecord(
            rootID: root.id,
            url: URL(fileURLWithPath: "/tmp/library/missing-source.3mf"),
            fileName: "missing-source.3mf",
            relativePath: "missing-source.3mf",
            fileSize: 1,
            modifiedAt: Date(),
            indexingStatus: .indexed,
            previewStatus: .available,
            printability: .readyToPrint,
            printDetails: PrintDetails(materials: ["PLA"], printer: "Bambu P1S")
        )
        let snapshot = LibrarySnapshot(roots: [root], records: [record])
        let search = LibrarySearch()

        XCTAssertEqual(search.reviewReasons(for: record, in: snapshot), [.missingSource])
        let signature = try XCTUnwrap(search.reviewSignature(for: record, in: snapshot))

        var reviewedRecord = record
        reviewedRecord.reviewedAt = Date(timeIntervalSince1970: 1_000)
        reviewedRecord.reviewedIssueSignature = signature
        let reviewedSnapshot = LibrarySnapshot(roots: [root], records: [reviewedRecord])

        XCTAssertTrue(search.records(in: reviewedSnapshot, matching: LibraryQuery(text: "", smartCollection: .needsReview)).isEmpty)

        var changedRecord = reviewedRecord
        changedRecord.previewStatus = .missing
        let changedSnapshot = LibrarySnapshot(roots: [root], records: [changedRecord])

        XCTAssertEqual(search.reviewReasons(for: changedRecord, in: changedSnapshot), [.missingPreview, .missingSource])
        XCTAssertEqual(search.records(in: changedSnapshot, matching: LibraryQuery(text: "", smartCollection: .needsReview)).map(\.id), [changedRecord.id])
    }

    func testSmartCollectionsExposeDefaultSortsForSidebarViews() {
        XCTAssertEqual(SmartCollection.all.defaultSortOption, .name)
        XCTAssertTrue(SmartCollection.all.defaultSortAscending)
        XCTAssertEqual(SmartCollection.needsReview.defaultSortOption, .name)
        XCTAssertTrue(SmartCollection.needsReview.defaultSortAscending)
        XCTAssertEqual(SmartCollection.recentlyAdded.defaultSortOption, .indexedDate)
        XCTAssertFalse(SmartCollection.recentlyAdded.defaultSortAscending)
        XCTAssertEqual(SmartCollection.latestEdited.defaultSortOption, .modifiedDate)
        XCTAssertFalse(SmartCollection.latestEdited.defaultSortAscending)
        XCTAssertEqual(SmartCollection.duplicateCandidates.defaultSortOption, .name)
        XCTAssertTrue(SmartCollection.duplicateCandidates.defaultSortAscending)
    }

        func testSearchSortsByModifiedDateAndLatestEditedCollection() {
                let root = LibraryRoot(url: URL(fileURLWithPath: "/tmp/library"))
                let older = PrintFileRecord(
                        rootID: root.id,
                        url: URL(fileURLWithPath: "/tmp/library/older.3mf"),
                        fileName: "older.3mf",
                        relativePath: "older.3mf",
                        fileSize: 1,
                        modifiedAt: Date(timeIntervalSince1970: 10)
                )
                let newer = PrintFileRecord(
                        rootID: root.id,
                        url: URL(fileURLWithPath: "/tmp/library/newer.3mf"),
                        fileName: "newer.3mf",
                        relativePath: "newer.3mf",
                        fileSize: 1,
                        modifiedAt: Date(timeIntervalSince1970: 20)
                )
                let undated = PrintFileRecord(
                        rootID: root.id,
                        url: URL(fileURLWithPath: "/tmp/library/undated.3mf"),
                        fileName: "undated.3mf",
                        relativePath: "undated.3mf",
                        fileSize: 1,
                        modifiedAt: nil
                )
                let snapshot = LibrarySnapshot(roots: [root], records: [older, newer, undated])
                let records = LibrarySearch().records(
                        in: snapshot,
                        matching: LibraryQuery(text: "", smartCollection: .latestEdited, sortOption: .modifiedDate, sortAscending: false)
                )

                XCTAssertEqual(records.map(\.id), [newer.id, older.id])
        }

        func testPlateAndMeshExtractorsReadSyntheticPackage() throws {
                let packageURL = try makeTemporaryDirectory().appendingPathComponent("multi-plate.3mf")
                try makePackage(at: packageURL, entries: [
                        "Metadata/plate_1.png": try makePNG(width: 32, height: 20),
                        "Metadata/plate_2.png": try makePNG(width: 20, height: 32),
                        "3D/3dmodel.model": Data("""
                        <?xml version="1.0" encoding="UTF-8"?>
                        <model unit="millimeter">
                            <resources>
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
                        </model>
                        """.utf8)
                ])

                let previews = PlatePreviewExtractor().previews(for: packageURL)
                let mesh = try XCTUnwrap(ThreeMFMeshExtractor().mesh(for: packageURL))

                XCTAssertEqual(previews.map(\.title), ["Plate 1", "Plate 2"])
                XCTAssertEqual(mesh.vertices.count, 3)
                XCTAssertEqual(mesh.triangles, [ThreeMFTriangle(a: 0, b: 1, c: 2)])
        }

            func testOrganizationPlannerBuildsManagedFolderStructureAndCopiesFiles() throws {
                let sourceRoot = try makeTemporaryDirectory()
                let targetRoot = try makeTemporaryDirectory()
                let sourceURL = sourceRoot.appendingPathComponent("EV Charger Cable and Plug Holder 90 Degrees.3mf")
                try Data("fixture".utf8).write(to: sourceURL)
                let record = PrintFileRecord(
                    rootID: UUID(),
                    url: sourceURL,
                    fileName: sourceURL.lastPathComponent,
                    relativePath: sourceURL.lastPathComponent,
                    fileSize: 7,
                    modifiedAt: Date(),
                    indexingStatus: .indexed,
                    projectName: "EV Charger Cable and Plug Holder 90 Degrees",
                    userTags: ["garage"]
                )

                let planner = OrganizationPlanner()
                let plan = planner.planCopy(records: [record], to: targetRoot)

                XCTAssertEqual(plan.actions.count, 1)
                let destination = try XCTUnwrap(plan.actions.first?.destinationURL)
                XCTAssertEqual(destination.path, targetRoot.appendingPathComponent("garage/EV Charger Cable and Plug Holder 90 Degrees/EV Charger Cable and Plug Holder 90 Degrees.3mf").path)

                planner.execute(plan)

                XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
                XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
            }

            func testOrganizationPlannerBuildsManagedFolderStructureAndMovesFiles() throws {
                let sourceRoot = try makeTemporaryDirectory()
                let targetRoot = try makeTemporaryDirectory()
                let sourceURL = sourceRoot.appendingPathComponent("wall-hook.3mf")
                try Data("fixture".utf8).write(to: sourceURL)
                let record = PrintFileRecord(
                    rootID: UUID(),
                    url: sourceURL,
                    fileName: sourceURL.lastPathComponent,
                    relativePath: sourceURL.lastPathComponent,
                    fileSize: 7,
                    modifiedAt: Date(),
                    indexingStatus: .indexed,
                    projectName: "Wall Hook",
                    userTags: ["garage"]
                )

                let planner = OrganizationPlanner()
                let plan = planner.planMove(records: [record], to: targetRoot)

                XCTAssertEqual(plan.actions.count, 1)
                XCTAssertEqual(plan.actions.first?.kind, .move)
                let destination = try XCTUnwrap(plan.actions.first?.destinationURL)

                planner.execute(plan)

                XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
                XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))
            }

            func testOrganizationPlannerUsesAIRecommendedSubfolders() throws {
                let sourceRoot = try makeTemporaryDirectory()
                let targetRoot = try makeTemporaryDirectory()
                let sourceURL = sourceRoot.appendingPathComponent("10 pc Build Plate Rack Bambu X1 P1.3mf")
                try Data("fixture".utf8).write(to: sourceURL)
                let recordID = UUID()
                let record = PrintFileRecord(
                    id: recordID,
                    rootID: UUID(),
                    url: sourceURL,
                    fileName: sourceURL.lastPathComponent,
                    relativePath: sourceURL.lastPathComponent,
                    fileSize: 7,
                    modifiedAt: Date(),
                    indexingStatus: .indexed,
                    projectName: "10 pc Build Plate Rack Bambu X1 P1",
                    category: "Functional Part"
                )
                let suggestion = OrganizationSuggestion(
                    recordID: recordID,
                    relativePath: "Printer Accessories/Storage/Build Plate Racks/10 pc Build Plate Rack Bambu X1 P1.3mf",
                    rationale: "Build plate rack belongs under printer accessory storage."
                )

                let plan = OrganizationPlanner().planCopy(records: [record], to: targetRoot, suggestions: [suggestion])
                let destination = try XCTUnwrap(plan.actions.first?.destinationURL)

                XCTAssertEqual(destination.path, targetRoot.appendingPathComponent("Printer Accessories/Storage/Build Plate Racks/10 pc Build Plate Rack Bambu X1 P1.3mf").path)
                XCTAssertEqual(plan.actions.first?.reason, "Build plate rack belongs under printer accessory storage.")
            }

            func testOrganizationPlannerMovesFilesAlreadyInsideManagedFolder() throws {
                let targetRoot = try makeTemporaryDirectory()
                let oldFolder = targetRoot.appendingPathComponent("Functional Part/10 pc Build Plate Rack Bambu X1 P1", isDirectory: true)
                try FileManager.default.createDirectory(at: oldFolder, withIntermediateDirectories: true)
                let sourceURL = oldFolder.appendingPathComponent("10 pc Build Plate Rack Bambu X1 P1.3mf")
                try Data("fixture".utf8).write(to: sourceURL)
                let recordID = UUID()
                let record = PrintFileRecord(
                    id: recordID,
                    rootID: UUID(),
                    url: sourceURL,
                    fileName: sourceURL.lastPathComponent,
                    relativePath: "Functional Part/10 pc Build Plate Rack Bambu X1 P1/10 pc Build Plate Rack Bambu X1 P1.3mf",
                    fileSize: 7,
                    modifiedAt: Date(),
                    indexingStatus: .indexed,
                    projectName: "10 pc Build Plate Rack Bambu X1 P1"
                )
                let suggestion = OrganizationSuggestion(
                    recordID: recordID,
                    relativePath: "Printer Accessories/Storage/Build Plate Racks/10 pc Build Plate Rack Bambu X1 P1.3mf",
                    rationale: "Reuse the existing printer accessory storage structure."
                )

                let plan = OrganizationPlanner().planMove(records: [record], to: targetRoot, suggestions: [suggestion])
                let destination = try XCTUnwrap(plan.actions.first?.destinationURL)

                XCTAssertEqual(plan.actions.count, 1)
                XCTAssertEqual(destination.path, targetRoot.appendingPathComponent("Printer Accessories/Storage/Build Plate Racks/10 pc Build Plate Rack Bambu X1 P1.3mf").path)

                try OrganizationPlanner().execute(plan)

                XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))
                XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
            }

            func testOrganizationPlannerCopiesFilesAlreadyInsideManagedFolder() throws {
                let targetRoot = try makeTemporaryDirectory()
                let oldFolder = targetRoot.appendingPathComponent("Functional Part/Wall Hook", isDirectory: true)
                try FileManager.default.createDirectory(at: oldFolder, withIntermediateDirectories: true)
                let sourceURL = oldFolder.appendingPathComponent("Wall Hook.3mf")
                try Data("fixture".utf8).write(to: sourceURL)
                let recordID = UUID()
                let record = PrintFileRecord(
                    id: recordID,
                    rootID: UUID(),
                    url: sourceURL,
                    fileName: sourceURL.lastPathComponent,
                    relativePath: "Functional Part/Wall Hook/Wall Hook.3mf",
                    fileSize: 7,
                    modifiedAt: Date(),
                    indexingStatus: .indexed,
                    projectName: "Wall Hook"
                )
                let suggestion = OrganizationSuggestion(
                    recordID: recordID,
                    relativePath: "Household/Hooks/Wall Hook.3mf",
                    rationale: "Wall hooks belong with household hooks."
                )

                let plan = OrganizationPlanner().planCopy(records: [record], to: targetRoot, suggestions: [suggestion])
                let destination = try XCTUnwrap(plan.actions.first?.destinationURL)

                XCTAssertEqual(plan.actions.count, 1)

                try OrganizationPlanner().execute(plan)

                XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
                XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
            }

            func testOrganizationPlannerSkipsManagedFilesAlreadyAtSuggestedPath() throws {
                let targetRoot = try makeTemporaryDirectory()
                let folder = targetRoot.appendingPathComponent("Printer Accessories/Storage/Build Plate Racks", isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let sourceURL = folder.appendingPathComponent("10 pc Build Plate Rack Bambu X1 P1.3mf")
                try Data("fixture".utf8).write(to: sourceURL)
                let recordID = UUID()
                let record = PrintFileRecord(
                    id: recordID,
                    rootID: UUID(),
                    url: sourceURL,
                    fileName: sourceURL.lastPathComponent,
                    relativePath: "Printer Accessories/Storage/Build Plate Racks/10 pc Build Plate Rack Bambu X1 P1.3mf",
                    fileSize: 7,
                    modifiedAt: Date(),
                    indexingStatus: .indexed,
                    projectName: "10 pc Build Plate Rack Bambu X1 P1"
                )
                let suggestion = OrganizationSuggestion(
                    recordID: recordID,
                    relativePath: "Printer Accessories/Storage/Build Plate Racks/10 pc Build Plate Rack Bambu X1 P1.3mf",
                    rationale: "Already correctly sorted."
                )

                let plan = OrganizationPlanner().planMove(records: [record], to: targetRoot, suggestions: [suggestion])

                XCTAssertEqual(plan.actions.count, 0)
                XCTAssertEqual(plan.skippedCount, 1)
            }

    func testSearchIgnoresFillerWordsSoNaturalPhrasingWorks() {
        let root = LibraryRoot(url: URL(fileURLWithPath: "/tmp/library"))
        let matching = PrintFileRecord(
            rootID: root.id,
            url: URL(fileURLWithPath: "/tmp/library/bracket.3mf"),
            fileName: "bracket.3mf",
            relativePath: "bracket.3mf",
            fileSize: 1,
            modifiedAt: nil,
            metadata: ["material": "PLA", "printer": "Bambu P1S"]
        )
        let other = PrintFileRecord(
            rootID: root.id,
            url: URL(fileURLWithPath: "/tmp/library/vase.3mf"),
            fileName: "vase.3mf",
            relativePath: "vase.3mf",
            fileSize: 1,
            modifiedAt: nil,
            metadata: ["material": "PETG", "printer": "Prusa MK4"]
        )
        let snapshot = LibrarySnapshot(roots: [root], records: [matching, other])

        // This phrasing previously matched nothing, because "files" and "for" appear in no record.
        let results = LibrarySearch().records(
            in: snapshot,
            matching: LibraryQuery(text: "PLA files for Bambu P1S", sortOption: .name)
        )

        XCTAssertEqual(results.map(\.fileName), ["bracket.3mf"])
    }

    func testSearchStillMatchesFillerWordsWhenThatIsAllTheUserTyped() {
        let root = LibraryRoot(url: URL(fileURLWithPath: "/tmp/library"))
        let record = PrintFileRecord(
            rootID: root.id,
            url: URL(fileURLWithPath: "/tmp/library/print-guide.3mf"),
            fileName: "print-guide.3mf",
            relativePath: "print-guide.3mf",
            fileSize: 1,
            modifiedAt: nil
        )
        let other = PrintFileRecord(
            rootID: root.id,
            url: URL(fileURLWithPath: "/tmp/library/vase.3mf"),
            fileName: "vase.3mf",
            relativePath: "vase.3mf",
            fileSize: 1,
            modifiedAt: nil
        )
        let snapshot = LibrarySnapshot(roots: [root], records: [record, other])

        // A query made only of filler must still filter, not silently show everything.
        let results = LibrarySearch().records(
            in: snapshot,
            matching: LibraryQuery(text: "print", sortOption: .name)
        )

        XCTAssertEqual(results.map(\.fileName), ["print-guide.3mf"])
    }

    func testSearchTermsDropFillerButKeepMeaningfulWords() {
        XCTAssertEqual(LibrarySearch.searchTerms(in: "pla files for bambu p1s").map(String.init), ["pla", "bambu", "p1s"])
        XCTAssertEqual(LibrarySearch.searchTerms(in: "the and for").map(String.init), ["the", "and", "for"])
        XCTAssertTrue(LibrarySearch.searchTerms(in: "").isEmpty)
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
