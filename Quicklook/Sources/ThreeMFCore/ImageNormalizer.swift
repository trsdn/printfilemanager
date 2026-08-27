import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public protocol ImageNormalizing: Sendable {
    func normalize(_ data: Data, maxPixelDimension: Int?) -> PreviewImage?
}

public struct CGImagePreviewImageNormalizer: ImageNormalizing {
    public init() {}

    public func normalize(_ data: Data, maxPixelDimension: Int?) -> PreviewImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        let targetSize = Self.targetSize(for: image, maxPixelDimension: maxPixelDimension)
        guard let renderedImage = Self.render(image, at: targetSize) else {
            return nil
        }

        let normalizedData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            normalizedData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        CGImageDestinationAddImage(destination, renderedImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        return PreviewImage(
            data: normalizedData as Data,
            contentTypeIdentifier: UTType.png.identifier,
            pixelSize: CGSize(width: targetSize.width, height: targetSize.height)
        )
    }

    private static func targetSize(for image: CGImage, maxPixelDimension: Int?) -> PixelSize {
        let width = image.width
        let height = image.height

        guard let maxPixelDimension, max(width, height) > maxPixelDimension else {
            return PixelSize(width: width, height: height)
        }

        let scale = Double(maxPixelDimension) / Double(max(width, height))
        return PixelSize(
            width: max(1, Int((Double(width) * scale).rounded())),
            height: max(1, Int((Double(height) * scale).rounded()))
        )
    }

    private static func render(_ image: CGImage, at size: PixelSize) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: nil,
            width: size.width,
            height: size.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        return context.makeImage()
    }

    private struct PixelSize {
        let width: Int
        let height: Int
    }
}
