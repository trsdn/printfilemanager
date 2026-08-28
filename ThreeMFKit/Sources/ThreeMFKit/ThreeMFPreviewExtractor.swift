import Foundation

public struct ThreeMFPreviewExtractor: Sendable {
    private let reader: any ThreeMFPackageReading
    private let resolver: any PreviewImageResolving
    private let normalizer: any ImageNormalizing

    public init(
        reader: any ThreeMFPackageReading = ZIPFoundationThreeMFPackageReader(),
        resolver: any PreviewImageResolving = BambuPreviewResolver(),
        normalizer: any ImageNormalizing = CGImagePreviewImageNormalizer()
    ) {
        self.reader = reader
        self.resolver = resolver
        self.normalizer = normalizer
    }

    public func preview(for packageURL: URL, maxPixelDimension: Int? = nil) -> PreviewExtractionResult {
        let entries: [ThreeMFPackageEntry]
        do {
            entries = try reader.fileEntries(in: packageURL)
        } catch {
            return .fallback(PreviewFallback(reason: .unreadablePackage, fileName: packageURL.lastPathComponent))
        }

        let candidates = resolver.orderedPreviewCandidates(in: entries)

        guard Self.isThreeMFPackage(entries: entries) else {
            return .fallback(PreviewFallback(reason: .notAThreeMFPackage, fileName: packageURL.lastPathComponent))
        }

        guard !candidates.isEmpty else {
            return .fallback(PreviewFallback(reason: .noSupportedImage, fileName: packageURL.lastPathComponent))
        }

        for candidate in candidates {
            guard let data = try? reader.data(for: candidate, in: packageURL) else {
                continue
            }

            if let image = normalizer.normalize(data, maxPixelDimension: maxPixelDimension) {
                return .preview(image)
            }
        }

        return .fallback(PreviewFallback(reason: .imageNormalizationFailed, fileName: packageURL.lastPathComponent))
    }

    /// A 3MF is an OPC package that must carry the 3D model part. Checking for it distinguishes a
    /// real 3MF from any other zip archive the extension is offered.
    static func isThreeMFPackage(entries: [ThreeMFPackageEntry]) -> Bool {
        entries.contains { entry in
            let path = entry.path.lowercased()
            return path.hasSuffix(".model") && path.hasPrefix("3d/")
        }
    }
}
