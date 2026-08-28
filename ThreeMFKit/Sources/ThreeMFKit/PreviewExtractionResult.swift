import CoreGraphics
import Foundation

public enum PreviewFallbackReason: String, Equatable, Sendable {
    case unreadablePackage
    case noSupportedImage
    case imageNormalizationFailed

    /// The archive opened but is not a 3MF package. Because the extensions also register for
    /// `public.zip-archive` (so they still fire when a slicer owns the `.3mf` type), ordinary
    /// zip files reach them and must be handed back to the system rather than previewed.
    case notAThreeMFPackage
}

public struct PreviewFallback: Equatable, Sendable {
    public let reason: PreviewFallbackReason
    public let fileName: String

    public init(reason: PreviewFallbackReason, fileName: String) {
        self.reason = reason
        self.fileName = fileName
    }
}

public struct PreviewImage: Equatable, Sendable {
    public let data: Data
    public let contentTypeIdentifier: String
    public let pixelSize: CGSize

    public init(data: Data, contentTypeIdentifier: String, pixelSize: CGSize) {
        self.data = data
        self.contentTypeIdentifier = contentTypeIdentifier
        self.pixelSize = pixelSize
    }
}

public enum PreviewExtractionResult: Equatable, Sendable {
    case preview(PreviewImage)
    case fallback(PreviewFallback)
}
