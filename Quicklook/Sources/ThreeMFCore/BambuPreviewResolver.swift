import Foundation

public protocol PreviewImageResolving: Sendable {
    func orderedPreviewCandidates(in entries: [ThreeMFPackageEntry]) -> [ThreeMFPackageEntry]
}

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

    private func rank(for path: String) -> Int? {
        let normalizedPath = path.lowercased()
        guard isSupportedImagePath(normalizedPath) else {
            return nil
        }

        var rank = 1_000

        if normalizedPath == "auxiliaries/.thumbnails/thumbnail_middle.png" {
            return 0
        }

        if normalizedPath == "auxiliaries/.thumbnails/thumbnail_3mf.png" {
            return 10
        }

        if normalizedPath == "auxiliaries/.thumbnails/thumbnail_small.png" {
            return 20
        }

        if normalizedPath.hasPrefix("auxiliaries/.thumbnails/") {
            rank -= 800
        }

        if normalizedPath.hasPrefix("metadata/") {
            rank -= 200
        }

        if normalizedPath.hasPrefix("metadata/top_") {
            rank -= 320
        }

        if normalizedPath.hasPrefix("metadata/pick_") {
            rank -= 300
        }

        if normalizedPath.contains("top_cover") || normalizedPath.contains("cover") {
            rank -= 250
        }

        if normalizedPath.contains("preview") {
            rank -= 150
        }

        if normalizedPath.contains("thumbnail") || normalizedPath.contains("thumb") {
            rank -= 100
        }

        if normalizedPath.hasPrefix("metadata/plate_") {
            rank += 200
        }

        if normalizedPath.contains("plate_no_light") {
            rank += 250
        }

        if normalizedPath.contains("_small") || normalizedPath.contains("small_") {
            rank += 50
        }

        if normalizedPath.hasSuffix(".png") {
            rank -= 20
        }

        return rank
    }

    private func isSupportedImagePath(_ path: String) -> Bool {
        path.hasSuffix(".png") || path.hasSuffix(".jpg") || path.hasSuffix(".jpeg")
    }

    private struct RankedEntry {
        let entry: ThreeMFPackageEntry
        let rank: Int
    }
}
