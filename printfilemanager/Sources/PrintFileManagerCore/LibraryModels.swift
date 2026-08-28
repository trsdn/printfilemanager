import Foundation

public struct LibraryRoot: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var url: URL
    public var displayName: String
    public var isWatched: Bool
    public var isAvailable: Bool
    public var lastScannedAt: Date?

    public init(
        id: UUID = UUID(),
        url: URL,
        displayName: String? = nil,
        isWatched: Bool = true,
        isAvailable: Bool = true,
        lastScannedAt: Date? = nil
    ) {
        self.id = id
        self.url = url.standardizedFileURL
        self.displayName = displayName ?? url.lastPathComponent
        self.isWatched = isWatched
        self.isAvailable = isAvailable
        self.lastScannedAt = lastScannedAt
    }
}

public enum IndexingStatus: String, Codable, Equatable, Sendable {
    case pending
    case indexed
    case failed
    case missing
}

public enum PreviewStatus: String, Codable, Equatable, Sendable {
    case available
    case missing
    case failed
}

public enum GeneratedTagState: String, Codable, Equatable, Sendable {
    case suggested
    case accepted
    case rejected
}

public struct GeneratedTag: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var value: String
    public var confidence: Double
    public var source: String
    public var state: GeneratedTagState

    public init(
        id: UUID = UUID(),
        value: String,
        confidence: Double,
        source: String,
        state: GeneratedTagState = .suggested
    ) {
        self.id = id
        self.value = value
        self.confidence = confidence
        self.source = source
        self.state = state
    }
}

public enum PrintabilityStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case readyToPrint
    case needsSlicing
    case needsReview
    case multiMaterial
    case printerSpecific
    case archived

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .readyToPrint: "Ready to Print"
        case .needsSlicing: "Needs Slicing"
        case .needsReview: "Needs Review"
        case .multiMaterial: "Multi Material"
        case .printerSpecific: "Printer Specific"
        case .archived: "Archived"
        }
    }
}

public struct PrintSourceInfo: Codable, Equatable, Sendable {
    public var platform: String?
    public var author: String?
    public var license: String?
    public var url: String?
    public var downloadedAt: Date?

    public init(
        platform: String? = nil,
        author: String? = nil,
        license: String? = nil,
        url: String? = nil,
        downloadedAt: Date? = nil
    ) {
        self.platform = platform
        self.author = author
        self.license = license
        self.url = url
        self.downloadedAt = downloadedAt
    }
}

public struct PrintDetails: Codable, Equatable, Sendable {
    public var plateCount: Int?
    public var objectCount: Int?
    public var buildItemCount: Int?
    public var materialCount: Int?
    public var colorCount: Int?
    public var materials: [String]
    public var colors: [String]
    public var slicer: String?
    public var printer: String?
    public var nozzleDiameter: String?
    public var layerHeight: String?
    public var estimatedPrintTime: String?
    public var estimatedFilament: String?

    public init(
        plateCount: Int? = nil,
        objectCount: Int? = nil,
        buildItemCount: Int? = nil,
        materialCount: Int? = nil,
        colorCount: Int? = nil,
        materials: [String] = [],
        colors: [String] = [],
        slicer: String? = nil,
        printer: String? = nil,
        nozzleDiameter: String? = nil,
        layerHeight: String? = nil,
        estimatedPrintTime: String? = nil,
        estimatedFilament: String? = nil
    ) {
        self.plateCount = plateCount
        self.objectCount = objectCount
        self.buildItemCount = buildItemCount
        self.materialCount = materialCount
        self.colorCount = colorCount
        self.materials = materials
        self.colors = colors
        self.slicer = slicer
        self.printer = printer
        self.nozzleDiameter = nozzleDiameter
        self.layerHeight = layerHeight
        self.estimatedPrintTime = estimatedPrintTime
        self.estimatedFilament = estimatedFilament
    }
}

public struct PrintHistoryEntry: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var printedAt: Date
    public var printer: String
    public var material: String
    public var result: String
    public var notes: String

    public init(
        id: UUID = UUID(),
        printedAt: Date = Date(),
        printer: String = "",
        material: String = "",
        result: String = "",
        notes: String = ""
    ) {
        self.id = id
        self.printedAt = printedAt
        self.printer = printer
        self.material = material
        self.result = result
        self.notes = notes
    }
}

