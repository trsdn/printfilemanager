import Foundation

public struct LibrarySearch {
    public init() {}

    public func reviewReasons(for record: PrintFileRecord, in snapshot: LibrarySnapshot) -> [ReviewReason] {
        reviewReasons(for: record, duplicateContentHashCounts: duplicateContentHashCounts(in: snapshot.records))
    }

    public func reviewSignature(for record: PrintFileRecord, in snapshot: LibrarySnapshot) -> String? {
        let duplicateContentHashCounts = duplicateContentHashCounts(in: snapshot.records)
        let reasons = reviewReasons(for: record, duplicateContentHashCounts: duplicateContentHashCounts)
        guard !reasons.isEmpty else { return nil }
        return reviewSignature(
            for: record,
            reasons: reasons,
            duplicateCount: duplicateCount(for: record, duplicateContentHashCounts: duplicateContentHashCounts)
        )
    }

    public func records(in snapshot: LibrarySnapshot, matching query: LibraryQuery) -> [PrintFileRecord] {
        sort(filteredRecords(in: snapshot, matching: query), option: query.sortOption, ascending: query.sortAscending)
    }

    /// Counts matches without sorting them.
    ///
    /// The sidebar asks for a count per collection and per root on every snapshot change; sorting
    /// results that are only going to be counted was the single largest cost in that path.
    public func count(in snapshot: LibrarySnapshot, matching query: LibraryQuery) -> Int {
        filteredRecords(in: snapshot, matching: query).count
    }

    /// Counts every smart collection in one pass, sharing the duplicate-hash tally between them.
    public func collectionCounts(in snapshot: LibrarySnapshot) -> [SmartCollection: Int] {
        let duplicateContentHashCounts = duplicateContentHashCounts(in: snapshot.records)
        var counts: [SmartCollection: Int] = [:]

        for collection in SmartCollection.allCases {
            counts[collection] = snapshot.records.count { record in
                matchesSmartCollection(
                    record,
                    collection: collection,
                    duplicateContentHashCounts: duplicateContentHashCounts
                )
            }
        }

        return counts
    }

    private func filteredRecords(in snapshot: LibrarySnapshot, matching query: LibraryQuery) -> [PrintFileRecord] {
        let duplicateContentHashCounts = duplicateContentHashCounts(in: snapshot.records)
        let normalizedText = query.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return snapshot.records.filter { record in
            matchesRoot(record, rootID: query.rootID)
                && matchesSmartCollection(record, collection: query.smartCollection, duplicateContentHashCounts: duplicateContentHashCounts)
                && matchesTags(record, selectedTags: query.selectedTags)
                && matchesPrintability(record, selectedPrintabilities: query.selectedPrintabilities)
                && matchesMaterials(record, selectedMaterials: query.selectedMaterials)
                && matchesPrinters(record, selectedPrinters: query.selectedPrinters)
                && matchesSourcePlatforms(record, selectedSourcePlatforms: query.selectedSourcePlatforms)
                && matchesSourceVersionStatuses(record, selectedStatuses: query.selectedSourceVersionStatuses)
                && matchesText(record, normalizedText: normalizedText)
        }
    }

    private func matchesRoot(_ record: PrintFileRecord, rootID: UUID?) -> Bool {
        guard let rootID else { return true }
        return record.rootID == rootID
    }

    private func matchesSmartCollection(
        _ record: PrintFileRecord,
        collection: SmartCollection?,
        duplicateContentHashCounts: [String: Int]
    ) -> Bool {
        switch collection ?? .all {
        case .all:
            return true
        case .needsReview:
            return needsReview(record, duplicateContentHashCounts: duplicateContentHashCounts)
        case .recentlyAdded:
            guard let indexedAt = record.indexedAt else { return false }
            let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? .distantPast
            return indexedAt >= cutoff
        case .latestEdited:
            return record.modifiedAt != nil
        case .untagged:
            return record.userTags.isEmpty && record.generatedTags.filter { $0.state == .accepted }.isEmpty
        case .missingPreview:
            return record.previewStatus != .available
        case .indexingErrors:
            return record.indexingStatus == .failed || record.indexingStatus == .missing
        case .duplicateCandidates:
            return duplicateCount(for: record, duplicateContentHashCounts: duplicateContentHashCounts) > 1
        }
    }

