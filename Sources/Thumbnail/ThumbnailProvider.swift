import AppKit
import QuickLookThumbnailing

/// Thumbnail do Finder para .3mf.
/// - Pequeno (lista, < 64 pt): ícone do fatiador em que o arquivo vai abrir.
/// - Médio/grande: imagem embutida pelo fatiador; sem ela, a mesa isométrica renderizada.
final class ThumbnailProvider: QLThumbnailProvider {
    static let iconThreshold: CGFloat = 64

    override func provideThumbnail(for request: QLFileThumbnailRequest, _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        let url = request.fileURL
        let box = request.maximumSize
        do {
            let zip = try ZipArchive(url: url)
            let info = try ThreeMF.info(zip: zip)
            if max(box.width, box.height) < Self.iconThreshold, let icon = slicerIcon(url: url, info: info) {
                handler(QLThumbnailReply(contextSize: box) { () -> Bool in
                    icon.draw(in: NSRect(origin: .zero, size: box))
                    return true
                }, nil)
                return
            }
            let image: CGImage
            if let path = info.embeddedThumbnail, let png = try? zip.read(path),
               let src = CGImageSourceCreateWithData(png as CFData, nil),
               let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) {
                image = cg
            } else {
                let side = max(256, max(box.width, box.height) * request.scale)
                image = try PreviewRenderer.render(url: url, info: info, size: CGSize(width: side, height: side))
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

    /// Mesma regra do roteamento: memória do xattr enquanto a impressora não mudar; senão, a impressora nova.
    func slicerIcon(url: URL, info: ThreeMFInfo) -> NSImage? {
        guard let app = Router.expectedApp(info: info, record: FileRecord.read(from: url), mappings: Mappings()) else { return nil }
        let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID)?.path ?? app.path
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return NSWorkspace.shared.icon(forFile: path)
    }
}