public struct PrintFileRecord: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var rootID: UUID
    public var url: URL
    public var fileName: String
    public var relativePath: String
    public var fileSize: Int64
    public var modifiedAt: Date?
    public var contentHash: String?
    public var indexedAt: Date?
    public var indexingStatus: IndexingStatus
    public var previewStatus: PreviewStatus

    /// Key into `ThumbnailStore` rather than the image bytes themselves; see that type for why.
    public var thumbnailKey: String?

    public var projectName: String?
    public var sourceHints: [String]
    public var metadata: [String: String]
    public var userTags: [String]
    public var generatedTags: [GeneratedTag]
    public var notes: String
    public var errorMessage: String?
    public var projectKey: String?
    public var variantName: String?
    public var category: String?
    public var printability: PrintabilityStatus?
    public var sourceInfo: PrintSourceInfo?
    public var printDetails: PrintDetails?
    public var printHistory: [PrintHistoryEntry]?
    public var reviewedAt: Date?
    public var reviewedIssueSignature: String?

    public init(
        id: UUID = UUID(),
        rootID: UUID,
        url: URL,
        fileName: String,
        relativePath: String,
        fileSize: Int64,
        modifiedAt: Date?,
        contentHash: String? = nil,
        indexedAt: Date? = nil,
        indexingStatus: IndexingStatus = .pending,
        previewStatus: PreviewStatus = .missing,
        thumbnailKey: String? = nil,
        projectName: String? = nil,
        sourceHints: [String] = [],
        metadata: [String: String] = [:],
        userTags: [String] = [],
        generatedTags: [GeneratedTag] = [],
        notes: String = "",
        errorMessage: String? = nil,
        projectKey: String? = nil,
        variantName: String? = nil,
        category: String? = nil,
        printability: PrintabilityStatus? = nil,
        sourceInfo: PrintSourceInfo? = nil,
        printDetails: PrintDetails? = nil,
        printHistory: [PrintHistoryEntry]? = nil,
        reviewedAt: Date? = nil,
        reviewedIssueSignature: String? = nil
    ) {
        self.id = id
        self.rootID = rootID
        self.url = url.standardizedFileURL
        self.fileName = fileName
        self.relativePath = relativePath
        self.fileSize = fileSize
        self.modifiedAt = modifiedAt
        self.contentHash = contentHash
        self.indexedAt = indexedAt
        self.indexingStatus = indexingStatus
        self.previewStatus = previewStatus
        self.thumbnailKey = thumbnailKey
        self.projectName = projectName
        self.sourceHints = sourceHints
        self.metadata = metadata
        self.userTags = userTags
        self.generatedTags = generatedTags
        self.notes = notes
        self.errorMessage = errorMessage
        self.projectKey = projectKey
        self.variantName = variantName
        self.category = category
        self.printability = printability
        self.sourceInfo = sourceInfo
        self.printDetails = printDetails
        self.printHistory = printHistory
        self.reviewedAt = reviewedAt
        self.reviewedIssueSignature = reviewedIssueSignature
    }
}

public enum ReviewReason: String, Codable, CaseIterable, Identifiable, Sendable {
    case fileUnavailable
    case missingPreview
    case printabilityNeedsReview
    case pendingTagSuggestions
    case possibleSourceUpdate
    case missingSource
    case missingPrintProfile
    case duplicateCandidate

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .fileUnavailable: "File missing or unreadable"
        case .missingPreview: "Preview missing"
        case .printabilityNeedsReview: "Printability needs review"
        case .pendingTagSuggestions: "Tag suggestions pending"
        case .possibleSourceUpdate: "Source update possible"
        case .missingSource: "Source missing"
        case .missingPrintProfile: "Printer or material missing"
        case .duplicateCandidate: "Duplicate candidate"
        }
    }

    public var systemImage: String {
        switch self {
        case .fileUnavailable: "exclamationmark.triangle.fill"
        case .missingPreview: "photo.badge.exclamationmark"
        case .printabilityNeedsReview: "checklist.unchecked"
        case .pendingTagSuggestions: "tag"
        case .possibleSourceUpdate: "arrow.triangle.2.circlepath"
        case .missingSource: "link.badge.plus"
        case .missingPrintProfile: "printer"
        case .duplicateCandidate: "doc.on.doc"
        }
    }
}

public struct LibrarySnapshot: Codable, Equatable, Sendable {
    /// Schema revision of the persisted library file.
    ///
    /// Bump this whenever the on-disk shape changes in a way that older or newer builds cannot
    /// read, and extend `migrate(from:)` accordingly. Files written before versioning existed
    /// decode as version 1 because the property is optional in `init(from:)`.
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var roots: [LibraryRoot]
    public var records: [PrintFileRecord]
    public var managedFolderURL: URL?
    public var updatedAt: Date?

