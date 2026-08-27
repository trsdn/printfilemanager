import AppKit
import PrintFileManagerCore
import SceneKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: LibraryViewModel
    @EnvironmentObject private var aiSettings: AISettingsStore

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } content: {
            LibraryBrowserView()
                .navigationSplitViewColumnWidth(min: 520, ideal: 720)
        } detail: {
            FileInspectorView(record: viewModel.selectedRecord)
                .navigationSplitViewColumnWidth(min: 300, ideal: 360)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if let record = viewModel.selectedRecord {
                    Button {
                        viewModel.openInDefaultApp(record: record)
                    } label: {
                        Label("Open", systemImage: "arrow.up.forward.app")
                    }

                    Button {
                        viewModel.openInBambuStudio(record: record)
                    } label: {
                        Label("Bambu Studio", systemImage: "cube")
                    }

                    Button {
                        viewModel.prepareMovePlan(for: record, settings: aiSettings.enrichmentSettings())
                    } label: {
                        Label("Move to Managed", systemImage: "arrowshape.turn.up.right")
                    }
                    .disabled(viewModel.managedFolderURL == nil)

                    Button(role: .destructive) {
                        viewModel.requestDelete(record: record)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }

                Button {
                    viewModel.addFolderFromPanel()
                } label: {
                    Label("Add Folder", systemImage: "folder.badge.plus")
                }

                Button {
                    viewModel.rescanAllRoots()
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.snapshot.roots.isEmpty || viewModel.isScanning)
            }
        }
        .sheet(item: $viewModel.organizationPlan) { plan in
            OrganizationPlanSheet(plan: plan)
                .environmentObject(viewModel)
        }
        .alert("Move File to Trash?", isPresented: deleteAlertBinding, presenting: viewModel.deleteCandidate) { record in
            Button("Cancel", role: .cancel) {
                viewModel.deleteCandidate = nil
            }
            Button("Move to Trash", role: .destructive) {
                viewModel.moveDeleteCandidateToTrash()
            }
        } message: { record in
            Text("This will move \(record.fileName) to the macOS Trash and remove it from the library index.")
        }
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.deleteCandidate != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.deleteCandidate = nil
                }
            }
        )
    }
}

private struct SidebarView: View {
    @EnvironmentObject private var viewModel: LibraryViewModel
    @EnvironmentObject private var aiSettings: AISettingsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SidebarSection(title: "Library") {
                    VStack(spacing: 4) {
                        ForEach(SmartCollection.allCases) { collection in
                            SidebarCollectionButton(collection: collection)
                        }
                    }
                }

                SidebarSection(title: "Auto Sort Target") {
                    VStack(alignment: .leading, spacing: 8) {
                        if let url = viewModel.managedFolderURL {
                            Label(url.lastPathComponent, systemImage: "shippingbox")
                                .font(.body.weight(.medium))
                                .lineLimit(1)
                            Text(url.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        } else {
                            Text("No target folder")
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 8) {
                            Button {
                                viewModel.setManagedFolderFromPanel()
                            } label: {
                                Label("Set Target", systemImage: "folder.badge.gearshape")
                            }
                        }
                        .controlSize(.small)

                        if viewModel.selectedRecordCount > 0 {
                            Label("\(viewModel.selectedRecordCount) selected", systemImage: "checkmark.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 8) {

                            Button {
                                viewModel.prepareOrganizationPlan(settings: aiSettings.enrichmentSettings())
                            } label: {
                                Label("Copy Selected", systemImage: "doc.on.doc")
                            }
                            .disabled(viewModel.managedFolderURL == nil || viewModel.selectedRecordCount == 0 || viewModel.isOrganizing)
                            .help("Copy selected files into the managed library")

                            Button {
                                viewModel.prepareMoveOrganizationPlan(settings: aiSettings.enrichmentSettings())
                            } label: {
                                Label("Move Selected", systemImage: "arrowshape.turn.up.right")
                            }
                            .disabled(viewModel.managedFolderURL == nil || viewModel.selectedRecordCount == 0 || viewModel.isOrganizing)
                            .help("Move or re-sort selected files into the managed library")
                        }
                        .controlSize(.small)
                    }
                }

                SidebarSection(title: "Scanned Folders") {
                    if viewModel.snapshot.roots.isEmpty {
                        Text("No folders")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(viewModel.snapshot.roots) { root in
                                FolderRow(root: root)
                            }
                        }
                    }
                }
            }
            .padding(12)
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                if viewModel.isScanning || viewModel.isOrganizing {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(viewModel.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(12)
        }
    }
}

