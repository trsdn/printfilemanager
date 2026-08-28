import CryptoKit
import Foundation

public struct LibraryScanResult: Equatable, Sendable {
    public var root: LibraryRoot
    public var rootIsAvailable: Bool
    public var records: [PrintFileRecord]
    public var scannedAt: Date

    public init(root: LibraryRoot, rootIsAvailable: Bool, records: [PrintFileRecord], scannedAt: Date = Date()) {
        self.root = root
        self.rootIsAvailable = rootIsAvailable
        self.records = records
        self.scannedAt = scannedAt
    }
}

public struct LibraryIndexer {
    private let thumbnailStore: ThumbnailStore?

    public init(thumbnailStore: ThumbnailStore? = nil) {
        self.thumbnailStore = thumbnailStore
    }

    /// Scans a root for `.3mf` files.
    ///
    /// - Parameter previousRecords: records from an earlier scan of the same root. Files whose
    ///   size and modification date are unchanged are carried over verbatim instead of being
    ///   re-hashed and re-parsed, which is what makes repeated scans cheap on a large library.
    public func scan(root: LibraryRoot, previousRecords: [PrintFileRecord] = []) throws -> LibraryScanResult {
        let rootURL = root.url.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return LibraryScanResult(root: root, rootIsAvailable: false, records: [])
        }

        let resourceKeys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return LibraryScanResult(root: root, rootIsAvailable: false, records: [])
        }

        let extractor = ThreeMFPreviewExtractor()
        let metadataExtractor = ThreeMFMetadataExtractor()
        var records: [PrintFileRecord] = []

        var reusableRecords: [String: PrintFileRecord] = [:]
        for record in previousRecords where record.indexingStatus == .indexed && record.contentHash != nil {
            reusableRecords[record.url.standardizedFileURL.path] = record
        }

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension.lowercased() == "3mf" else { continue }
            let standardizedURL = fileURL.standardizedFileURL
            let values = try standardizedURL.resourceValues(forKeys: Set(resourceKeys))
            guard values.isRegularFile == true else { continue }

            let fileSize = Int64(values.fileSize ?? 0)
            let modifiedAt = values.contentModificationDate

            if let previous = reusableRecords[standardizedURL.path],
               previous.fileSize == fileSize,
               Self.isSameModificationDate(previous.modifiedAt, modifiedAt) {
                records.append(previous)
                continue
            }

            records.append(indexFile(
                fileURL: standardizedURL,
                root: root,
                rootURL: rootURL,
                fileSize: fileSize,
                modifiedAt: modifiedAt,
                extractor: extractor,
                metadataExtractor: metadataExtractor
            ))
        }

        return LibraryScanResult(root: root, rootIsAvailable: true, records: records)
    }

    /// File systems store modification dates at differing resolutions, so compare at whole seconds.
    private static func isSameModificationDate(_ lhs: Date?, _ rhs: Date?) -> Bool {
        guard let lhs, let rhs else { return lhs == nil && rhs == nil }
        return abs(lhs.timeIntervalSince(rhs)) < 1
    }

    private func indexFile(
        fileURL: URL,
        root: LibraryRoot,
        rootURL: URL,
        fileSize: Int64,
        modifiedAt: Date?,
        extractor: ThreeMFPreviewExtractor,
        metadataExtractor: ThreeMFMetadataExtractor
    ) -> PrintFileRecord {
        let relativePath = Self.relativePath(for: fileURL, rootURL: rootURL)
        let contentHash = try? Self.sha256Hash(for: fileURL)
        let metadataSummary = try? metadataExtractor.extract(from: fileURL)
        let previewResult = extractor.preview(for: fileURL, maxPixelDimension: 420)

        let previewStatus: PreviewStatus
        let thumbnailKey: String?
        switch previewResult {
        case .preview(let image):
            previewStatus = .available
            thumbnailKey = try? thumbnailStore?.store(image.data)
        case .fallback(let fallback):
            previewStatus = fallback.reason == .noSupportedImage ? .missing : .failed
            thumbnailKey = nil
        }

        let indexingStatus: IndexingStatus = metadataSummary == nil ? .failed : .indexed
        let errorMessage = metadataSummary == nil ? "Package metadata could not be read." : nil
        let generatedTags = LocalTagSuggester().suggestTags(
            fileName: fileURL.deletingPathExtension().lastPathComponent,
            sourceHints: metadataSummary?.sourceHints ?? [],
            metadata: metadataSummary?.metadata ?? [:]
        )

        return PrintFileRecord(
            rootID: root.id,
            url: fileURL,
            fileName: fileURL.lastPathComponent,
            relativePath: relativePath,
            fileSize: fileSize,
            modifiedAt: modifiedAt,
            contentHash: contentHash,
            indexedAt: Date(),
            indexingStatus: indexingStatus,
            previewStatus: previewStatus,
            thumbnailKey: thumbnailKey,
            projectName: metadataSummary?.projectName ?? fileURL.deletingPathExtension().lastPathComponent,
            sourceHints: metadataSummary?.sourceHints ?? [],
            metadata: metadataSummary?.metadata ?? [:],
            generatedTags: generatedTags,
            errorMessage: errorMessage,
            projectKey: metadataSummary?.projectKey,
            variantName: metadataSummary?.variantName,
            category: metadataSummary?.category,
            printability: metadataSummary?.printability,
            sourceInfo: metadataSummary?.sourceInfo,
            printDetails: metadataSummary?.printDetails
        )
    }

    private static func relativePath(for fileURL: URL, rootURL: URL) -> String {
        let filePath = fileURL.standardizedFileURL.path
        let rootPath = rootURL.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath) else { return fileURL.lastPathComponent }
        let startIndex = filePath.index(filePath.startIndex, offsetBy: rootPath.count)
        return String(filePath[startIndex...]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func sha256Hash(for url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let data = try? handle.read(upToCount: 1_048_576)
            guard let data, !data.isEmpty else { return false }
            hasher.update(data: data)
            return true
        }) {}

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

