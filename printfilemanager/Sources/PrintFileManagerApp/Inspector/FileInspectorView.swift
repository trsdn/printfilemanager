import AppKit
import PrintFileManagerCore
import SwiftUI

struct FileInspectorView: View {
    @EnvironmentObject private var viewModel: LibraryViewModel
    @EnvironmentObject private var aiSettings: AISettingsStore
    let record: PrintFileRecord?
    @State private var newTag = ""
    @State private var notes = ""
    @State private var category = ""
    @State private var variantName = ""
    @State private var printabilityID = ""
    @State private var sourcePlatform = ""
    @State private var sourceAuthor = ""
    @State private var sourceLicense = ""
    @State private var sourceURL = ""
    @State private var historyPrinter = ""
    @State private var historyMaterial = ""
    @State private var historyResult = "Success"
    @State private var historyNotes = ""
    @State private var isEditingProject = false
    @State private var isEditingTags = false
    @State private var isEditingSource = false
    @State private var isAddingPrintLog = false
    @State private var showsRawMetadata = false

    var body: some View {
        Group {
            if let record {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        PlateAndModelPreview(record: record)
                        inspectorHeader(record)
                        reviewSection(record)
                        projectSection(record)
                        tagsSection(record)

                        AIEnrichmentSection(record: record)

                        sourceSection(record)

                        if let details = record.printDetails {
                            DetailSection(title: "Print Details") {
                                PrintDetailsView(details: details)
                            }
                        }

                        printHistorySection(record)

                        DetailSection(title: "Notes") {
                            TextEditor(text: $notes)
                                .frame(height: 96)
                                .onChange(of: notes) { _, value in
                                    viewModel.updateNotes(value, for: record)
                                }
                        }

                        metadataSection(record)
                    }
                    .padding(16)
                }
                .onAppear {
                    syncFields(from: record)
                }
                .onChange(of: record.id) { _, _ in
                    syncFields(from: record)
                }
            } else {
                ContentUnavailableView("No Selection", systemImage: "sidebar.right", description: Text("Select a print file."))
            }
        }
    }

    @ViewBuilder
    private func inspectorHeader(_ record: PrintFileRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(record.projectName ?? record.fileName)
                .font(.title3.weight(.semibold))
                .lineLimit(2)
            Text(record.url.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private func reviewSection(_ record: PrintFileRecord) -> some View {
        let reasons = viewModel.reviewReasons(for: record)
        let isDismissed = viewModel.isReviewDismissed(for: record)

        if !reasons.isEmpty || record.reviewedAt != nil {
            DetailSection(title: "Review", accessory: {
                if !reasons.isEmpty {
                    Button {
                        if isDismissed {
                            viewModel.reopenReview(record)
                        } else {
                            viewModel.markReviewed(record)
                        }
                    } label: {
                        Label(isDismissed ? "Reopen" : "Mark Reviewed", systemImage: isDismissed ? "arrow.uturn.backward" : "checkmark.circle")
                    }
                    .controlSize(.small)
                }
            }) {
                VStack(alignment: .leading, spacing: 8) {
                    if reasons.isEmpty {
                        Label("No review items", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        FlowLayout(spacing: 6) {
                            ForEach(reasons) { reason in
                                ReviewReasonChip(reason: reason, isDismissed: isDismissed)
                            }
                        }
                    }

                    if let reviewedAt = record.reviewedAt {
                        Text("Reviewed \(reviewedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func projectSection(_ record: PrintFileRecord) -> some View {
        DetailSection(title: "Project", accessory: {
            Button {
                if isEditingProject {
                    saveDomainFields(record)
                }
                isEditingProject.toggle()
            } label: {
                Label(isEditingProject ? "Done" : "Edit", systemImage: isEditingProject ? "checkmark" : "pencil")
            }
            .controlSize(.small)
        }) {
            if isEditingProject {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Category", text: $category)
                    TextField("Variant", text: $variantName)
                    Picker("Printability", selection: $printabilityID) {
                        Text("Unknown").tag("")
                        ForEach(PrintabilityStatus.allCases) { status in
                            Text(status.title).tag(status.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                }
                // Committed as you type, like Notes. Without this, switching to another file
                // discards whatever was typed since the last "Done".
                .onChange(of: category) { _, _ in saveDomainFields(record) }
                .onChange(of: variantName) { _, _ in saveDomainFields(record) }
                .onChange(of: printabilityID) { _, _ in saveDomainFields(record) }
            } else {
                MetadataRow(label: "Key", value: displayValue(record.projectKey))
                MetadataRow(label: "Category", value: displayValue(record.category))
                MetadataRow(label: "Variant", value: displayValue(record.variantName))
                MetadataRow(label: "Printability", value: record.printability?.title ?? "Not set")
            }
        }
    }

    @ViewBuilder
    private func tagsSection(_ record: PrintFileRecord) -> some View {
        DetailSection(title: "Tags", accessory: {
            Button {
                isEditingTags.toggle()
            } label: {
                Label(isEditingTags ? "Done" : "Edit", systemImage: isEditingTags ? "checkmark" : "pencil")
            }
            .controlSize(.small)
        }) {
            VStack(alignment: .leading, spacing: 10) {
                if record.userTags.isEmpty {
                    Text("No tags")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(record.userTags, id: \.self) { tag in
                            if isEditingTags {
                                Button {
                                    viewModel.removeUserTag(tag, from: record)
                                } label: {
                                    Label(tag, systemImage: "xmark")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            } else {
                                TagChip(tag)
                            }
                        }
                    }
                }

                if isEditingTags {
                    HStack(spacing: 8) {
                        TextField("New tag", text: $newTag)
                        Button {
                            viewModel.addUserTag(newTag, to: record)
                            newTag = ""
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Add tag")
                        .disabled(newTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                let suggestions = record.generatedTags.filter { $0.state == .suggested }
                if !suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Suggestions")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        FlowLayout(spacing: 6) {
                            ForEach(suggestions) { tag in
                                SuggestedTagChip(tag: tag, record: record)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sourceSection(_ record: PrintFileRecord) -> some View {
        DetailSection(title: "Source and License", accessory: {
            HStack(spacing: 8) {
                Button {
                    viewModel.lookupSource(
                        record: record,
                        settings: aiSettings.enrichmentSettings(),
                        isEnabled: aiSettings.sourceLookupEnabled
                    )
                } label: {
                    Label("Find", systemImage: "magnifyingglass")
                }
                .disabled(viewModel.isLookingUpSource || !aiSettings.sourceLookupEnabled)
                .help(aiSettings.sourceLookupEnabled
                      ? "Search the web for this model's original page. The project or file name is sent to a search engine."
                      : "Enable web source lookup in Settings to use this.")

                if viewModel.isLookingUpSource {
                    ProgressView()
                        .controlSize(.small)
                }

                Button {
                    if isEditingSource {
                        saveSourceInfo(record)
                    }
                    isEditingSource.toggle()
                } label: {
                    Label(isEditingSource ? "Done" : "Edit", systemImage: isEditingSource ? "checkmark" : "pencil")
                }
            }
            .controlSize(.small)
        }) {
            if isEditingSource {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Platform", text: $sourcePlatform)
                    TextField("Author", text: $sourceAuthor)
                    TextField("License", text: $sourceLicense)
                    TextField("Source URL", text: $sourceURL)
                }
                // See projectSection: commit as you type so changing the selection cannot
                // silently throw the edit away.
                .onChange(of: sourcePlatform) { _, _ in saveSourceInfo(record) }
                .onChange(of: sourceAuthor) { _, _ in saveSourceInfo(record) }
                .onChange(of: sourceLicense) { _, _ in saveSourceInfo(record) }
                .onChange(of: sourceURL) { _, _ in saveSourceInfo(record) }
            } else {
                MetadataRow(label: "Platform", value: displayValue(record.sourceInfo?.platform))
                MetadataRow(label: "Author", value: displayValue(record.sourceInfo?.author))
                MetadataRow(label: "License", value: displayValue(record.sourceInfo?.license))
                SourceURLRow(label: "URL", value: displayValue(record.sourceInfo?.url))

                if let title = metadataValue(record, key: "source.title") {
                    MetadataRow(label: "Title", value: title)
                }
                if let description = metadataValue(record, key: "source.description") {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if let versionText = sourceVersionText(record) {
                    MetadataRow(label: "Version", value: versionText)
                }
                if let updatedAt = sourceDateText(record, key: "source.updatedAt") {
                    MetadataRow(label: "Updated", value: updatedAt)
                }
                if let checkedAt = sourceDateText(record, key: "source.checkedAt") {
                    MetadataRow(label: "Checked", value: checkedAt)
                }
            }
        }
    }

    @ViewBuilder
    private func printHistorySection(_ record: PrintFileRecord) -> some View {
        DetailSection(title: "Print History", accessory: {
            Button {
                isAddingPrintLog.toggle()
            } label: {
                Label(isAddingPrintLog ? "Cancel" : "Add", systemImage: isAddingPrintLog ? "xmark" : "plus")
            }
            .controlSize(.small)
        }) {
            VStack(alignment: .leading, spacing: 10) {
                if isAddingPrintLog {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            TextField("Printer", text: $historyPrinter)
                            TextField("Material", text: $historyMaterial)
                        }
                        HStack(spacing: 8) {
                            Picker("Result", selection: $historyResult) {
                                Text("Success").tag("Success")
                                Text("Partial").tag("Partial")
                                Text("Failed").tag("Failed")
                                Text("Needs retry").tag("Needs retry")
                            }
                            .pickerStyle(.menu)
                            TextField("Notes", text: $historyNotes)
                        }
                        Button {
                            viewModel.addPrintHistoryEntry(
                                printer: historyPrinter,
                                material: historyMaterial,
                                result: historyResult,
                                notes: historyNotes,
                                to: record
                            )
                            historyPrinter = ""
                            historyMaterial = ""
                            historyNotes = ""
                            isAddingPrintLog = false
                        } label: {
                            Label("Save Print Log", systemImage: "checkmark")
                        }
                        .controlSize(.small)
                    }
                }

                if let history = record.printHistory, !history.isEmpty {
                    ForEach(history) { entry in
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.printedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption.weight(.semibold))
                                Text([entry.printer, entry.material, entry.result].filter { !$0.isEmpty }.joined(separator: " / "))
                                    .font(.caption)
                                if !entry.notes.isEmpty {
                                    Text(entry.notes)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button(role: .destructive) {
                                viewModel.removePrintHistoryEntry(entry, from: record)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Delete print log entry")
                        }
                    }
                } else if !isAddingPrintLog {
                    Text("No print logs")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func metadataSection(_ record: PrintFileRecord) -> some View {
        DetailSection(title: "File") {
            MetadataRow(label: "Status", value: record.indexingStatus.rawValue)
            MetadataRow(label: "Preview", value: record.previewStatus.rawValue)
            MetadataRow(label: "Size", value: ByteCountFormatter.string(fromByteCount: record.fileSize, countStyle: .file))
            if let modifiedAt = record.modifiedAt {
                MetadataRow(label: "Modified", value: modifiedAt.formatted(date: .abbreviated, time: .shortened))
            }

            DisclosureGroup("Raw Package Metadata", isExpanded: $showsRawMetadata) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(record.metadata.keys.sorted(), id: \.self) { key in
                        MetadataRow(label: key, value: record.metadata[key] ?? "")
                    }
                }
                .padding(.top, 6)
            }
            .font(.caption)
        }
    }

    private func syncFields(from record: PrintFileRecord) {
        notes = record.notes
        category = record.category ?? ""
        variantName = record.variantName ?? ""
        printabilityID = record.printability?.rawValue ?? ""
        sourcePlatform = record.sourceInfo?.platform ?? ""
        sourceAuthor = record.sourceInfo?.author ?? ""
        sourceLicense = record.sourceInfo?.license ?? ""
        sourceURL = record.sourceInfo?.url ?? ""
        newTag = ""
        isEditingProject = false
        isEditingTags = false
        isEditingSource = false
        isAddingPrintLog = false
        showsRawMetadata = false
    }

    private func displayValue(_ value: String?) -> String {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Not set"
        }
        return value
    }

    private func metadataValue(_ record: PrintFileRecord, key: String) -> String? {
        guard let value = record.metadata[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private func sourceVersionText(_ record: PrintFileRecord) -> String? {
        guard let rawStatus = metadataValue(record, key: "source.versionStatus") else { return nil }
        let status = SourceVersionStatus(rawValue: rawStatus)?.title ?? rawStatus
        if let latestVersion = metadataValue(record, key: "source.latestVersion") {
            return "\(status) / latest: \(latestVersion)"
        }
        return status
    }

    private func sourceDateText(_ record: PrintFileRecord, key: String) -> String? {
        guard let value = metadataValue(record, key: key) else { return nil }
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: value) else { return value }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func saveDomainFields(_ record: PrintFileRecord) {
        viewModel.updateDomainFields(
            category: category,
            variantName: variantName,
            printability: PrintabilityStatus(rawValue: printabilityID),
            for: record
        )
    }

    private func saveSourceInfo(_ record: PrintFileRecord) {
        viewModel.updateSourceInfo(
            platform: sourcePlatform,
            author: sourceAuthor,
            license: sourceLicense,
            url: sourceURL,
            for: record
        )
    }
}

struct PrintDetailsView: View {
    let details: PrintDetails

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let plateCount = details.plateCount { MetadataRow(label: "Plates", value: String(plateCount)) }
            if let objectCount = details.objectCount { MetadataRow(label: "Objects", value: String(objectCount)) }
            if let buildItemCount = details.buildItemCount { MetadataRow(label: "Build Items", value: String(buildItemCount)) }
            if let materialCount = details.materialCount { MetadataRow(label: "Materials", value: String(materialCount)) }
            if let colorCount = details.colorCount { MetadataRow(label: "Colors", value: String(colorCount)) }
            if !details.materials.isEmpty { MetadataRow(label: "Material", value: details.materials.joined(separator: ", ")) }
            if !details.colors.isEmpty { MetadataRow(label: "Color", value: details.colors.joined(separator: ", ")) }
            if let slicer = details.slicer { MetadataRow(label: "Slicer", value: slicer) }
            if let printer = details.printer { MetadataRow(label: "Printer", value: printer) }
            if let nozzleDiameter = details.nozzleDiameter { MetadataRow(label: "Nozzle", value: nozzleDiameter) }
            if let layerHeight = details.layerHeight { MetadataRow(label: "Layer", value: layerHeight) }
            if let estimatedPrintTime = details.estimatedPrintTime { MetadataRow(label: "Time", value: estimatedPrintTime) }
            if let estimatedFilament = details.estimatedFilament { MetadataRow(label: "Filament", value: estimatedFilament) }
        }
    }
}

struct AIEnrichmentSection: View {
    @EnvironmentObject private var viewModel: LibraryViewModel
    @EnvironmentObject private var aiSettings: AISettingsStore
    let record: PrintFileRecord

    var body: some View {
        DetailSection(title: "AI Enrichment") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Button {
                        enrich()
                    } label: {
                        Label("Enrich", systemImage: "sparkles")
                    }
                    .disabled(!aiSettings.isConfigured || viewModel.isEnriching)

                    if viewModel.isEnriching {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if aiSettings.isConfigured {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("AI enrichment enabled in Settings", systemImage: "checkmark.circle.fill")
                        Text(aiSettings.includeThumbnail
                             ? "Sends the file name, its folder path, extracted metadata and the preview image to your configured provider."
                             : "Sends the file name, its folder path and extracted metadata to your configured provider.")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Label("Enable AI enrichment in Application Settings", systemImage: "gearshape")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let description = record.metadata["ai.description"], !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                if let materialHints = record.metadata["ai.materialHints"], !materialHints.isEmpty {
                    MetadataRow(label: "Materials", value: materialHints)
                }

                if let workflowNotes = record.metadata["ai.workflowNotes"], !workflowNotes.isEmpty {
                    MetadataRow(label: "Workflow", value: workflowNotes)
                }
            }
        }
    }

    private func enrich() {
        guard let settings = aiSettings.enrichmentSettings() else { return }
        viewModel.enrich(
            record: record,
            settings: settings,
            allowSourceLookup: aiSettings.sourceLookupEnabled
        )
    }
}
