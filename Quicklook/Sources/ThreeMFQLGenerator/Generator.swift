import CoreGraphics
import Foundation
import ImageIO
import os
import QuickLook
import UniformTypeIdentifiers

private let extractor = ThreeMFPreviewExtractor()
private let logger = Logger(subsystem: "com.printfilemanager.ThreeMFQuickLook", category: "QLGenerator")

@_cdecl("GeneratePreviewForURL")
public func GeneratePreviewForURL(
    _ thisInterface: UnsafeMutableRawPointer?,
    _ preview: QLPreviewRequest?,
    _ url: CFURL?,
    _ contentTypeUTI: CFString?,
    _ options: CFDictionary?
) -> OSStatus {
    guard let preview, let url else {
        return noErr
    }

    if QLPreviewRequestIsCancelled(preview) {
        return noErr
    }

    let fileURL = url as URL
    logger.info("Legacy preview request started file=\(fileURL.path, privacy: .public)")

    switch extractor.preview(for: fileURL, maxPixelDimension: 1_600) {
    case .preview(let image):
        let properties: [CFString: Any] = [
            kQLPreviewPropertyWidthKey: image.pixelSize.width,
            kQLPreviewPropertyHeightKey: image.pixelSize.height
        ]
        QLPreviewRequestSetDataRepresentation(
            preview,
            image.data as CFData,
            UTType.png.identifier as CFString,
            properties as CFDictionary
        )
        logger.info("Legacy preview generated file=\(fileURL.lastPathComponent, privacy: .public) bytes=\(image.data.count)")

    case .fallback(let fallback):
        let html = fallbackHTML(for: fallback)
        QLPreviewRequestSetDataRepresentation(
            preview,
            html as CFData,
            UTType.html.identifier as CFString,
            [kQLPreviewPropertyTextEncodingNameKey: "UTF-8"] as CFDictionary
        )
        logger.error("Legacy preview fallback file=\(fileURL.path, privacy: .public)")
    }

    return noErr
}

@_cdecl("CancelPreviewGeneration")
public func CancelPreviewGeneration(_ thisInterface: UnsafeMutableRawPointer?, _ preview: QLPreviewRequest?) {}

@_cdecl("GenerateThumbnailForURL")
public func GenerateThumbnailForURL(
    _ thisInterface: UnsafeMutableRawPointer?,
    _ thumbnail: QLThumbnailRequest?,
    _ url: CFURL?,
    _ contentTypeUTI: CFString?,
    _ options: CFDictionary?,
    _ maxSize: CGSize
) -> OSStatus {
    guard let thumbnail, let url else {
        return noErr
    }

    if QLThumbnailRequestIsCancelled(thumbnail) {
        return noErr
    }

    let fileURL = url as URL
    let maxPixelDimension = max(1, Int(max(maxSize.width, maxSize.height)))
    logger.info("Legacy thumbnail request started file=\(fileURL.path, privacy: .public) maxPixelDimension=\(maxPixelDimension)")

    guard case .preview(let image) = extractor.preview(for: fileURL, maxPixelDimension: maxPixelDimension),
          let source = CGImageSourceCreateWithData(image.data as CFData, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        logger.error("Legacy thumbnail extraction failed file=\(fileURL.path, privacy: .public)")
        return noErr
    }

    QLThumbnailRequestSetImage(thumbnail, cgImage, nil)
    logger.info("Legacy thumbnail generated file=\(fileURL.lastPathComponent, privacy: .public) bytes=\(image.data.count)")
    return noErr
}

@_cdecl("CancelThumbnailGeneration")
public func CancelThumbnailGeneration(_ thisInterface: UnsafeMutableRawPointer?, _ thumbnail: QLThumbnailRequest?) {}

private func fallbackHTML(for fallback: PreviewFallback) -> Data {
    let escapedFileName = fallback.fileName
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")

    let html = """
    <!doctype html>
    <html>
    <head><meta charset=\"utf-8\"><style>body{font:13px -apple-system;color:#1d1d1f;background:#f5f5f7;display:grid;place-items:center;height:100vh;margin:0}main{text-align:center;max-width:420px;padding:32px}</style></head>
    <body><main><h1>\(escapedFileName)</h1><p>No embedded 3MF preview image was found.</p></main></body>
    </html>
    """
    return Data(html.utf8)
}