    public init(
        roots: [LibraryRoot] = [],
        records: [PrintFileRecord] = [],
        managedFolderURL: URL? = nil,
        updatedAt: Date? = nil,
        schemaVersion: Int = LibrarySnapshot.currentSchemaVersion
    ) {
        self.roots = roots
        self.records = records
        self.managedFolderURL = managedFolderURL
        self.updatedAt = updatedAt
        self.schemaVersion = schemaVersion
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        roots = try container.decodeIfPresent([LibraryRoot].self, forKey: .roots) ?? []
        records = try container.decodeIfPresent([PrintFileRecord].self, forKey: .records) ?? []
        managedFolderURL = try container.decodeIfPresent(URL.self, forKey: .managedFolderURL)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
    }
}

public enum LibrarySchemaError: Error, Equatable, LocalizedError {
    case unsupportedSchemaVersion(found: Int, supported: Int)
    case unreadableIndex

    public var errorDescription: String? {
        switch self {
        case let .unsupportedSchemaVersion(found, supported):
            return "The library index was written by a newer version of the app (format \(found), this build supports \(supported))."
        case .unreadableIndex:
            return "The library index is not in a recognisable format."
        }
    }
}

public enum SmartCollection: String, CaseIterable, Identifiable, Codable, Sendable {
    case all
    case needsReview
    case recentlyAdded
    case latestEdited
    case untagged
    case missingPreview
    case indexingErrors
    case duplicateCandidates

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: "All Files"
        case .needsReview: "Needs Review"
        case .recentlyAdded: "Recently Added"
        case .latestEdited: "Latest Edited"
        case .untagged: "Untagged"
        case .missingPreview: "Missing Preview"
        case .indexingErrors: "Unreadable Files"
        case .duplicateCandidates: "Duplicate Candidates"
        }
    }

    public var systemImage: String {
        switch self {
        case .all: "square.grid.2x2"
        case .needsReview: "checklist.unchecked"
        case .recentlyAdded: "clock"
        case .latestEdited: "pencil.and.list.clipboard"
        case .untagged: "tag"
        case .missingPreview: "photo.badge.exclamationmark"
        case .indexingErrors: "exclamationmark.triangle"
        case .duplicateCandidates: "doc.on.doc"
        }
    }
}

public enum OrganizationActionKind: String, Codable, Equatable, Sendable {
    case copy
    case move
}

public struct OrganizationAction: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var recordID: UUID
    public var sourceURL: URL
    public var destinationURL: URL
    public var kind: OrganizationActionKind
    public var reason: String

    public init(
        id: UUID = UUID(),
        recordID: UUID,
        sourceURL: URL,
        destinationURL: URL,
        kind: OrganizationActionKind = .copy,
        reason: String
    ) {
        self.id = id
        self.recordID = recordID
        self.sourceURL = sourceURL.standardizedFileURL
        self.destinationURL = destinationURL.standardizedFileURL
        self.kind = kind
        self.reason = reason
    }
}

public struct OrganizationSuggestion: Equatable, Sendable {
    public var recordID: UUID
    public var relativePath: String
    public var rationale: String?

    public init(recordID: UUID, relativePath: String, rationale: String? = nil) {
        self.recordID = recordID
        self.relativePath = relativePath
        self.rationale = rationale
    }
}

public struct OrganizationFolderContext: Equatable, Sendable {
    public var existingDirectories: [String]

    public init(existingDirectories: [String] = []) {
        var seen = Set<String>()
        self.existingDirectories = existingDirectories
            .map(Self.normalizedDirectory)
            .filter { !$0.isEmpty }
            .filter { seen.insert($0.lowercased()).inserted }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    public mutating func insertDirectory(_ relativePath: String) {
        let directory = Self.normalizedDirectory(relativePath)
        guard !directory.isEmpty else { return }
        guard !existingDirectories.contains(where: { $0.caseInsensitiveCompare(directory) == .orderedSame }) else { return }
        existingDirectories.append(directory)
        existingDirectories.sort { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private static func normalizedDirectory(_ value: String) -> String {
        value
            .split(separator: "/")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "." && $0 != ".." }
            .joined(separator: "/")
    }
}

public struct OrganizationPlan: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var targetRootURL: URL
    public var actions: [OrganizationAction]
    public var skippedCount: Int

    public init(
        id: UUID = UUID(),
        targetRootURL: URL,
        actions: [OrganizationAction],
        skippedCount: Int = 0
    ) {
        self.id = id
        self.targetRootURL = targetRootURL.standardizedFileURL
        self.actions = actions
        self.skippedCount = skippedCount
    }
}

public enum OrganizationActionResult: Equatable, Sendable {
    case succeeded
    case skipped
    case failed(String)
}

public struct OrganizationActionOutcome: Identifiable, Equatable, Sendable {
    public var id: UUID { action.id }
    public let action: OrganizationAction
    public let result: OrganizationActionResult

