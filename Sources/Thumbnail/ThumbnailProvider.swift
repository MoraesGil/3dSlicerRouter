import AppKit
import QuickLookThumbnailing

/// Thumbnail do Finder para .3mf e .gcode.
/// - .3mf pequeno (lista, < 64 pt): ícone do fatiador em que o arquivo vai abrir.
/// - Médio/grande: imagem embutida pelo fatiador; sem ela, o preview do indexador (cache) ou um render na hora.
final class ThumbnailProvider: QLThumbnailProvider {
    static let iconThreshold: CGFloat = 64

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
                if max(box.width, box.height) < Self.iconThreshold, let icon = slicerIcon(url: url, info: info) {
                    handler(QLThumbnailReply(contextSize: box) { () -> Bool in
                        icon.draw(in: NSRect(origin: .zero, size: box))
                        return true
                    }, nil)
                    return
                }
                if let embedded = info.embeddedThumbnail.flatMap({ try? zip.read($0) }).flatMap(Self.decode) {
                    image = embedded
                } else if let cached = Self.cached(url) {
                    image = cached
                } else {
                    image = try PreviewRenderer.render(url: url, info: info, size: CGSize(width: side, height: side))
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

    static func decode(_ data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    static func cached(_ url: URL) -> CGImage? {
        PreviewCache.cachedURL(for: url).flatMap { try? Data(contentsOf: $0) }.flatMap(decode)
    }

    /// Mesma regra do roteamento: memória do xattr enquanto a impressora não mudar; senão, a impressora nova.
    func slicerIcon(url: URL, info: ThreeMFInfo) -> NSImage? {
        guard let app = Router.expectedApp(info: info, record: FileRecord.read(from: url), mappings: Mappings()) else { return nil }
        let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID)?.path ?? app.path
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return NSWorkspace.shared.icon(forFile: path)
    }
}
