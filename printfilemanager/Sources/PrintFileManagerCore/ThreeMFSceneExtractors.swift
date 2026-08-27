import Foundation
import simd

public struct PlatePreview: Identifiable, Equatable, Sendable {
    public var id: Int { index }
    public let index: Int
    public let title: String
    public let imageData: Data

    public init(index: Int, title: String, imageData: Data) {
        self.index = index
        self.title = title
        self.imageData = imageData
    }
}

public struct ThreeMFTriangle: Equatable, Sendable {
    public let a: Int32
    public let b: Int32
    public let c: Int32

    public init(a: Int32, b: Int32, c: Int32) {
        self.a = a
        self.b = b
        self.c = c
    }
}

public struct ThreeMFMesh: Equatable, Sendable {
    public let vertices: [SIMD3<Float>]
    public let triangles: [ThreeMFTriangle]

    public init(vertices: [SIMD3<Float>], triangles: [ThreeMFTriangle]) {
        self.vertices = vertices
        self.triangles = triangles
    }
}

public struct PlatePreviewExtractor {
    private let reader: any ThreeMFPackageReading
    private let normalizer: any ImageNormalizing

    public init(
        reader: any ThreeMFPackageReading = ZIPFoundationThreeMFPackageReader(),
        normalizer: any ImageNormalizing = CGImagePreviewImageNormalizer()
    ) {
        self.reader = reader
        self.normalizer = normalizer
    }

    public func previews(for packageURL: URL, maxPixelDimension: Int? = 900) -> [PlatePreview] {
        guard let entries = try? reader.fileEntries(in: packageURL) else { return [] }

        let plateEntries = entries.compactMap { entry -> (Int, ThreeMFPackageEntry)? in
            guard let index = Self.plateIndex(for: entry.path) else { return nil }
            return (index, entry)
        }
        .sorted { left, right in
            if left.0 == right.0 {
                return left.1.path.localizedStandardCompare(right.1.path) == .orderedAscending
            }
            return left.0 < right.0
        }

        let previews = plateEntries.compactMap { index, entry -> PlatePreview? in
            guard let data = try? reader.data(for: entry, in: packageURL),
                  let image = normalizer.normalize(data, maxPixelDimension: maxPixelDimension) else {
                return nil
            }
            return PlatePreview(index: index, title: "Plate \(index)", imageData: image.data)
        }

        if !previews.isEmpty {
            return previews
        }

        return fallbackCoverPreview(from: entries, packageURL: packageURL, maxPixelDimension: maxPixelDimension)
    }

    private func fallbackCoverPreview(
        from entries: [ThreeMFPackageEntry],
        packageURL: URL,
        maxPixelDimension: Int?
    ) -> [PlatePreview] {
        let resolver = BambuPreviewResolver()
        guard let entry = resolver.orderedPreviewCandidates(in: entries).first,
              let data = try? reader.data(for: entry, in: packageURL),
              let image = normalizer.normalize(data, maxPixelDimension: maxPixelDimension) else {
            return []
        }
        return [PlatePreview(index: 1, title: "Preview", imageData: image.data)]
    }

    private static func plateIndex(for path: String) -> Int? {
        let normalized = path.lowercased()
        guard normalized.hasPrefix("metadata/plate_"),
              !normalized.contains("_small"),
              normalized.hasSuffix(".png") || normalized.hasSuffix(".jpg") || normalized.hasSuffix(".jpeg") else {
            return nil
        }

        let suffix = normalized.dropFirst("metadata/plate_".count)
        let digits = suffix.prefix { $0.isNumber }
        return Int(digits)
    }
}

public struct ThreeMFMeshExtractor {
    private let reader: any ThreeMFPackageReading

    public init(reader: any ThreeMFPackageReading = ZIPFoundationThreeMFPackageReader()) {
        self.reader = reader
    }

    public func mesh(for packageURL: URL) -> ThreeMFMesh? {
        guard let entries = try? reader.fileEntries(in: packageURL) else { return nil }
        let modelEntries = entries
            .filter { $0.path.lowercased().hasSuffix(".model") }
            .sorted { left, right in
                if left.path.lowercased() == "3d/3dmodel.model" { return true }
                if right.path.lowercased() == "3d/3dmodel.model" { return false }
                return left.path.localizedStandardCompare(right.path) == .orderedAscending
            }

        for entry in modelEntries {
            guard let data = try? reader.data(for: entry, in: packageURL) else { continue }
            let mesh = ThreeMFMeshXMLParser.parse(data: data)
            if !mesh.vertices.isEmpty, !mesh.triangles.isEmpty {
                return mesh
            }
        }

        return nil
    }
}

private final class ThreeMFMeshXMLParser: NSObject, XMLParserDelegate {
    private var vertices: [SIMD3<Float>] = []
    private var triangles: [ThreeMFTriangle] = []
    private var currentMeshVertexBase = 0

    static func parse(data: Data) -> ThreeMFMesh {
        let delegate = ThreeMFMeshXMLParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return ThreeMFMesh(vertices: delegate.vertices, triangles: delegate.triangles)
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName.lowercased() {
        case "mesh":
            currentMeshVertexBase = vertices.count
        case "vertex":
            guard let x = Float(attributeDict["x"] ?? ""),
                  let y = Float(attributeDict["y"] ?? ""),
                  let z = Float(attributeDict["z"] ?? "") else {
                return
            }
            vertices.append(SIMD3<Float>(x, y, z))
        case "triangle":
            guard let v1 = Int32(attributeDict["v1"] ?? ""),
                  let v2 = Int32(attributeDict["v2"] ?? ""),
                  let v3 = Int32(attributeDict["v3"] ?? "") else {
                return
            }
            let base = Int32(currentMeshVertexBase)
            triangles.append(ThreeMFTriangle(a: base + v1, b: base + v2, c: base + v3))
        default:
            return
        }
    }
}