    public init(action: OrganizationAction, result: OrganizationActionResult) {
        self.action = action
        self.result = result
    }
}

/// The outcome of executing an organization plan, retained so the batch can be reported and undone.
public struct OrganizationExecutionReport: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let targetRootURL: URL
    public let outcomes: [OrganizationActionOutcome]
    public let finishedAt: Date

    public init(
        id: UUID = UUID(),
        targetRootURL: URL,
        outcomes: [OrganizationActionOutcome],
        finishedAt: Date = Date()
    ) {
        self.id = id
        self.targetRootURL = targetRootURL.standardizedFileURL
        self.outcomes = outcomes
        self.finishedAt = finishedAt
    }

    public var successfulOutcomes: [OrganizationActionOutcome] {
        outcomes.filter { $0.result == .succeeded }
    }

    public var succeededCount: Int { successfulOutcomes.count }
    public var skippedCount: Int { outcomes.filter { $0.result == .skipped }.count }

    public var failures: [OrganizationActionOutcome] {
        outcomes.filter {
            if case .failed = $0.result { return true }
            return false
        }
    }

    public var failedCount: Int { failures.count }
    public var isUndoable: Bool { succeededCount > 0 }

    /// The verb of the batch, used for user-facing wording. Mixed batches are described as moves
    /// because that is the destructive half.
    public var kind: OrganizationActionKind {
        outcomes.contains { $0.action.kind == .move } ? .move : .copy
    }

    public var summary: String {
        var parts = ["\(succeededCount) \(kind == .move ? "moved" : "copied")"]
        if skippedCount > 0 { parts.append("\(skippedCount) skipped") }
        if failedCount > 0 { parts.append("\(failedCount) failed") }
        return parts.joined(separator: " · ")
    }
}

public enum SortOption: String, CaseIterable, Identifiable, Codable, Sendable {
    case name
    case modifiedDate
    case indexedDate
    case fileSize
    case previewStatus

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .name: "Name"
        case .modifiedDate: "Date Edited"
        case .indexedDate: "Date Added"
        case .fileSize: "Size"
        case .previewStatus: "Preview"
        }
    }

    public var systemImage: String {
        switch self {
        case .name: "textformat"
        case .modifiedDate: "calendar.badge.clock"
        case .indexedDate: "tray.and.arrow.down"
        case .fileSize: "externaldrive"
        case .previewStatus: "photo"
        }
    }
}

public extension SmartCollection {
    var defaultSortOption: SortOption {
        switch self {
        case .recentlyAdded:
            .indexedDate
        case .latestEdited:
            .modifiedDate
        case .all, .needsReview, .untagged, .missingPreview, .indexingErrors, .duplicateCandidates:
            .name
        }
    }

    var defaultSortAscending: Bool {
        switch self {
        case .recentlyAdded, .latestEdited:
            false
        case .all, .needsReview, .untagged, .missingPreview, .indexingErrors, .duplicateCandidates:
            true
        }
    }
}

public struct LibraryQuery: Equatable, Sendable {
    public var text: String
    public var smartCollection: SmartCollection?
    public var rootID: UUID?
    public var selectedTags: Set<String>
    public var selectedPrintabilities: Set<PrintabilityStatus>
    public var selectedMaterials: Set<String>
    public var selectedPrinters: Set<String>
    public var selectedSourcePlatforms: Set<String>
    public var selectedSourceVersionStatuses: Set<SourceVersionStatus>
    public var sortOption: SortOption
    public var sortAscending: Bool

    public init(
        text: String = "",
        smartCollection: SmartCollection? = .all,
        rootID: UUID? = nil,
        selectedTags: Set<String> = [],
        selectedPrintabilities: Set<PrintabilityStatus> = [],
        selectedMaterials: Set<String> = [],
        selectedPrinters: Set<String> = [],
        selectedSourcePlatforms: Set<String> = [],
        selectedSourceVersionStatuses: Set<SourceVersionStatus> = [],
        sortOption: SortOption = .name,
        sortAscending: Bool = true
    ) {
        self.text = text
        self.smartCollection = smartCollection
        self.rootID = rootID
        self.selectedTags = selectedTags
        self.selectedPrintabilities = selectedPrintabilities
        self.selectedMaterials = selectedMaterials
        self.selectedPrinters = selectedPrinters
        self.selectedSourcePlatforms = selectedSourcePlatforms
        self.selectedSourceVersionStatuses = selectedSourceVersionStatuses
        self.sortOption = sortOption
        self.sortAscending = sortAscending
    }
}
