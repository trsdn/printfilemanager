import Foundation

public final class LibraryDatabase {
    public let fileURL: URL
    private let thumbnailStore: ThumbnailStore?

    /// Set once a `.bak` has been written for this session, so the backup captures the last
    /// known-good state rather than being overwritten by every subsequent save.
    private var hasWrittenSessionBackup = false

    public init(fileURL: URL, thumbnailStore: ThumbnailStore? = nil) {
        self.fileURL = fileURL
        self.thumbnailStore = thumbnailStore
    }

    public static func applicationSupport() throws -> LibraryDatabase {
        let folderURL = try ApplicationSupportLocation.supportDirectory()
        return LibraryDatabase(
            fileURL: folderURL.appendingPathComponent("library-index.json"),
            thumbnailStore: ThumbnailStore(directoryURL: folderURL.appendingPathComponent("Thumbnails", isDirectory: true))
        )
    }

    public func load() throws -> LibrarySnapshot {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return LibrarySnapshot()
        }

        var data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let storedVersion = try Self.schemaVersion(in: data)
        guard storedVersion <= LibrarySnapshot.currentSchemaVersion else {
            throw LibrarySchemaError.unsupportedSchemaVersion(
                found: storedVersion,
                supported: LibrarySnapshot.currentSchemaVersion
            )
        }

        if storedVersion < 2 {
            data = try migrateEmbeddedThumbnails(in: data)
        }

        var snapshot = try decoder.decode(LibrarySnapshot.self, from: data)
        snapshot.schemaVersion = LibrarySnapshot.currentSchemaVersion
        return snapshot
    }

    /// Reads the schema version without decoding the whole document, so a version that this build
    /// cannot represent is rejected before the typed decode fails on unfamiliar fields.
    private static func schemaVersion(in data: Data) throws -> Int {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LibrarySchemaError.unreadableIndex
        }
        return object["schemaVersion"] as? Int ?? 1
    }

    /// Schema 1 stored preview images as base64 inside every record. This moves them into the
    /// thumbnail store and replaces them with a key, which is what shrinks the index.
    private func migrateEmbeddedThumbnails(in data: Data) throws -> Data {
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var records = object["records"] as? [[String: Any]] else {
            throw LibrarySchemaError.unreadableIndex
        }

        for index in records.indices {
            guard let encodedImage = records[index]["thumbnailData"] as? String else { continue }
            records[index]["thumbnailData"] = nil

            guard let imageData = Data(base64Encoded: encodedImage), !imageData.isEmpty else { continue }
            // Without a store there is nowhere to put the image, so the record simply loses its
            // cached preview and will regenerate one on the next scan.
            if let key = try? thumbnailStore?.store(imageData) {
                records[index]["thumbnailKey"] = key
            }
        }

        object["records"] = records
        object["schemaVersion"] = LibrarySnapshot.currentSchemaVersion
        return try JSONSerialization.data(withJSONObject: object)
    }

    /// Moves an index file that could not be decoded out of the way so it is never overwritten,
    /// and returns the location it was preserved at.
    @discardableResult
    public func quarantineUnreadableIndex() throws -> URL? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let timestamp = DateFormatter.quarantineFormatter.string(from: Date())
        let quarantineURL = fileURL
            .deletingPathExtension()
            .appendingPathExtension("corrupt-\(timestamp)")
            .appendingPathExtension("json")

        try FileManager.default.moveItem(at: fileURL, to: quarantineURL)
        return quarantineURL
    }

    public func save(_ snapshot: LibrarySnapshot) throws {
        let folderURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        try writeSessionBackupIfNeeded()

        var updatedSnapshot = snapshot
        updatedSnapshot.updatedAt = Date()
        updatedSnapshot.schemaVersion = LibrarySnapshot.currentSchemaVersion

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(updatedSnapshot)
        try data.write(to: fileURL, options: [.atomic])
    }

    private func writeSessionBackupIfNeeded() throws {
        guard !hasWrittenSessionBackup, FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }

        let backupURL = fileURL.appendingPathExtension("bak")
        if FileManager.default.fileExists(atPath: backupURL.path) {
            guard Self.backup(at: backupURL, isSupersededBy: fileURL) else {
                // The existing backup carries records this one does not. Replacing it would make
                // the only recoverable copy the poorer of the two, so this session goes without a
                // backup instead. A stale backup can be replaced later; a discarded one cannot.
                hasWrittenSessionBackup = true
                return
            }
        }
        let data = try Data(contentsOf: fileURL)
        try data.write(to: backupURL, options: [.atomic])
        hasWrittenSessionBackup = true
    }

    /// Whether `candidate` can replace the backup at `backupURL` without losing anything.
    ///
    /// Decided on records rather than bytes. Bytes shrink legitimately — moving preview images out
    /// of the index into the content-addressed store took a real library from 114 MB to 3 MB
    /// without dropping a single record — so a size rule would freeze the backup forever at the
    /// first migration. What must never happen is a backup that knows about files the replacement
    /// has forgotten.
    private static func backup(at backupURL: URL, isSupersededBy candidate: URL) -> Bool {
        guard let replacement = LegacyLibraryLocator.recordIdentifiers(at: candidate) else {
            return false
        }
        guard let existing = LegacyLibraryLocator.recordIdentifiers(at: backupURL) else {
            // An unreadable backup protects nothing, so there is nothing to lose by replacing it.
            return true
        }
        return existing.isSubset(of: replacement)
    }
}