private struct SidebarSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content
        }
    }
}

private struct SidebarCollectionButton: View {
    @EnvironmentObject private var viewModel: LibraryViewModel
    let collection: SmartCollection

    var body: some View {
        Button {
            viewModel.select(collection: collection)
        } label: {
            HStack(spacing: 8) {
                Label(collection.title, systemImage: collection.systemImage)
                Spacer()
                Text("\(viewModel.count(for: collection))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            viewModel.selectedRootID == nil && viewModel.selectedCollection == collection ? Color.accentColor.opacity(0.18) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
    }
}

private struct FolderRow: View {
    @EnvironmentObject private var viewModel: LibraryViewModel
    let root: LibraryRoot

    var body: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.select(root: root)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: root.isAvailable ? "folder" : "folder.badge.questionmark")
                        .foregroundStyle(root.isAvailable ? Color.secondary : Color.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(root.displayName)
                            .lineLimit(1)
                        Text(root.url.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text("\(viewModel.count(for: root))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(
                viewModel.selectedRootID == root.id ? Color.accentColor.opacity(0.18) : Color.clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
            .help("Show folder contents")

            Button {
                viewModel.scan(root: root)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Rescan folder")
        }
    }
}

private struct LibraryBrowserView: View {
    @EnvironmentObject private var viewModel: LibraryViewModel

    private let columns = [GridItem(.adaptive(minimum: 176, maximum: 240), spacing: 16)]

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search files, tags, printer, material, source", text: $viewModel.searchText)
                        .textFieldStyle(.plain)
                    Spacer()

                    if viewModel.selectedRecordCount > 0 {
                        Label("\(viewModel.selectedRecordCount) selected", systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    FilterMenuView()

                    Picker("Sort", selection: $viewModel.sortOption) {
                        ForEach(SortOption.allCases) { option in
                            Label(option.title, systemImage: option.systemImage)
                                .tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 148)

                    Button {
                        viewModel.sortAscending.toggle()
                    } label: {
                        Image(systemName: viewModel.sortAscending ? "arrow.up" : "arrow.down")
                    }
                    .help(viewModel.sortAscending ? "Ascending" : "Descending")

                    Text("\(viewModel.filteredRecords.count)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                if viewModel.activeFilterCount > 0 {
                    ActiveFilterBar()
                }
            }
            .padding(12)
            .background(.regularMaterial)

            Divider()

            if viewModel.snapshot.roots.isEmpty {
                EmptyLibraryView()
            } else if viewModel.filteredRecords.isEmpty {
                ContentUnavailableView("No Results", systemImage: "magnifyingglass", description: Text("Try another search, filter, or collection."))
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(viewModel.filteredRecords) { record in
                            FileTile(record: record, isSelected: viewModel.selectedRecordIDs.contains(record.id))
                                .onTapGesture {
                                    viewModel.select(record: record, extendingSelection: NSApp.currentEvent?.modifierFlags.contains(.command) == true)
                                }
                        }
                    }
                    .padding(16)
                }
            }
        }
    }
}

private struct FilterMenuView: View {
    @EnvironmentObject private var viewModel: LibraryViewModel

    var body: some View {
        Menu {
            if viewModel.activeFilterCount > 0 {
                Button {
                    viewModel.clearFilters()
                } label: {
                    Label("Clear Filters", systemImage: "xmark.circle")
                }
                Divider()
            }

            Section("Printability") {
                ForEach(PrintabilityStatus.allCases) { status in
                    Button {
                        viewModel.togglePrintabilityFilter(status)
                    } label: {
                        Label(status.title, systemImage: viewModel.selectedPrintabilities.contains(status) ? "checkmark" : "checklist")
                    }
                }
            }

            if !viewModel.allTags.isEmpty {
                Section("Tags") {
                    ForEach(viewModel.allTags, id: \.self) { tag in
                        Button {
                            viewModel.toggleTagFilter(tag)
                        } label: {
                            Label(tag, systemImage: contains(tag, in: viewModel.selectedTags) ? "checkmark" : "tag")
                        }
                    }
                }
            }

            if !viewModel.allMaterials.isEmpty {
                Section("Materials") {
                    ForEach(viewModel.allMaterials, id: \.self) { material in
                        Button {
                            viewModel.toggleMaterialFilter(material)
                        } label: {
                            Label(material, systemImage: contains(material, in: viewModel.selectedMaterials) ? "checkmark" : "circle.hexagongrid")
                        }
                    }
                }
            }

            if !viewModel.allPrinters.isEmpty {
                Section("Printers") {
                    ForEach(viewModel.allPrinters, id: \.self) { printer in
                        Button {
                            viewModel.togglePrinterFilter(printer)
                        } label: {
                            Label(printer, systemImage: contains(printer, in: viewModel.selectedPrinters) ? "checkmark" : "printer")
                        }
                    }
                }
            }

            if !viewModel.allSourcePlatforms.isEmpty {
                Section("Sources") {
                    ForEach(viewModel.allSourcePlatforms, id: \.self) { platform in
                        Button {
                            viewModel.toggleSourcePlatformFilter(platform)
                        } label: {
                            Label(platform, systemImage: contains(platform, in: viewModel.selectedSourcePlatforms) ? "checkmark" : "link")
                        }
                    }
                }
            }

            if !viewModel.availableSourceVersionStatuses.isEmpty {
                Section("Version") {
                    ForEach(viewModel.availableSourceVersionStatuses) { status in
                        Button {
                            viewModel.toggleSourceVersionStatusFilter(status)
                        } label: {
                            Label(status.title, systemImage: viewModel.selectedSourceVersionStatuses.contains(status) ? "checkmark" : "clock.arrow.circlepath")
                        }
                    }
                }
            }
        } label: {
            Label("Filters", systemImage: viewModel.activeFilterCount == 0 ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
        .help("Filter library")
    }

    private func contains(_ value: String, in set: Set<String>) -> Bool {
        set.contains { $0.caseInsensitiveCompare(value) == .orderedSame }
    }
}

private struct ActiveFilterBar: View {
    @EnvironmentObject private var viewModel: LibraryViewModel

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(viewModel.selectedPrintabilities.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }) { status in
                ActiveFilterChip(title: status.title, systemImage: "checklist") {
                    viewModel.togglePrintabilityFilter(status)
                }
            }

            ForEach(viewModel.selectedTags.sorted { $0.localizedStandardCompare($1) == .orderedAscending }, id: \.self) { tag in
                ActiveFilterChip(title: tag, systemImage: "tag") {
                    viewModel.toggleTagFilter(tag)
                }
            }

            ForEach(viewModel.selectedMaterials.sorted { $0.localizedStandardCompare($1) == .orderedAscending }, id: \.self) { material in
                ActiveFilterChip(title: material, systemImage: "circle.hexagongrid") {
                    viewModel.toggleMaterialFilter(material)
                }
            }

            ForEach(viewModel.selectedPrinters.sorted { $0.localizedStandardCompare($1) == .orderedAscending }, id: \.self) { printer in
                ActiveFilterChip(title: printer, systemImage: "printer") {
                    viewModel.togglePrinterFilter(printer)
                }
            }

            ForEach(viewModel.selectedSourcePlatforms.sorted { $0.localizedStandardCompare($1) == .orderedAscending }, id: \.self) { platform in
                ActiveFilterChip(title: platform, systemImage: "link") {
                    viewModel.toggleSourcePlatformFilter(platform)
                }
            }

            ForEach(viewModel.selectedSourceVersionStatuses.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }) { status in
                ActiveFilterChip(title: status.title, systemImage: "clock.arrow.circlepath") {
                    viewModel.toggleSourceVersionStatusFilter(status)
                }
            }

            Button {
                viewModel.clearFilters()
            } label: {
                Label("Clear", systemImage: "xmark.circle")
            }
            .controlSize(.small)
        }
    }
}