    private func matchesTags(_ record: PrintFileRecord, selectedTags: Set<String>) -> Bool {
        guard !selectedTags.isEmpty else { return true }
        let availableTags = Set((record.userTags + record.generatedTags.filter { $0.state == .accepted }.map(\.value)).map { $0.lowercased() })
        return selectedTags.allSatisfy { availableTags.contains($0.lowercased()) }
    }

    private func matchesPrintability(_ record: PrintFileRecord, selectedPrintabilities: Set<PrintabilityStatus>) -> Bool {
        guard !selectedPrintabilities.isEmpty else { return true }
        guard let printability = record.printability else { return false }
        return selectedPrintabilities.contains(printability)
    }

    private func matchesMaterials(_ record: PrintFileRecord, selectedMaterials: Set<String>) -> Bool {
        guard !selectedMaterials.isEmpty else { return true }
        let availableMaterials = materialValues(for: record)
        return selectedMaterials.contains { availableMaterials.contains($0.lowercased()) }
    }

    private func matchesPrinters(_ record: PrintFileRecord, selectedPrinters: Set<String>) -> Bool {
        guard !selectedPrinters.isEmpty else { return true }
        let availablePrinters = printerValues(for: record)
        return selectedPrinters.contains { availablePrinters.contains($0.lowercased()) }
    }

    private func matchesSourcePlatforms(_ record: PrintFileRecord, selectedSourcePlatforms: Set<String>) -> Bool {
        guard !selectedSourcePlatforms.isEmpty else { return true }
        let platform = record.sourceInfo?.platform?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let platform, !platform.isEmpty else { return false }
        return selectedSourcePlatforms.contains { platform == $0.lowercased() }
    }

    private func matchesSourceVersionStatuses(_ record: PrintFileRecord, selectedStatuses: Set<SourceVersionStatus>) -> Bool {
        guard !selectedStatuses.isEmpty else { return true }
        let status = sourceVersionStatus(for: record)
        return selectedStatuses.contains(status)
    }

    private func matchesText(_ record: PrintFileRecord, normalizedText: String) -> Bool {
        let terms = Self.searchTerms(in: normalizedText)
        guard !terms.isEmpty else { return true }
        let haystack = Self.searchIndexCache.haystack(for: record)
        return terms.allSatisfy { haystack.contains($0) }
    }

    /// Filler words that carry no meaning in a library query.
    ///
    /// Every term has to appear in a record for it to match, so a phrase people actually type —
    /// "PLA files for Bambu P1S" — used to return nothing, because "files" and "for" are not in
    /// any record's text. Dropping them makes natural phrasing behave the way users expect
    /// without pretending to parse language.
    private static let stopWords: Set<String> = [
        "a", "an", "and", "any", "are", "as", "at", "be", "but", "by", "file", "files", "find",
        "for", "from", "has", "have", "in", "is", "it", "me", "my", "of", "on", "or", "print",
        "printed", "show", "that", "the", "then", "to", "with"
    ]

    /// Splits a query into the terms a record actually has to contain.
    ///
    /// If the query is nothing but filler, every term is kept — otherwise typing "files" would
    /// silently show the whole library rather than telling the user nothing matched.
    static func searchTerms(in normalizedText: String) -> [Substring] {
        let tokens = normalizedText.split(separator: " ").filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return [] }