private extension DateFormatter {
    /// Compact, colon-free timestamp so quarantined files stay readable in Finder.
    static let quarantineFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}

extension LibraryDatabase {

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

        // A scan cannot establish whether a copy in another root moved or still exists.
        // Match only within this root, even when roots overlap or share content hashes.
        let oldRecords = next.records.filter { $0.rootID == root.id }
        let unchangedOtherRootRecords = next.records.filter { $0.rootID != root.id }
        let existingByPath = Dictionary(grouping: oldRecords, by: { $0.url.standardizedFileURL.path })
        let existingByHash = Dictionary(grouping: oldRecords.compactMap { record -> (String, PrintFileRecord)? in
            guard let hash = record.contentHash else { return nil }
            return (hash, record)
        }, by: \.0)
        var scannedPaths = Set<String>()

        // Historical IDs are not unique. Track matched paths so distinct copies keep their own
        // annotations and only a record actually matched as a move is removed from its old path.
        var claimedPaths = Set<String>()
        var matches: [Int: PrintFileRecord] = [:]

        // Paths are unique and exact, so they are resolved before any content-hash guess.
        for (index, scannedRecord) in scanResult.records.enumerated() {
            let path = scannedRecord.url.standardizedFileURL.path
            scannedPaths.insert(path)
            guard let existing = existingByPath[path]?.first else { continue }
            matches[index] = existing
            claimedPaths.insert(path)
        }

        // A file that moved keeps its identity, but only if nothing else has taken it already.
        for (index, scannedRecord) in scanResult.records.enumerated() where matches[index] == nil {
            guard let hash = scannedRecord.contentHash,
                  let existing = existingByHash[hash]?.lazy.map(\.1).first(where: {
                      !claimedPaths.contains($0.url.standardizedFileURL.path)
                  })
            else { continue }
            matches[index] = existing
            claimedPaths.insert(existing.url.standardizedFileURL.path)
        }

        let mergedScannedRecords = scanResult.records.enumerated().map { index, scannedRecord -> PrintFileRecord in
            guard let existing = matches[index] else {
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

        let missingRecords = oldRecords
            .filter {
                let path = $0.url.standardizedFileURL.path
                return !scannedPaths.contains(path) && !claimedPaths.contains(path)
            }
            .map { record -> PrintFileRecord in
                var missing = record
                missing.indexingStatus = .missing
                missing.errorMessage = "File was not found during the latest scan."
                return missing
            }

        // Cached scan records retain their old IDs. Mint replacements explicitly, including for
        // missing records, without changing any record belonging to an unscanned root.
        var usedIDs = Set(unchangedOtherRootRecords.map(\.id))
        let uniqueRootRecords = (mergedScannedRecords + missingRecords).map { record in
            var unique = record
            while !usedIDs.insert(unique.id).inserted {
                unique.id = UUID()
            }
            return unique
        }
        next.records = (unchangedOtherRootRecords + uniqueRootRecords)
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
