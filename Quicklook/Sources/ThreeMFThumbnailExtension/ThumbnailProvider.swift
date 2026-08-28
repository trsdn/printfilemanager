import CoreGraphics
import Foundation
import ImageIO
import os
import QuickLookThumbnailing
import ThreeMFKit

final class ThumbnailProvider: QLThumbnailProvider {
    private let extractor = ThreeMFPreviewExtractor()
    private let logger = Logger(subsystem: "com.printfilemanager.ThreeMFQuickLook", category: "ThumbnailProvider")

    override func provideThumbnail(
        for request: QLFileThumbnailRequest,
        _ handler: @escaping (QLThumbnailReply?, Error?) -> Void
    ) {
        let hasSecurityScopedAccess = request.fileURL.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScopedAccess {
                request.fileURL.stopAccessingSecurityScopedResource()
            }
        }

        let maxPixelDimension = Int(max(request.maximumSize.width, request.maximumSize.height) * request.scale)
        logger.info("Thumbnail request started file=\(request.fileURL.path, privacy: .private) maxPixelDimension=\(maxPixelDimension) securityScoped=\(hasSecurityScopedAccess)")

        switch extractor.preview(for: request.fileURL, maxPixelDimension: maxPixelDimension) {
        case .preview(let image):
            logger.info("Thumbnail preview extracted file=\(request.fileURL.lastPathComponent, privacy: .private) bytes=\(image.data.count) width=\(image.pixelSize.width) height=\(image.pixelSize.height)")
            let reply = QLThumbnailReply(contextSize: request.maximumSize) { context in
                Self.draw(image: image, in: context, canvasSize: request.maximumSize)
            }
            handler(reply, nil)

        case .fallback:
            logger.error("Thumbnail extraction fell back file=\(request.fileURL.path, privacy: .private)")
            handler(nil, nil)
        }
    }

    private static func draw(image: PreviewImage, in context: CGContext, canvasSize: CGSize) -> Bool {
        guard let source = CGImageSourceCreateWithData(image.data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return false
        }

        context.interpolationQuality = .high
        context.draw(cgImage, in: aspectFitRect(imageSize: image.pixelSize, in: canvasSize))
        return true
    }

    private static func aspectFitRect(imageSize: CGSize, in canvasSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, canvasSize.width > 0, canvasSize.height > 0 else {
            return CGRect(origin: .zero, size: canvasSize)
        }

        let scale = min(canvasSize.width / imageSize.width, canvasSize.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        let x = (canvasSize.width - width) / 2
        let y = (canvasSize.height - height) / 2
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
