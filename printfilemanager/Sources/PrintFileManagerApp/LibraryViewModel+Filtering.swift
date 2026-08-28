import Foundation
import PrintFileManagerCore

/// Facet vocabularies and the filter toggles behind the browser's filter menu.
@MainActor
extension LibraryViewModel {
    var allTags: [String] {
        let tags = snapshot.records.flatMap { record in
            record.userTags + record.generatedTags.filter { $0.state == .accepted }.map(\.value)
        }
        return Array(Set(tags)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    var allMaterials: [String] {
        let values = snapshot.records.flatMap { record in
            var materials = record.printDetails?.materials ?? []
            if let aiMaterialHints = record.metadata["ai.materialHints"] {
                materials.append(contentsOf: aiMaterialHints.components(separatedBy: ","))
            }
            return materials
        }
        return normalizedFacetValues(values)
    }

    var allPrinters: [String] {
        let values = snapshot.records.flatMap { record in
            var printers: [String] = []
            if let printer = record.printDetails?.printer {
                printers.append(printer)
            }
            if let history = record.printHistory {
                printers.append(contentsOf: history.map(\.printer))
            }
            return printers
        }
        return normalizedFacetValues(values)
    }

    var allSourcePlatforms: [String] {
        normalizedFacetValues(snapshot.records.compactMap { $0.sourceInfo?.platform })
    }

    var availableSourceVersionStatuses: [SourceVersionStatus] {
        let statuses = Set(snapshot.records.map(sourceVersionStatus(for:)))
        return SourceVersionStatus.allCases.filter { statuses.contains($0) }
    }

    var activeFilterCount: Int {
        selectedTags.count
            + selectedPrintabilities.count
            + selectedMaterials.count
            + selectedPrinters.count
            + selectedSourcePlatforms.count
            + selectedSourceVersionStatuses.count
    }

    func clearFilters() {
        selectedTags.removeAll()
        selectedPrintabilities.removeAll()
        selectedMaterials.removeAll()
        selectedPrinters.removeAll()
        selectedSourcePlatforms.removeAll()
        selectedSourceVersionStatuses.removeAll()
    }

    func toggleTagFilter(_ tag: String) {
        toggleTrimmedString(tag, in: &selectedTags)
    }

    func toggleMaterialFilter(_ material: String) {
        toggleTrimmedString(material, in: &selectedMaterials)
    }

    func togglePrinterFilter(_ printer: String) {
        toggleTrimmedString(printer, in: &selectedPrinters)
    }

    func toggleSourcePlatformFilter(_ platform: String) {
        toggleTrimmedString(platform, in: &selectedSourcePlatforms)
    }

    func togglePrintabilityFilter(_ printability: PrintabilityStatus) {
        if selectedPrintabilities.contains(printability) {
            selectedPrintabilities.remove(printability)
        } else {
            selectedPrintabilities.insert(printability)
        }
    }

    func toggleSourceVersionStatusFilter(_ status: SourceVersionStatus) {
        if selectedSourceVersionStatuses.contains(status) {
            selectedSourceVersionStatuses.remove(status)
        } else {
            selectedSourceVersionStatuses.insert(status)
        }
    }
}
