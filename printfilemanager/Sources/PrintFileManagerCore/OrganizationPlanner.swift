import Foundation

public struct OrganizationPlanner {
    public init() {}

    public func planCopy(records: [PrintFileRecord], to targetRootURL: URL) -> OrganizationPlan {
        plan(records: records, to: targetRootURL, kind: .copy)
    }

    public func planCopy(records: [PrintFileRecord], to targetRootURL: URL, suggestions: [OrganizationSuggestion]) -> OrganizationPlan {
        plan(records: records, to: targetRootURL, kind: .copy, suggestions: suggestions)
    }

    public func planMove(records: [PrintFileRecord], to targetRootURL: URL) -> OrganizationPlan {
        plan(records: records, to: targetRootURL, kind: .move)
    }

    public func planMove(records: [PrintFileRecord], to targetRootURL: URL, suggestions: [OrganizationSuggestion]) -> OrganizationPlan {
        plan(records: records, to: targetRootURL, kind: .move, suggestions: suggestions)
    }

    private func plan(
        records: [PrintFileRecord],
        to targetRootURL: URL,
        kind: OrganizationActionKind,
        suggestions: [OrganizationSuggestion] = []
    ) -> OrganizationPlan {
        let activeRecords = records.filter { record in
            record.indexingStatus != .missing
                && FileManager.default.fileExists(atPath: record.url.path)
        }

        let suggestionsByRecordID = Dictionary(uniqueKeysWithValues: suggestions.map { ($0.recordID, $0) })
        var usedDestinations = Set<String>()
        let actions = activeRecords.compactMap { record -> OrganizationAction? in
            let destinationURL = uniqueDestinationURL(
                for: record,
                targetRootURL: targetRootURL.standardizedFileURL,
                suggestedRelativePath: suggestionsByRecordID[record.id]?.relativePath,
                sourceURL: record.url.standardizedFileURL,
                usedDestinations: &usedDestinations
            )
            guard destinationURL.standardizedFileURL.path != record.url.standardizedFileURL.path else {
                return nil
            }
            let reason = suggestionsByRecordID[record.id]?.rationale
                ?? "\(kind == .move ? "Move" : "Copy") into managed library as \(destinationURL.lastPathComponent)"

            return OrganizationAction(
                recordID: record.id,
                sourceURL: record.url,
                destinationURL: destinationURL,
                kind: kind,
                reason: reason
            )
        }

        return OrganizationPlan(
            targetRootURL: targetRootURL,
            actions: actions,
            skippedCount: records.count - actions.count
        )
    }

    public func execute(_ plan: OrganizationPlan) throws {
        for action in plan.actions {
            switch action.kind {
            case .copy:
                try copy(action)
            case .move:
                try move(action)
            }
        }
    }

    private func copy(_ action: OrganizationAction) throws {
        guard action.sourceURL.standardizedFileURL.path != action.destinationURL.standardizedFileURL.path else { return }
        let destinationFolder = action.destinationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: action.destinationURL.path) {
            return
        }

        try FileManager.default.copyItem(at: action.sourceURL, to: action.destinationURL)
    }

    private func move(_ action: OrganizationAction) throws {
        guard action.sourceURL.standardizedFileURL.path != action.destinationURL.standardizedFileURL.path else { return }
        let destinationFolder = action.destinationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: action.destinationURL.path) {
            throw OrganizationPlannerError.destinationAlreadyExists(action.destinationURL)
        }

        try FileManager.default.moveItem(at: action.sourceURL, to: action.destinationURL)
    }

    private func uniqueDestinationURL(
        for record: PrintFileRecord,
        targetRootURL: URL,
        suggestedRelativePath: String? = nil,
        sourceURL: URL,
        usedDestinations: inout Set<String>
    ) -> URL {
        let fallbackRelativePath = fallbackRelativePath(for: record)
        let relativePath = sanitizedRelativePath(suggestedRelativePath, fallback: fallbackRelativePath)
        let folderComponents = Array(relativePath.dropLast())
        let fileName = relativePath.last ?? sanitizedComponent(record.fileNameWithoutExtension) + ".3mf"
        let folderURL = folderComponents.reduce(targetRootURL) { url, component in
            url.appendingPathComponent(component, isDirectory: true)
        }

        var candidate = folderURL.appendingPathComponent(fileName)
        let fileExtension = (fileName as NSString).pathExtension
        let fileBaseName = (fileName as NSString).deletingPathExtension
        var suffix = 2
        while usedDestinations.contains(candidate.path) || destinationAlreadyExists(candidate, sourceURL: sourceURL) {
            candidate = folderURL.appendingPathComponent("\(fileBaseName) \(suffix)")
            if !fileExtension.isEmpty {
                candidate = candidate.appendingPathExtension(fileExtension)
            }
            suffix += 1
        }

        usedDestinations.insert(candidate.path)
        return candidate
    }

    private func destinationAlreadyExists(_ destinationURL: URL, sourceURL: URL) -> Bool {
        let destinationPath = destinationURL.standardizedFileURL.path
        guard destinationPath != sourceURL.standardizedFileURL.path else { return false }
        return FileManager.default.fileExists(atPath: destinationPath)
    }

    private func fallbackRelativePath(for record: PrintFileRecord) -> [String] {
        let category = categoryFolderName(for: record)
        let project = sanitizedComponent(record.projectName ?? record.fileNameWithoutExtension)
        let baseName = sanitizedComponent(record.projectName ?? record.fileNameWithoutExtension)
        return [category, project, "\(baseName).3mf"]
    }

    private func sanitizedRelativePath(_ suggestedRelativePath: String?, fallback: [String]) -> [String] {
        guard let suggestedRelativePath else { return fallback }
        let components = suggestedRelativePath
            .split(separator: "/")
            .map { sanitizedComponent(String($0)) }
            .filter { !$0.isEmpty && $0 != "." && $0 != ".." }

        guard components.count >= 2 else { return fallback }
        let limitedComponents = Array(components.prefix(5))
        let lastComponent = limitedComponents.last ?? fallback.last ?? "Untitled.3mf"
        let fileBaseName = sanitizedComponent((lastComponent as NSString).deletingPathExtension)
        let fileName = "\(fileBaseName.isEmpty ? "Untitled" : fileBaseName).3mf"
        return Array(limitedComponents.dropLast()) + [fileName]
    }

    private func categoryFolderName(for record: PrintFileRecord) -> String {
        let acceptedGeneratedTags = record.generatedTags
            .filter { $0.state == .accepted }
            .map(\.value)
        let candidate = record.category
            ?? (record.userTags + acceptedGeneratedTags)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .first
            ?? record.sourceHints.first
            ?? "Uncategorized"
        return sanitizedComponent(candidate)
    }

    private func sanitizedComponent(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = trimmed.isEmpty ? "Untitled" : trimmed
        let invalidCharacters = CharacterSet(charactersIn: "/:")
            .union(.newlines)
            .union(.controlCharacters)
        let cleaned = fallback
            .components(separatedBy: invalidCharacters)
            .joined(separator: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .joined(separator: " ")
        return cleaned.isEmpty ? "Untitled" : cleaned
    }
}

public enum OrganizationPlannerError: Error, Equatable, Sendable {
    case destinationAlreadyExists(URL)
}

private extension PrintFileRecord {
    var fileNameWithoutExtension: String {
        (fileName as NSString).deletingPathExtension
    }
}