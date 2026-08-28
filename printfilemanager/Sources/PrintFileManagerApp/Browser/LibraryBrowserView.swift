import AppKit
import PrintFileManagerCore
import SwiftUI

struct LibraryBrowserView: View {
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
                    .accessibilityLabel(viewModel.sortAscending ? "Sort ascending" : "Sort descending")
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
                EmptyResultsView()
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(viewModel.filteredRecords) { record in
                            FileTile(record: record, isSelected: viewModel.selectedRecordIDs.contains(record.id))
                                .onTapGesture {
                                    let flags = NSApp.currentEvent?.modifierFlags ?? []
                                    let modifier: LibraryViewModel.SelectionModifier =
                                        flags.contains(.shift) ? .extendRange
                                        : flags.contains(.command) ? .toggle
                                        : .replace
                                    viewModel.select(record: record, modifier: modifier)
                                }
                        }
                    }
                    .padding(16)
                }
            }
        }
    }
}

/// Distinguishes "your search found nothing" from "this collection is legitimately empty", and
/// always offers the action that resolves it. A single generic message leaves the user stuck.

struct EmptyResultsView: View {
    @EnvironmentObject private var viewModel: LibraryViewModel

    var body: some View {
        if !viewModel.searchText.isEmpty {
            ContentUnavailableView {
                Label("No files match “\(viewModel.searchText)”", systemImage: "magnifyingglass")
            } description: {
                Text("Search looks at names, folders, tags, notes and extracted metadata.")
            } actions: {
                Button("Clear Search") { viewModel.searchText = "" }
            }
        } else if viewModel.activeFilterCount > 0 {
            ContentUnavailableView {
                Label("No files match your filters", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("\(viewModel.activeFilterCount) filters are active.")
            } actions: {
                Button("Clear Filters") { viewModel.clearFilters() }
            }
        } else if viewModel.snapshot.records.isEmpty {
            ContentUnavailableView {
                Label("Nothing indexed yet", systemImage: "tray")
            } description: {
                Text("Your folders have been added but contain no .3mf files, or have not been scanned yet.")
            } actions: {
                Button("Rescan All") { viewModel.rescanAllRoots() }
                    .disabled(viewModel.isScanning)
            }
        } else {
            ContentUnavailableView {
                Label(emptyCollectionTitle, systemImage: viewModel.selectedCollection?.systemImage ?? "tray")
            } description: {
                Text(emptyCollectionMessage)
            } actions: {
                Button("Show All Files") { viewModel.select(collection: .all) }
            }
        }
    }

    private var emptyCollectionTitle: String {
        switch viewModel.selectedCollection {
        case .needsReview: return "Nothing needs review"
        case .untagged: return "Everything is tagged"
        case .missingPreview: return "Every file has a preview"
        case .indexingErrors: return "No unreadable files"
        case .duplicateCandidates: return "No duplicates found"
        default: return "Nothing here yet"
        }
    }

    private var emptyCollectionMessage: String {
        switch viewModel.selectedCollection {
        case .needsReview: return "Every file has the information it needs."
        case .untagged: return "All indexed files carry at least one tag."
        case .missingPreview: return "Every indexed file has a usable preview image."
        case .indexingErrors: return "Every file in your library could be read."
        case .duplicateCandidates: return "No two files share the same contents."
        default: return "This collection has no files in it."
        }
    }
}

struct EmptyLibraryView: View {
    @EnvironmentObject private var viewModel: LibraryViewModel

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 10) {
                Image(systemName: "shippingbox")
                    .font(.system(size: 40))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                Text("Find your print files again")
                    .font(.title2.weight(.semibold))

                Text("Point the app at the folders where your .3mf files already live. Nothing is moved, renamed or deleted until you ask for it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 420)
            }

            VStack(alignment: .leading, spacing: 10) {
                OnboardingStep(number: 1, title: "Add a folder", detail: "Every .3mf inside it is indexed, including subfolders.")
                OnboardingStep(number: 2, title: "Browse and search", detail: "Previews, printer and material details, tags and notes.")
                OnboardingStep(number: 3, title: "Sort when you are ready", detail: "Copy or move into a managed library — always previewed first, and undoable.")
            }
            .frame(maxWidth: 420, alignment: .leading)

            Button {
                viewModel.addFolderFromPanel()
            } label: {
                Label("Add a Folder", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Label("Indexing runs entirely on this Mac. AI enrichment and web lookup are optional and switched off until you enable them in Settings.", systemImage: "lock")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 420)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct OnboardingStep: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Color.accentColor, in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
