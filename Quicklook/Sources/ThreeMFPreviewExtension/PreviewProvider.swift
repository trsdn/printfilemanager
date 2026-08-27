import CoreGraphics
import Foundation
import os
import Quartz
import ThreeMFCore
import UniformTypeIdentifiers

final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    private let extractor = ThreeMFPreviewExtractor()
  private let logger = Logger(subsystem: "com.printfilemanager.ThreeMFQuickLook", category: "PreviewProvider")

    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
      let hasSecurityScopedAccess = request.fileURL.startAccessingSecurityScopedResource()
      defer {
        if hasSecurityScopedAccess {
          request.fileURL.stopAccessingSecurityScopedResource()
        }
      }

      logger.info("Preview request started file=\(request.fileURL.path, privacy: .public) securityScoped=\(hasSecurityScopedAccess)")

        switch extractor.preview(for: request.fileURL, maxPixelDimension: 1_600) {
        case .preview(let image):
        logger.info("Preview extracted file=\(request.fileURL.lastPathComponent, privacy: .public) bytes=\(image.data.count) width=\(image.pixelSize.width) height=\(image.pixelSize.height)")
            let contentType = UTType(image.contentTypeIdentifier) ?? .png
            return QLPreviewReply(dataOfContentType: contentType, contentSize: image.pixelSize) { _ in
                image.data
            }

        case .fallback(let fallback):
        logger.error("Preview extraction fell back file=\(request.fileURL.path, privacy: .public)")
            return QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 640, height: 420)) { reply in
                reply.stringEncoding = .utf8
                return Self.fallbackHTML(for: fallback)
            }
        }
    }

    private static func fallbackHTML(for fallback: PreviewFallback) -> Data {
        let escapedFileName = fallback.fileName
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        let html = """
        <!doctype html>
        <html>
        <head>
          <meta charset=\"utf-8\">
          <style>
            body {
              margin: 0;
              height: 100vh;
              display: grid;
              place-items: center;
              font: -apple-system-body;
              color: #1d1d1f;
              background: #f5f5f7;
            }
            main {
              text-align: center;
              max-width: 420px;
              padding: 32px;
            }
            .icon {
              width: 84px;
              height: 108px;
              margin: 0 auto 20px;
              border-radius: 12px;
              background: linear-gradient(#ffffff, #e8e8ed);
              border: 1px solid #d2d2d7;
              box-shadow: 0 10px 30px rgba(0,0,0,0.08);
            }
            h1 {
              margin: 0 0 8px;
              font-size: 18px;
              font-weight: 600;
            }
            p {
              margin: 0;
              color: #6e6e73;
              font-size: 13px;
            }
          </style>
        </head>
        <body>
          <main>
            <div class=\"icon\" aria-hidden=\"true\"></div>
            <h1>\(escapedFileName)</h1>
            <p>No embedded 3MF preview image was found.</p>
          </main>
        </body>
        </html>
        """

        return Data(html.utf8)
    }
}