private struct ActiveFilterChip: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
        .controlSize(.small)
        .help("Remove filter")
    }
}

private struct EmptyLibraryView: View {
    @EnvironmentObject private var viewModel: LibraryViewModel

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.plus")
                .font(.title)
                .foregroundStyle(.secondary)
            Text("Add a Folder")
                .font(.title3.weight(.semibold))
            Button {
                viewModel.addFolderFromPanel()
            } label: {
                Label("Add Folder", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FileTile: View {
    @EnvironmentObject private var viewModel: LibraryViewModel
    @EnvironmentObject private var aiSettings: AISettingsStore
    let record: PrintFileRecord
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary.opacity(0.45))
                ThumbnailView(data: record.thumbnailData)
                    .padding(8)
            }
            .frame(height: 132)

            VStack(alignment: .leading, spacing: 4) {
                Text(record.projectName ?? record.fileName)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                Text(record.relativePath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                if !activeReviewReasons.isEmpty {
                    TileStatusBadge(
                        title: activeReviewReasons.map(\.title).joined(separator: ", "),
                        systemImage: "exclamationmark.triangle.fill",
                        value: "\(activeReviewReasons.count)",
                        tint: .orange
                    )
                }
                TileStatusBadge(
                    title: record.previewStatus == .available ? "Preview available" : "No preview available",
                    systemImage: record.previewStatus == .available ? "checkmark.circle.fill" : "photo",
                    tint: record.previewStatus == .available ? .green : .secondary
                )
                if let printability = record.printability {
                    TileStatusBadge(
                        title: printability.title,
                        systemImage: "checklist.checked",
                        tint: .blue
                    )
                }
                if !record.userTags.isEmpty {
                    TileStatusBadge(
                        title: "\(record.userTags.count) user tags",
                        systemImage: "tag.fill",
                        value: "\(record.userTags.count)",
                        tint: .secondary
                    )
                }
                Spacer(minLength: 4)
                Button {
                    viewModel.prepareMovePlan(for: record, settings: aiSettings.enrichmentSettings())
                } label: {
                    Image(systemName: "arrowshape.turn.up.right")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(viewModel.managedFolderURL == nil)
                .help("Move to managed folder")

                Button {
                    viewModel.openInBambuStudio(record: record)
                } label: {
                    Image(systemName: "cube")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Open in Bambu Studio")

                Button(role: .destructive) {
                    viewModel.requestDelete(record: record)
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Move to Trash")
            }
            .frame(height: 28)
        }
        .padding(12)
        .background(isSelected ? Color.accentColor.opacity(0.16) : Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: isSelected ? 2 : 1)
        }
        .accessibilityElement(children: .combine)
        .contextMenu {
            Button {
                viewModel.openInDefaultApp(record: record)
            } label: {
                Label("Open", systemImage: "arrow.up.forward.app")
            }

            Button {
                viewModel.openInBambuStudio(record: record)
            } label: {
                Label("Open in Bambu Studio", systemImage: "cube")
            }

            Button {
                viewModel.prepareCopyPlan(for: record, settings: aiSettings.enrichmentSettings())
            } label: {
                Label("Copy to Managed Folder", systemImage: "doc.on.doc")
            }
            .disabled(viewModel.managedFolderURL == nil)

            Button {
                viewModel.prepareMovePlan(for: record, settings: aiSettings.enrichmentSettings())
            } label: {
                Label("Move to Managed Folder", systemImage: "arrowshape.turn.up.right")
            }
            .disabled(viewModel.managedFolderURL == nil)

            if !viewModel.reviewReasons(for: record).isEmpty {
                Button {
                    if viewModel.isReviewDismissed(for: record) {
                        viewModel.reopenReview(record)
                    } else {
                        viewModel.markReviewed(record)
                    }
                } label: {
                    Label(viewModel.isReviewDismissed(for: record) ? "Reopen Review" : "Mark Reviewed", systemImage: viewModel.isReviewDismissed(for: record) ? "arrow.uturn.backward" : "checkmark.circle")
                }
            }

            Divider()

            Button(role: .destructive) {
                viewModel.requestDelete(record: record)
            } label: {
                Label("Move to Trash", systemImage: "trash")
            }
        }
    }

    private var activeReviewReasons: [ReviewReason] {
        guard !viewModel.isReviewDismissed(for: record) else { return [] }
        return viewModel.reviewReasons(for: record)
    }
}

private struct OrganizationPlanSheet: View {
    @EnvironmentObject private var viewModel: LibraryViewModel
    let plan: OrganizationPlan
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: isMovePlan ? "arrowshape.turn.up.right" : "doc.on.doc")
                    .imageScale(.large)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text(planTitle)
                        .font(.title3.weight(.semibold))
                    Text(planSummary)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Target")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(plan.targetRootURL.path)
                    .font(.caption)
                    .textSelection(.enabled)
            }