public struct ThreeMFMetadataSummary: Equatable, Sendable {
    public var projectName: String?
    public var sourceHints: [String]
    public var metadata: [String: String]
    public var projectKey: String?
    public var variantName: String?
    public var category: String?
    public var printability: PrintabilityStatus?
    public var sourceInfo: PrintSourceInfo?
    public var printDetails: PrintDetails?
}

public struct ThreeMFMetadataExtractor {
    private let reader: any ThreeMFPackageReading

    public init(reader: any ThreeMFPackageReading = ZIPFoundationThreeMFPackageReader()) {
        self.reader = reader
    }

    public func extract(from packageURL: URL) throws -> ThreeMFMetadataSummary {
        let entries = try reader.fileEntries(in: packageURL)
        var metadata: [String: String] = [
            "entryCount": String(entries.count)
        ]

        let paths = entries.map(\.path)
        let lowercasePaths = paths.map { $0.lowercased() }
        let plateCount = Self.plateCount(in: lowercasePaths)
        if plateCount > 0 {
            metadata["plateCount"] = String(plateCount)
        }

        var sourceHints = ["3MF"]
        if lowercasePaths.contains(where: { $0.hasPrefix("metadata/plate_") || $0.contains("bambu") }) {
            sourceHints.append("Bambu Studio / MakerWorld")
        }

        for entry in entries where Self.isSmallTextMetadataEntry(entry) {
            guard let data = try? reader.data(for: entry, in: packageURL) else { continue }
            let fields = ThreeMFDomainXMLParser.metadataFields(from: data)
            for (key, value) in fields where metadata[key] == nil {
                metadata[key] = value
            }
        }

        let projectName = metadata["Title"] ?? metadata["title"] ?? metadata["Name"] ?? metadata["name"]
        let fileName = packageURL.deletingPathExtension().lastPathComponent
        let effectiveProjectName = projectName ?? fileName
        let printDetails = PrintDetails.from(metadata: metadata, plateCount: plateCount)
        let sourceInfo = PrintSourceInfo.from(metadata: metadata, sourceHints: sourceHints)
        return ThreeMFMetadataSummary(
            projectName: projectName,
            sourceHints: Array(Set(sourceHints)).sorted(),
            metadata: metadata,
            projectKey: DomainClassifier.projectKey(for: effectiveProjectName),
            variantName: DomainClassifier.variantName(for: fileName, metadata: metadata),
            category: DomainClassifier.category(for: effectiveProjectName, metadata: metadata),
            printability: DomainClassifier.printability(metadata: metadata, details: printDetails),
            sourceInfo: sourceInfo,
            printDetails: printDetails
        )
    }

    private static func plateCount(in paths: [String]) -> Int {
        var plateIDs = Set<String>()
        for path in paths where path.hasPrefix("metadata/plate_") && !path.contains("_small") {
            let suffix = path.dropFirst("metadata/plate_".count)
            let digits = suffix.prefix { $0.isNumber }
            if !digits.isEmpty {
                plateIDs.insert(String(digits))
            }
        }
        return plateIDs.count
    }

