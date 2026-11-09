import AppKit
import QuickLookThumbnailing

/// Thumbnail do Finder para .3mf e .gcode.
/// - .3mf: primeira chapa em todos os tamanhos; cache atual antes da imagem embutida.
final class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(for request: QLFileThumbnailRequest, _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        let url = request.fileURL
        let box = request.maximumSize
        let side = max(256, max(box.width, box.height) * request.scale)
        do {
            let image: CGImage
            if url.pathExtension.lowercased() == "gcode" {
                let meta = try GCode.metadata(url: url)
                if let embedded = meta.thumbnail.flatMap(Self.decode) {
                    image = embedded
                } else if let cached = Self.cached(url) {
                    image = cached
                } else {
                    image = try PreviewRenderer.renderGCode(url: url, info: meta.info, size: CGSize(width: side, height: side))
                }
            } else {
                let zip = try ZipArchive(url: url)
                let info = try ThreeMF.info(zip: zip)
                image = try PreviewRenderer.thumbnail(url: url, info: info, size: CGSize(width: side, height: side))
            }
            let ratio = min(box.width / CGFloat(image.width), box.height / CGFloat(image.height))
            let size = CGSize(width: CGFloat(image.width) * ratio, height: CGFloat(image.height) * ratio)
            // currentContextDrawing já vem escalado para @2x; o CGContext cru não.
            let picture = NSImage(cgImage: image, size: size)
            handler(QLThumbnailReply(contextSize: size) { () -> Bool in
                picture.draw(in: NSRect(origin: .zero, size: size))
                return true
            }, nil)
        } catch {
            handler(nil, error)
        }
    }

    static func decode(_ data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    static func cached(_ url: URL) -> CGImage? {
        PreviewCache.cachedURL(for: url).flatMap { try? Data(contentsOf: $0) }.flatMap(decode)
    }

}
