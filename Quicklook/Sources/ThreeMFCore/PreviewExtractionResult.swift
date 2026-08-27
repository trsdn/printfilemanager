import CoreGraphics
import Foundation

public enum PreviewFallbackReason: String, Equatable, Sendable {
    case unreadablePackage
    case noSupportedImage
    case imageNormalizationFailed
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