            List(plan.actions.prefix(80)) { action in
                VStack(alignment: .leading, spacing: 4) {
                    Text(action.destinationURL.lastPathComponent)
                        .font(.body.weight(.medium))
                    Text(relativeDestinationPath(action.destinationURL))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !action.reason.isEmpty {
                        Text(action.reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Text(action.sourceURL.path)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .padding(.vertical, 4)
            }
            .frame(minHeight: 260)

            if plan.actions.count > 80 {
                Text("Showing the first 80 planned actions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                Spacer()
                Button {
                    viewModel.executeOrganizationPlan(plan)
                    dismiss()
                } label: {
                    Label(confirmTitle, systemImage: isMovePlan ? "arrowshape.turn.up.right" : "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)
                .disabled(plan.actions.isEmpty || viewModel.isOrganizing)
            }
        }
        .padding(20)
        .frame(minWidth: 680, minHeight: 520)
    }

    private var isMovePlan: Bool {
        plan.actions.contains { $0.kind == .move }
    }

    private var operationTitle: String {
        isMovePlan ? "Move" : "Copy"
    }

    private var planTitle: String {
        if isMovePlan, isReSortPlan {
            return "Re-sort Managed Files"
        }
        return isMovePlan ? "Move into Managed Library" : "Copy into Managed Library"
    }

    private var planSummary: String {
        let fileWord = plan.actions.count == 1 ? "file" : "files"
        let actionText = "\(plan.actions.count) \(fileWord) will be \(isMovePlan ? "moved" : "copied")."
        let safetyText = isMovePlan ? "Original files change location." : "Original files stay where they are."
        let skippedText = plan.skippedCount == 1 ? "1 file is already in place or skipped." : "\(plan.skippedCount) files are already in place or skipped."
        return "\(actionText) \(safetyText) \(skippedText)"
    }

    private var confirmTitle: String {
        isMovePlan ? "Move Files" : "Copy Files"
    }

    private var isReSortPlan: Bool {
        !plan.actions.isEmpty && plan.actions.allSatisfy { action in
            let targetPath = plan.targetRootURL.standardizedFileURL.path
            let sourcePath = action.sourceURL.standardizedFileURL.path
            return sourcePath == targetPath || sourcePath.hasPrefix(targetPath + "/")
        }
    }

    private func relativeDestinationPath(_ url: URL) -> String {
        let targetPath = plan.targetRootURL.standardizedFileURL.path
        let destinationPath = url.standardizedFileURL.path
        guard destinationPath.hasPrefix(targetPath) else { return destinationPath }
        let startIndex = destinationPath.index(destinationPath.startIndex, offsetBy: targetPath.count)
        return String(destinationPath[startIndex...]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

private struct ThumbnailView: View {
    let data: Data?

    var body: some View {
        if let data, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "cube.transparent")
                .font(.title)
                .foregroundStyle(.secondary)
        }
    }
}

private struct TileStatusBadge: View {
    let title: String
    let systemImage: String
    var value: String?
    var tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .imageScale(.small)
            if let value {
                Text(value)
                    .font(.caption2.monospacedDigit())
                    .lineLimit(1)
            }
        }
            .font(.caption)
            .foregroundStyle(tint)
            .frame(minWidth: 24, minHeight: 24)
            .padding(.horizontal, value == nil ? 0 : 6)
            .background(.quaternary.opacity(0.35), in: Capsule())
            .help(title)
            .accessibilityLabel(title)
    }
}

private struct FileInspectorView: View {
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

private struct PrintDetailsView: View {
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

private struct PlateAndModelPreview: View {
    let record: PrintFileRecord
    @State private var platePreviews: [PlatePreview] = []
    @State private var mesh: ThreeMFMesh?
    @State private var selection = "3d"
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if availableModes.count > 1 {
                Picker("Preview", selection: $selection) {
                    ForEach(availableModes, id: \.id) { mode in
                        Label(mode.title, systemImage: mode.systemImage)
                            .tag(mode.id)
                    }
                }
                .pickerStyle(.segmented)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary.opacity(0.35))

                if isLoading {
                    ProgressView()
                } else if selection == "3d", let mesh {
                    ThreeMFScenePreview(mesh: mesh)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else if let preview = selectedPlatePreview {
                    ThumbnailView(data: preview.imageData)
                        .padding(8)
                } else {
                    ThumbnailView(data: record.thumbnailData)
                        .padding(8)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 220, maxHeight: 280)
        }
        .task(id: record.id) {
            await loadPreviewAssets()
        }
    }

    private var availableModes: [PreviewMode] {
        var modes: [PreviewMode] = []
        if mesh != nil {
            modes.append(PreviewMode(id: "3d", title: "3D", systemImage: "cube"))
        }
        modes.append(contentsOf: platePreviews.map { preview in
            PreviewMode(id: "plate-\(preview.index)", title: preview.title, systemImage: "square.stack.3d.up")
        })
        return modes.isEmpty ? [PreviewMode(id: "preview", title: "Preview", systemImage: "photo")] : modes
    }

    private var selectedPlatePreview: PlatePreview? {
        guard selection.hasPrefix("plate-"), let index = Int(selection.dropFirst("plate-".count)) else {
            return nil
        }
        return platePreviews.first { $0.index == index }
    }

    private func loadPreviewAssets() async {
        isLoading = true
        let url = record.url
        let result = await Task.detached(priority: .userInitiated) {
            (
                PlatePreviewExtractor().previews(for: url),
                ThreeMFMeshExtractor().mesh(for: url)
            )
        }.value

        platePreviews = result.0
        mesh = result.1
        if result.1 != nil {
            selection = "3d"
        } else if let firstPlate = result.0.first {
            selection = "plate-\(firstPlate.index)"
        } else {
            selection = "preview"
        }
        isLoading = false
    }

    private struct PreviewMode {
        let id: String
        let title: String
        let systemImage: String
    }
}

private struct ThreeMFScenePreview: View {
    let mesh: ThreeMFMesh

    var body: some View {
        SceneView(
            scene: Self.scene(for: mesh),
            options: [.allowsCameraControl, .autoenablesDefaultLighting]
        )
    }

    private static func scene(for mesh: ThreeMFMesh) -> SCNScene {
        let scene = SCNScene()
        let node = SCNNode(geometry: geometry(for: mesh))
        node.geometry?.firstMaterial?.diffuse.contents = NSColor.controlAccentColor
        node.geometry?.firstMaterial?.roughness.contents = 0.72
        node.geometry?.firstMaterial?.metalness.contents = 0.08
        scene.rootNode.addChildNode(node)

        let camera = SCNCamera()
        camera.zNear = 0.01
        camera.zFar = 100
        camera.fieldOfView = 42
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 1.8, 6)
        cameraNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(cameraNode)

        let lightNode = SCNNode()
        lightNode.light = SCNLight()
        lightNode.light?.type = .omni
        lightNode.light?.intensity = 650
        lightNode.position = SCNVector3(2, 4, 4)
        scene.rootNode.addChildNode(lightNode)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 250
        scene.rootNode.addChildNode(ambient)

        return scene
    }

    private static func geometry(for mesh: ThreeMFMesh) -> SCNGeometry {
        let normalizedVertices = normalize(mesh.vertices)
        let source = SCNGeometrySource(vertices: normalizedVertices.map { SCNVector3($0.x, $0.y, $0.z) })
        let indices = mesh.triangles.flatMap { [$0.a, $0.b, $0.c] }
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        let geometry = SCNGeometry(sources: [source], elements: [element])
        geometry.firstMaterial = SCNMaterial()
        geometry.firstMaterial?.isDoubleSided = true
        return geometry
    }

    private static func normalize(_ vertices: [SIMD3<Float>]) -> [SIMD3<Float>] {
        guard let first = vertices.first else { return [] }
        var minPoint = first
        var maxPoint = first

        for vertex in vertices.dropFirst() {
            minPoint = SIMD3<Float>(min(minPoint.x, vertex.x), min(minPoint.y, vertex.y), min(minPoint.z, vertex.z))
            maxPoint = SIMD3<Float>(max(maxPoint.x, vertex.x), max(maxPoint.y, vertex.y), max(maxPoint.z, vertex.z))
        }

        let center = (minPoint + maxPoint) / 2
        let size = max(maxPoint.x - minPoint.x, max(maxPoint.y - minPoint.y, maxPoint.z - minPoint.z))
        let scale: Float = size > 0 ? 3.4 / size : 1

        return vertices.map { vertex in
            let centered = (vertex - center) * scale
            return SIMD3<Float>(centered.x, centered.z, -centered.y)
        }
    }
}

private struct AIEnrichmentSection: View {
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

private struct TagChip: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Label(title, systemImage: "tag")
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.35), in: Capsule())
    }
}

