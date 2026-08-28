import PrintFileManagerCore
import SwiftUI

struct FilterMenuView: View {
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

struct ActiveFilterBar: View {
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

struct ActiveFilterChip: View {
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
