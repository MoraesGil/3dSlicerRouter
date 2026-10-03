import Cocoa
import QuickLookUI
import SceneKit

/// Quick Look (espaço / painel de preview do Finder) para .3mf.
/// Uma mesa → cena 3D que gira e dá zoom; várias mesas → screenshot panorâmico.
final class PreviewViewController: NSViewController, QLPreviewingController {
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        let aspect = Float(max(view.bounds.width, 1) / max(view.bounds.height, 1))
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let info = try ThreeMF.info(url: url)
                if info.plateCount > 1 {
                    let image = try PreviewRenderer.render(url: url, info: info, size: CGSize(width: 1600, height: 1600))
                    DispatchQueue.main.async { self.show(image: image); handler(nil) }
                } else {
                    let prepared = try PreviewRenderer.prepare(url: url, info: info, aspect: aspect)
                    DispatchQueue.main.async { self.show(prepared, info: info); handler(nil) }
                }
            } catch {
                DispatchQueue.main.async { handler(error) }
            }
        }
    }

    private func show(image: CGImage) {
        let imageView = NSImageView(frame: view.bounds)
        imageView.autoresizingMask = [.width, .height]
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.image = NSImage(cgImage: image, size: .zero)
        view.addSubview(imageView)
    }

    private func show(_ prepared: PreviewRenderer.Prepared, info: ThreeMFInfo) {
        let scnView = SCNView(frame: view.bounds)
        scnView.autoresizingMask = [.width, .height]
        scnView.scene = prepared.scene
        scnView.pointOfView = prepared.camera
        scnView.backgroundColor = PreviewRenderer.background
        scnView.antialiasingMode = .multisampling4X
        scnView.allowsCameraControl = true
        scnView.defaultCameraController.interactionMode = .orbitTurntable
        scnView.defaultCameraController.target = SCNVector3(prepared.target)
        scnView.defaultCameraController.worldUp = SCNVector3(0, 0, 1)
        view.addSubview(scnView)

        let title = NSTextField(labelWithString: info.printerModel ?? L10n.noPrinter)
        title.font = .systemFont(ofSize: 18, weight: .semibold)
        title.textColor = PreviewRenderer.inkColour
        title.frame = NSRect(x: 20, y: view.bounds.height - 40, width: view.bounds.width - 40, height: 24)
        title.autoresizingMask = [.width, .minYMargin]
        view.addSubview(title)
    }
}