private struct ReviewReasonChip: View {
    let reason: ReviewReason
    let isDismissed: Bool

    var body: some View {
        Label(reason.title, systemImage: reason.systemImage)
            .font(.caption)
            .foregroundStyle(isDismissed ? Color.secondary : Color.orange)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.35), in: Capsule())
    }
}

private struct SuggestedTagChip: View {
    @EnvironmentObject private var viewModel: LibraryViewModel
    let tag: GeneratedTag
    let record: PrintFileRecord

    var body: some View {
        HStack(spacing: 4) {
            Text(tag.value)
            Button {
                viewModel.acceptGeneratedTag(tag, for: record)
            } label: {
                Image(systemName: "checkmark")
            }
            .buttonStyle(.borderless)
            .help("Accept tag")

            Button {
                viewModel.rejectGeneratedTag(tag, for: record)
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Reject tag")
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.35), in: Capsule())
    }
}

private struct DetailSection<Content: View, Accessory: View>: View {
    let title: String
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    init(title: String, @ViewBuilder content: () -> Content) where Accessory == EmptyView {
        self.title = title
        self.accessory = EmptyView()
        self.content = content()
    }

    init(title: String, @ViewBuilder accessory: () -> Accessory, @ViewBuilder content: () -> Content) {
        self.title = title
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                Spacer()
                accessory
            }
            content
        }
    }
}

private struct MetadataRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 84, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .font(.caption)
    }
}

private struct SourceURLRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 84, alignment: .leading)
            if let url = URL(string: value), value != "Not set" {
                Link(value, destination: url)
                    .lineLimit(2)
                    .textSelection(.enabled)
            } else {
                Text(value)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .font(.caption)
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 320
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX > 0, currentX + size.width > maxWidth {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        return CGSize(width: maxWidth, height: currentY + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX > bounds.minX, currentX + size.width > bounds.maxX {
                currentX = bounds.minX
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: ProposedViewSize(size))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(LibraryViewModel())
    .environmentObject(AISettingsStore())
}
