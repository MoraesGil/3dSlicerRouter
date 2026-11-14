import AppKit
import QuickLookThumbnailing

/// Thumbnail do Finder para .3mf e .gcode.
/// - Small requests: the whole Router logo uses the destination slicer's colour.
/// - Larger requests: current model/toolpath preview, preserving geometry and painting.
final class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(for request: QLFileThumbnailRequest, _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        DispatchQueue.global(qos: .background).async {
            self.reply(to: request, handler)
        }
    }

    private func reply(to request: QLFileThumbnailRequest, _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        let url = request.fileURL
        let box = request.maximumSize
        let side = max(256, max(box.width, box.height) * request.scale)
        do {
            if RouterFileIcon.usesBrandIcon(maximumSize: box) {
                let document = try? RoutableDocument.read(url: url)
                let preferences = RoutingPreferences.read(for: url)
                let app = document?.expectedApp(record: preferences.record, mappings: preferences.mappings)
                let picture = RouterFileIcon.image(for: app)
                let reply = QLThumbnailReply(contextSize: box) { () -> Bool in
                    picture.draw(in: NSRect(origin: .zero, size: box))
                    return true
                }
                reply.extensionBadge = ""
                handler(reply, nil)
                return
            }
            let image: CGImage
            if url.pathExtension.lowercased() == "gcode" {
                let meta = try GCode.metadata(url: url)
                if let embedded = meta.thumbnail.flatMap(PreviewRenderer.decode) {
                    image = embedded
                } else if let cached = PreviewRenderer.cachedImage(url) {
                    image = cached
                } else {
                    image = try PreviewGate.run(for: url) { check in
                        try PreviewRenderer.renderGCode(url: url, info: meta.info, size: CGSize(width: side, height: side), checkpoint: check)
                    }
                }
            } else {
                let zip = try ZipArchive(url: url)
                let info = try ThreeMF.info(zip: zip)
                if let cached = PreviewRenderer.cachedImage(url) {
                    image = cached
                } else {
                    do {
                        image = try PreviewGate.run(for: url) { check in
                            try PreviewRenderer.thumbnail(url: url, info: info, size: CGSize(width: side, height: side), checkpoint: check)
                        }
                    } catch is PreviewGate.Busy {
                        guard let fallback = info.embeddedThumbnail.flatMap({ try? zip.read($0) }).flatMap(PreviewRenderer.decode) else {
                            throw PreviewGate.Busy()
                        }
                        image = fallback
                    }
                }
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
}
