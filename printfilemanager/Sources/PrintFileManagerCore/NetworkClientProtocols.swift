import Foundation

/// The AI enrichment operations the app depends on.
///
/// Declared as a protocol so the view model can be exercised in tests without reaching the
/// network. `AIEnrichmentClient` is the production implementation.
public protocol AIEnriching: Sendable {
    func enrich(
        record: PrintFileRecord,
        settings: AIEnrichmentSettings,
        thumbnailData: Data?
    ) async throws -> AIEnrichmentResult

    func organizationSuggestion(
        for record: PrintFileRecord,
        settings: AIEnrichmentSettings,
        folderContext: OrganizationFolderContext
    ) async throws -> OrganizationSuggestion
}

/// The web source lookup the app depends on. See `AIEnriching` for why this exists.
public protocol SourceLooking: Sendable {
    func lookup(record: PrintFileRecord, settings: AIEnrichmentSettings?) async throws -> SourceLookupResult
}