        let meaningful = tokens.filter { !stopWords.contains(String($0)) }
        return meaningful.isEmpty ? tokens : meaningful
    }

    /// Caches each record's lowercased searchable text.
    ///
    /// Building it means joining roughly 25 fields and lowercasing the result; doing that for
    /// every record on every query dominated search time on large libraries. The cache is keyed by
    /// record identity and invalidated whenever the record itself changes.
    private final class SearchIndexCache: @unchecked Sendable {
        private struct Entry {
            let record: PrintFileRecord
            let haystack: String
        }

        private let lock = NSLock()
        private var entries: [UUID: Entry] = [:]

        func haystack(for record: PrintFileRecord) -> String {
            lock.lock()
            defer { lock.unlock() }

            if let entry = entries[record.id], entry.record == record {
                return entry.haystack
            }

            let haystack = Self.build(for: record).lowercased()
            // Bound the cache so a huge library cannot grow it without limit.
            if entries.count > 20_000 { entries.removeAll(keepingCapacity: true) }
            entries[record.id] = Entry(record: record, haystack: haystack)
            return haystack
        }

        private static func build(for record: PrintFileRecord) -> String {
            var parts = [
                record.fileName,
                record.relativePath,
                record.projectName ?? "",
                record.projectKey ?? "",
                record.variantName ?? "",
                record.category ?? "",
                record.printability?.title ?? "",
                record.sourceInfo?.platform ?? "",
                record.sourceInfo?.author ?? "",
                record.sourceInfo?.license ?? "",
                record.sourceInfo?.url ?? "",
                record.notes
            ]
            if let printDetails = record.printDetails {
                parts.append(contentsOf: printDetails.materials)
                parts.append(contentsOf: printDetails.colors)
                parts.append(printDetails.slicer ?? "")
                parts.append(printDetails.printer ?? "")
            }
            if let printHistory = record.printHistory {
                for entry in printHistory {
                    parts.append(contentsOf: [entry.printer, entry.material, entry.result, entry.notes])
                }
            }
            parts.append(contentsOf: record.userTags)
            parts.append(contentsOf: record.generatedTags.map(\.value))
            parts.append(contentsOf: record.sourceHints)
            parts.append(contentsOf: record.metadata.keys)
            parts.append(contentsOf: record.metadata.values)
            return parts.joined(separator: " ")
        }
    }

    private static let searchIndexCache = SearchIndexCache()

    func searchableText(for record: PrintFileRecord) -> String {
        Self.searchIndexCache.haystack(for: record)
    }

    private func needsReview(_ record: PrintFileRecord, duplicateContentHashCounts: [String: Int]) -> Bool {
        let reasons = reviewReasons(for: record, duplicateContentHashCounts: duplicateContentHashCounts)
        guard !reasons.isEmpty else { return false }
        let signature = reviewSignature(
            for: record,
            reasons: reasons,
            duplicateCount: duplicateCount(for: record, duplicateContentHashCounts: duplicateContentHashCounts)
        )
        return record.reviewedIssueSignature != signature
    }

    private func reviewReasons(for record: PrintFileRecord, duplicateContentHashCounts: [String: Int]) -> [ReviewReason] {
        var reasons: [ReviewReason] = []

        if record.indexingStatus == .failed || record.indexingStatus == .missing {
            reasons.append(.fileUnavailable)
        }
        if record.previewStatus != .available {
            reasons.append(.missingPreview)
        }
        if record.printability == .needsReview {
            reasons.append(.printabilityNeedsReview)
        }
        if record.generatedTags.contains(where: { $0.state == .suggested }) {
            reasons.append(.pendingTagSuggestions)
        }
        if sourceVersionStatus(for: record) == .possibleUpdateAvailable {
            reasons.append(.possibleSourceUpdate)
        }
        if hasMissingSource(record) {
            reasons.append(.missingSource)
        }
        if hasMissingPrintProfile(record) {
            reasons.append(.missingPrintProfile)
        }
        if duplicateCount(for: record, duplicateContentHashCounts: duplicateContentHashCounts) > 1 {
            reasons.append(.duplicateCandidate)
        }

        return reasons
    }

    private func reviewSignature(for record: PrintFileRecord, reasons: [ReviewReason], duplicateCount: Int) -> String {
        [
            "reasons:\(reasons.map(\.rawValue).sorted().joined(separator: ","))",
            "index:\(record.indexingStatus.rawValue)",
            "preview:\(record.previewStatus.rawValue)",
            "printability:\(record.printability?.rawValue ?? "unknown")",
            "source:\(record.sourceInfo?.url?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")",
            "version:\(sourceVersionStatus(for: record).rawValue)",
            "materials:\(materialValues(for: record).sorted().joined(separator: ","))",
            "printers:\(printerValues(for: record).sorted().joined(separator: ","))",
            "suggestions:\(record.generatedTags.filter { $0.state == .suggested }.count)",
            "hash:\(record.contentHash ?? "")",
            "duplicates:\(duplicateCount)"
        ].joined(separator: "|")
    }

    private func hasMissingSource(_ record: PrintFileRecord) -> Bool {
        guard let url = record.sourceInfo?.url?.trimmingCharacters(in: .whitespacesAndNewlines) else { return true }
        return url.isEmpty
    }

    private func hasMissingPrintProfile(_ record: PrintFileRecord) -> Bool {
        let details = record.printDetails
        let printer = details?.printer?.trimmingCharacters(in: .whitespacesAndNewlines)
        return printer?.isEmpty != false || materialValues(for: record).isEmpty
    }

    private func materialValues(for record: PrintFileRecord) -> Set<String> {
        var values = record.printDetails?.materials ?? []
        if let aiMaterialHints = record.metadata["ai.materialHints"] {
            values.append(contentsOf: aiMaterialHints.components(separatedBy: ","))
        }
        return normalizedValues(values)
    }

    private func printerValues(for record: PrintFileRecord) -> Set<String> {
        var values: [String] = []
        if let printer = record.printDetails?.printer {
            values.append(printer)
        }
        if let history = record.printHistory {
            values.append(contentsOf: history.map(\.printer))
        }
        return normalizedValues(values)
    }

    private func normalizedValues(_ values: [String]) -> Set<String> {
        Set(values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty })
    }

    private func sourceVersionStatus(for record: PrintFileRecord) -> SourceVersionStatus {
        guard let rawStatus = record.metadata["source.versionStatus"] else { return .unknown }
        return SourceVersionStatus(rawValue: rawStatus) ?? .unknown
    }

    private func duplicateContentHashCounts(in records: [PrintFileRecord]) -> [String: Int] {
        let hashes = records.compactMap(\.contentHash)
        return Dictionary(hashes.map { ($0, 1) }, uniquingKeysWith: +)
    }

    private func duplicateCount(for record: PrintFileRecord, duplicateContentHashCounts: [String: Int]) -> Int {
        guard let hash = record.contentHash else { return 0 }
        return duplicateContentHashCounts[hash] ?? 0
    }

    private func sort(_ records: [PrintFileRecord], option: SortOption, ascending: Bool) -> [PrintFileRecord] {
        records.sorted { left, right in
            let comparison: ComparisonResult = switch option {
            case .name:
                (left.projectName ?? left.fileName).localizedStandardCompare(right.projectName ?? right.fileName)
            case .modifiedDate:
                compare(left.modifiedAt, right.modifiedAt)
            case .indexedDate:
                compare(left.indexedAt, right.indexedAt)
            case .fileSize:
                compare(left.fileSize, right.fileSize)
            case .previewStatus:
                left.previewStatus.rawValue.localizedStandardCompare(right.previewStatus.rawValue)
            }

            if comparison == .orderedSame {
                return left.fileName.localizedStandardCompare(right.fileName) == .orderedAscending
            }
            return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
    }

    private func compare(_ left: Date?, _ right: Date?) -> ComparisonResult {
        switch (left, right) {
        case let (left?, right?):
            return left.compare(right)
        case (nil, nil):
            return .orderedSame
        case (nil, _?):
            return .orderedDescending
        case (_?, nil):
            return .orderedAscending
        }
    }

    private func compare(_ left: Int64, _ right: Int64) -> ComparisonResult {
        if left == right { return .orderedSame }
        return left < right ? .orderedAscending : .orderedDescending
    }
}