    private static func isSmallTextMetadataEntry(_ entry: ThreeMFPackageEntry) -> Bool {
        guard entry.uncompressedSize <= 2_000_000 else { return false }
        let path = entry.path.lowercased()
        return path.hasSuffix(".model") || path.hasSuffix(".xml") || path.hasSuffix(".config")
    }
}

public struct LocalTagSuggester {
    public init() {}

    public func suggestTags(fileName: String, sourceHints: [String], metadata: [String: String]) -> [GeneratedTag] {
        var tags = Set<String>()
        let ignoredTokens: Set<String> = ["3mf", "bambu", "makerworld"]

        for token in fileName
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ") {
            let normalized = token.trimmingCharacters(in: .punctuationCharacters).lowercased()
            if normalized.count >= 4,
               normalized.rangeOfCharacter(from: .decimalDigits) == nil,
               !ignoredTokens.contains(normalized) {
                tags.insert(normalized)
            }
        }

        return tags.sorted().map {
            GeneratedTag(value: $0, confidence: 0.55, source: "local")
        }
    }
}

private final class ThreeMFDomainXMLParser: NSObject, XMLParserDelegate {
    private var fields: [String: String] = [:]
    private var currentName: String?
    private var currentText = ""
    private var objectCount = 0
    private var buildItemCount = 0
    private var materialCount = 0
    private var colorCount = 0
    private var materialNames = Set<String>()
    private var colors = Set<String>()

    static func metadataFields(from data: Data) -> [String: String] {
        let delegate = ThreeMFDomainXMLParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        delegate.addCountFields()
        return delegate.fields
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName.lowercased() {
        case "metadata":
            currentName = attributeDict["name"] ?? attributeDict["Name"]
            currentText = ""
        case "object":
            objectCount += 1
        case "item":
            buildItemCount += 1
        case "base":
            materialCount += 1
            if let name = attributeDict["name"], !name.isEmpty {
                materialNames.insert(name)
            }
            if let color = attributeDict["displaycolor"], !color.isEmpty {
                colors.insert(color)
            }
        case "color":
            colorCount += 1
            if let color = attributeDict["color"], !color.isEmpty {
                colors.insert(color)
            }
        default:
            return
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard currentName != nil else { return }
        currentText.append(string)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard elementName.lowercased() == "metadata", let currentName else { return }
        let value = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty {
            fields[currentName] = value
        }
        self.currentName = nil
        currentText = ""
    }

    private func addCountFields() {
        if objectCount > 0 { fields["objectCount"] = String(objectCount) }
        if buildItemCount > 0 { fields["buildItemCount"] = String(buildItemCount) }
        if materialCount > 0 { fields["materialCount"] = String(materialCount) }
        if colorCount > 0 { fields["colorCount"] = String(colorCount) }
        if !materialNames.isEmpty {
            fields["materials"] = materialNames.sorted().joined(separator: ", ")
        }
        if !colors.isEmpty {
            fields["colors"] = colors.sorted().joined(separator: ", ")
        }
    }
}

private extension PrintDetails {
    static func from(metadata: [String: String], plateCount: Int) -> PrintDetails {
        PrintDetails(
            plateCount: plateCount > 0 ? plateCount : intValue(metadata, keys: ["plateCount"]),
            objectCount: intValue(metadata, keys: ["objectCount"]),
            buildItemCount: intValue(metadata, keys: ["buildItemCount"]),
            materialCount: intValue(metadata, keys: ["materialCount", "filamentCount"]),
            colorCount: intValue(metadata, keys: ["colorCount"]),
            materials: listValue(metadata, keys: ["materials", "filament_type", "filamentType", "Material", "material"]),
            colors: listValue(metadata, keys: ["colors", "filament_colour", "filamentColor"]),
            slicer: stringValue(metadata, keys: ["Application", "application", "slicer", "Producer", "producer"]),
            printer: stringValue(metadata, keys: ["printer", "printer_model", "printerModel", "Printer", "Machine"]),
            nozzleDiameter: stringValue(metadata, keys: ["nozzle_diameter", "nozzleDiameter", "NozzleDiameter"]),
            layerHeight: stringValue(metadata, keys: ["layer_height", "layerHeight", "LayerHeight"]),
            estimatedPrintTime: stringValue(metadata, keys: ["print_time", "estimatedPrintTime", "PrintTime"]),
            estimatedFilament: stringValue(metadata, keys: ["filament_used", "filamentUsed", "used_filament", "FilamentUsed"])
        )
    }

    private static func intValue(_ metadata: [String: String], keys: [String]) -> Int? {
        for key in keys {
            guard let value = metadata[key] else { continue }
            if let intValue = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return intValue
            }
        }
        return nil
    }

