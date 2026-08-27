import Foundation

public protocol PreviewImageResolving: Sendable {
    func orderedPreviewCandidates(in entries: [ThreeMFPackageEntry]) -> [ThreeMFPackageEntry]
}

/// Ranks the images inside a `.3mf` package by how well each one works as a human-facing preview.
///
/// Slicers ship several images with very different purposes: an isometric "hero" render of the
/// build plate, a top-down orthographic view, low-resolution variants, and an object-picking mask
/// used for hit testing. Only the hero render reliably identifies a model at a glance, so it must
/// win over the rest; picking masks are flat colour-coded bitmaps and are excluded outright.
///
/// Lower ranks are preferred.
public struct BambuPreviewResolver: PreviewImageResolving {
    public init() {}

    public func orderedPreviewCandidates(in entries: [ThreeMFPackageEntry]) -> [ThreeMFPackageEntry] {
        entries
            .compactMap { entry -> RankedEntry? in
                guard let rank = rank(for: entry.path) else {
                    return nil
                }
                return RankedEntry(entry: entry, rank: rank)
            }
            .sorted { left, right in
                if left.rank == right.rank {
                    return left.entry.path.localizedStandardCompare(right.entry.path) == .orderedAscending
                }
                return left.rank < right.rank
            }
            .map(\.entry)
    }

    private enum Rank {
        static let auxiliaryMiddleThumbnail = 0
        static let auxiliary3MFThumbnail = 10
        static let auxiliarySmallThumbnail = 20
        static let auxiliaryOtherThumbnail = 30
        static let platePreview = 100
        static let genericThumbnail = 150
        static let plateWithoutLighting = 200
        static let smallPlatePreview = 250
        static let topDownPreview = 300
        static let otherMetadataImage = 400
        static let unrelatedImage = 900
    }

    private func rank(for path: String) -> Int? {
        let normalizedPath = path.lowercased()
        guard isSupportedImagePath(normalizedPath), !isPickMask(normalizedPath) else {
            return nil
        }

        if normalizedPath.hasPrefix("auxiliaries/.thumbnails/") {
            switch normalizedPath {
            case "auxiliaries/.thumbnails/thumbnail_middle.png":
                return Rank.auxiliaryMiddleThumbnail
            case "auxiliaries/.thumbnails/thumbnail_3mf.png":
                return Rank.auxiliary3MFThumbnail
            case "auxiliaries/.thumbnails/thumbnail_small.png":
                return Rank.auxiliarySmallThumbnail
            default:
                return Rank.auxiliaryOtherThumbnail
            }
        }

        // Images outside the known preview locations are usually textures or materials.
        guard normalizedPath.hasPrefix("metadata/") else {
            return Rank.unrelatedImage
        }

        if normalizedPath.hasPrefix("metadata/plate_") {
            if normalizedPath.contains("plate_no_light") {
                return Rank.plateWithoutLighting
            }
            return isSmallVariant(normalizedPath) ? Rank.smallPlatePreview : Rank.platePreview
        }

        if normalizedPath.hasPrefix("metadata/top_") {
            return Rank.topDownPreview
        }

        // Non-Bambu slicers commonly emit a single generic Metadata/thumbnail.png.
        if normalizedPath.contains("thumbnail") || normalizedPath.contains("thumb") || normalizedPath.contains("preview") {
            return Rank.genericThumbnail
        }

        return Rank.otherMetadataImage
    }

    /// Object-picking masks encode object IDs as flat colours for hit testing and never depict the model.
    private func isPickMask(_ path: String) -> Bool {
        path.hasPrefix("metadata/pick_") || path.hasPrefix("metadata/top_pick")
    }

    private func isSmallVariant(_ path: String) -> Bool {
        path.contains("_small") || path.contains("small_")
    }

    private func isSupportedImagePath(_ path: String) -> Bool {
        path.hasSuffix(".png") || path.hasSuffix(".jpg") || path.hasSuffix(".jpeg")
    }

    private struct RankedEntry {
        let entry: ThreeMFPackageEntry
        let rank: Int
    }
}
