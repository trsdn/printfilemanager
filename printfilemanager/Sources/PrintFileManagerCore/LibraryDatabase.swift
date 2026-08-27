import Foundation

public final class LibraryDatabase {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func applicationSupport() throws -> LibraryDatabase {
        let baseURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let folderURL = baseURL.appendingPathComponent("Print File Manager", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        return LibraryDatabase(fileURL: folderURL.appendingPathComponent("library-index.json"))
    }

    public func load() throws -> LibrarySnapshot {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return LibrarySnapshot()
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LibrarySnapshot.self, from: data)
    }

    public func save(_ snapshot: LibrarySnapshot) throws {
        let folderURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        var updatedSnapshot = snapshot
        updatedSnapshot.updatedAt = Date()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(updatedSnapshot)
        try data.write(to: fileURL, options: [.atomic])
    }

    public func upsert(root: LibraryRoot, into snapshot: LibrarySnapshot) -> LibrarySnapshot {
        var next = snapshot
        if let index = next.roots.firstIndex(where: { $0.id == root.id || $0.url == root.url }) {
            var mergedRoot = root
            mergedRoot.id = next.roots[index].id
            next.roots[index] = mergedRoot
        } else {
            next.roots.append(root)
        }
        next.updatedAt = Date()
        return next
    }

    public func merge(scanResult: LibraryScanResult, into snapshot: LibrarySnapshot) -> LibrarySnapshot {
        var next = snapshot
        var rootsByID = Dictionary(uniqueKeysWithValues: next.roots.map { ($0.id, $0) })
        var root = scanResult.root
        root.lastScannedAt = scanResult.scannedAt
        root.isAvailable = scanResult.rootIsAvailable
        rootsByID[root.id] = root
        next.roots = rootsByID.values.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }

        let oldRecords = next.records
        let existingByPath = Dictionary(uniqueKeysWithValues: oldRecords.map { ($0.url.standardizedFileURL.path, $0) })
        let existingByHash = Dictionary(grouping: oldRecords.compactMap { record -> (String, PrintFileRecord)? in
            guard let hash = record.contentHash else { return nil }
            return (hash, record)
        }, by: \.0)
        var scannedPaths = Set<String>()

        let mergedScannedRecords = scanResult.records.map { scannedRecord -> PrintFileRecord in
            scannedPaths.insert(scannedRecord.url.standardizedFileURL.path)
            let existing = existingByPath[scannedRecord.url.standardizedFileURL.path]
                ?? scannedRecord.contentHash.flatMap { existingByHash[$0]?.first?.1 }

            guard let existing else {
                return scannedRecord
            }

            var merged = scannedRecord
            merged.id = existing.id
            merged.userTags = existing.userTags
            merged.generatedTags = mergeGeneratedTags(existing: existing.generatedTags, scanned: scannedRecord.generatedTags)
            merged.notes = existing.notes
            merged.projectKey = existing.projectKey ?? scannedRecord.projectKey
            merged.variantName = existing.variantName ?? scannedRecord.variantName
            merged.category = existing.category ?? scannedRecord.category
            merged.printability = existing.printability ?? scannedRecord.printability
            merged.sourceInfo = mergeSourceInfo(existing: existing.sourceInfo, scanned: scannedRecord.sourceInfo)
            merged.printDetails = scannedRecord.printDetails ?? existing.printDetails
            merged.printHistory = existing.printHistory ?? scannedRecord.printHistory
            merged.reviewedAt = existing.reviewedAt
            merged.reviewedIssueSignature = existing.reviewedIssueSignature
            return merged
        }

        let unchangedOtherRootRecords = oldRecords.filter { $0.rootID != scanResult.root.id }
        let missingRecords = oldRecords
            .filter { $0.rootID == scanResult.root.id && !scannedPaths.contains($0.url.standardizedFileURL.path) }
            .map { record -> PrintFileRecord in
                var missing = record
                missing.indexingStatus = .missing
                missing.errorMessage = "File was not found during the latest scan."
                return missing
            }

        next.records = (unchangedOtherRootRecords + mergedScannedRecords + missingRecords)
            .sorted { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending }
        next.updatedAt = Date()
        return next
    }

    private func mergeGeneratedTags(existing: [GeneratedTag], scanned: [GeneratedTag]) -> [GeneratedTag] {
        let scannedValues = Set(scanned.map { $0.value.lowercased() })
        let preservedExisting = existing.filter { tag in
            tag.source != "local" || tag.state != .suggested || scannedValues.contains(tag.value.lowercased())
        }
        var byValue = Dictionary(uniqueKeysWithValues: preservedExisting.map { ($0.value.lowercased(), $0) })
        for tag in scanned where byValue[tag.value.lowercased()] == nil {
            byValue[tag.value.lowercased()] = tag
        }
        return byValue.values.sorted { $0.value.localizedStandardCompare($1.value) == .orderedAscending }
    }

    private func mergeSourceInfo(existing: PrintSourceInfo?, scanned: PrintSourceInfo?) -> PrintSourceInfo? {
        guard let existing else { return scanned }
        guard let scanned else { return existing }

        return PrintSourceInfo(
            platform: existing.platform ?? scanned.platform,
            author: existing.author ?? scanned.author,
            license: existing.license ?? scanned.license,
            url: existing.url ?? scanned.url,
            downloadedAt: existing.downloadedAt ?? scanned.downloadedAt
        )
    }
}