    private static func stringValue(_ metadata: [String: String], keys: [String]) -> String? {
        for key in keys {
            guard let value = metadata[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { continue }
            return value
        }
        return nil
    }

    private static func listValue(_ metadata: [String: String], keys: [String]) -> [String] {
        for key in keys {
            guard let value = metadata[key], !value.isEmpty else { continue }
            return value
                .components(separatedBy: CharacterSet(charactersIn: ",;"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        return []
    }
}

private extension PrintSourceInfo {
    static func from(metadata: [String: String], sourceHints: [String]) -> PrintSourceInfo? {
        let url = firstValue(metadata, keys: ["source_url", "sourceURL", "SourceURL", "url", "URL", "Source"])
        let platform = firstValue(metadata, keys: ["platform", "sourcePlatform", "SourcePlatform"])
            ?? platformName(from: url)
            ?? sourceHints.first { $0.localizedCaseInsensitiveContains("MakerWorld") || $0.localizedCaseInsensitiveContains("Bambu") }
        let author = firstValue(metadata, keys: ["author", "Author", "designer", "Designer", "creator", "Creator"])
        let license = firstValue(metadata, keys: ["license", "License", "copyright", "Copyright"])

        guard platform != nil || author != nil || license != nil || url != nil else { return nil }
        return PrintSourceInfo(platform: platform, author: author, license: license, url: url)
    }

    private static func firstValue(_ metadata: [String: String], keys: [String]) -> String? {
        for key in keys {
            guard let value = metadata[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { continue }
            return value
        }
        return nil
    }

    private static func platformName(from value: String?) -> String? {
        guard let value = value?.lowercased() else { return nil }
        if value.contains("makerworld") { return "MakerWorld" }
        if value.contains("printables") { return "Printables" }
        if value.contains("thingiverse") { return "Thingiverse" }
        if value.contains("github") { return "GitHub" }
        return nil
    }
}

private enum DomainClassifier {
    static func projectKey(for name: String) -> String {
        normalizedWords(from: name)
            .filter { !variantTokens.contains($0) }
            .joined(separator: "-")
    }

    static func variantName(for fileName: String, metadata: [String: String]) -> String? {
        var variants = normalizedWords(from: fileName).filter { variantTokens.contains($0) }
        if let material = metadata["materials"] ?? metadata["filament_type"] {
            variants.append(contentsOf: normalizedWords(from: material).filter { materialTokens.contains($0) })
        }
        let unique = Array(Set(variants)).sorted()
        return unique.isEmpty ? nil : unique.joined(separator: ", ")
    }

    static func category(for name: String, metadata: [String: String]) -> String {
        let haystack = (name + " " + metadata.values.joined(separator: " ")).lowercased()
        if containsAny(haystack, ["cable", "wire", "holder", "clip", "mount", "bracket", "hook"]) { return "Functional Part" }
        if containsAny(haystack, ["jig", "fixture", "template", "tool"]) { return "Jig / Fixture" }
        if containsAny(haystack, ["spare", "replacement", "repair"]) { return "Replacement Part" }
        if containsAny(haystack, ["toy", "game", "figurine"]) { return "Toy" }
        if containsAny(haystack, ["vase", "decor", "ornament", "art"]) { return "Decoration" }
        if containsAny(haystack, ["mod", "upgrade", "bambu", "printer"]) { return "Printer Mod" }
        return "Uncategorized"
    }

    static func printability(metadata: [String: String], details: PrintDetails) -> PrintabilityStatus {
        if (details.materialCount ?? 0) > 1 || (details.colorCount ?? 0) > 1 { return .multiMaterial }
        if details.printer != nil { return .printerSpecific }
        if (details.plateCount ?? 0) > 0 { return .readyToPrint }
        if metadata["objectCount"] != nil { return .needsSlicing }
        return .needsReview
    }

    private static let variantTokens = Set([
        "pla", "petg", "abs", "asa", "tpu", "pa", "nylon", "strong", "heavy", "light", "thin", "thick",
        "scaled", "scale", "fixed", "repaired", "remix", "v2", "v3", "ams", "multicolor", "multi", "support", "supports"
    ])

    private static let materialTokens = Set(["pla", "petg", "abs", "asa", "tpu", "pa", "nylon"])

    private static func normalizedWords(from value: String) -> [String] {
        value
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count > 1 }
    }

    private static func containsAny(_ value: String, _ needles: [String]) -> Bool {
        needles.contains { value.contains($0) }
    }
}
