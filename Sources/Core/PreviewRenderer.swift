import AppKit
import Metal
import SceneKit
import simd

/// Preview da mesa: fundo #E8E6E1, mesa clara com contorno escuro, vista isométrica.
/// Uma mesa → enquadra a mesa; várias → vista panorâmica de todas.
public enum PreviewRenderer {
    /// Cena pronta para render ou para um `SCNView` interativo; `target` é o centro do enquadramento.
    public struct Prepared {
        public let scene: SCNScene
        public let camera: SCNNode
        public let target: SIMD3<Float>
    }

    static let background = NSColor(hex: "#E8E6E1")
    static let bedColour = NSColor(hex: "#F7F6F3")
    static let gridColour = NSColor(hex: "#D3CFC6")
    static let inkColour = NSColor(hex: "#17191C")
    /// Normal flat por face a partir das derivadas da posição: malha indexada sem duplicar vértices.
    static let flatNormal = """
    float3 n = normalize(cross(dfdx(_surface.position), dfdy(_surface.position)));
    _surface.normal = n.z < 0 ? -n : n;
    """

    public static func png(url: URL, info: ThreeMFInfo, size: CGSize = CGSize(width: 1024, height: 1024)) throws -> Data {
        let image = try render(url: url, info: info, size: size)
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw RenderError.encode
        }
        return png
    }

    public static func render(url: URL, info: ThreeMFInfo, size: CGSize) throws -> CGImage {
        let prepared = try prepare(url: url, info: info, aspect: Float(size.width / size.height))
        guard let device = MTLCreateSystemDefaultDevice() else { throw RenderError.noMetal }
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = prepared.scene
        renderer.pointOfView = prepared.camera
        let shot = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
        return try overlay(shot, size: size, info: info)
    }

    public static func prepare(url: URL, info: ThreeMFInfo, aspect: Float) throws -> Prepared {
        let scene = try PrintScene.load(url: url, info: info)
        let (root, bounds) = build(scene)
        let scn = SCNScene()
        scn.background.contents = background
        scn.rootNode.addChildNode(root)

        let forward = simd_normalize(SIMD3<Float>(0.55, 1.0, -0.85))
        let up = SIMD3<Float>(0, 0, 1)
        let right = simd_normalize(simd_cross(forward, up))
        let camUp = simd_cross(right, forward)
        var lo = SIMD2<Float>(repeating: .greatestFiniteMagnitude), hi = -lo
        for x in [bounds.min.x, bounds.max.x] { for y in [bounds.min.y, bounds.max.y] { for z in [bounds.min.z, bounds.max.z] {
            let p = SIMD3(x, y, z)
            let q = SIMD2(simd_dot(p, right), simd_dot(p, camUp))
            lo = simd_min(lo, q); hi = simd_max(hi, q)
        } } }
        let mid = (lo + hi) / 2
        let half = (hi - lo) / 2
        let centre = right * mid.x + camUp * mid.y + forward * simd_dot((bounds.min + bounds.max) / 2, forward)

        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.orthographicScale = Double(max(half.y, half.x / aspect) * 1.12)
        camera.zNear = 1
        camera.zFar = 100_000
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.simdPosition = centre - forward * 20_000
        cameraNode.simdLook(at: centre, up: up, localFront: SIMD3(0, 0, -1))
        scn.rootNode.addChildNode(cameraNode)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light!.type = .ambient
        ambient.light!.intensity = 520
        scn.rootNode.addChildNode(ambient)
        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light!.type = .directional
        sun.light!.intensity = 650
        sun.simdLook(at: SIMD3(0.6, 1.0, -1.6), up: up, localFront: SIMD3(0, 0, -1))
        scn.rootNode.addChildNode(sun)
        return Prepared(scene: scn, camera: cameraNode, target: centre)
    }

    // MARK: cena

    static func build(_ scene: PrintScene) -> (SCNNode, (min: SIMD3<Float>, max: SIMD3<Float>)) {
        let root = SCNNode()
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude), hi = -lo
        for bed in scene.beds {
            let a = SIMD2<Float>(Float(bed.min.x), Float(bed.min.y)), b = SIMD2<Float>(Float(bed.max.x), Float(bed.max.y))
            root.addChildNode(bedNode(a, b, label: scene.beds.count > 1 ? "\(bed.index)" : nil))
            lo = simd_min(lo, SIMD3(a, -2)); hi = simd_max(hi, SIMD3(b, 0))
        }
        if scene.boundsMin.x <= scene.boundsMax.x {
            lo = simd_min(lo, scene.boundsMin); hi = simd_max(hi, scene.boundsMax)
        }
        for (hex, mesh) in scene.meshes.sorted(by: { $0.key < $1.key }) where !mesh.indices.isEmpty {
            let geometry = SCNGeometry(
                sources: [source(mesh.positions, .vertex)],
                elements: [SCNGeometryElement(indices: mesh.indices, primitiveType: .triangles)])
            let material = SCNMaterial()
            material.diffuse.contents = NSColor(hex: hex)
            material.lightingModel = .lambert
            material.isDoubleSided = true
            material.shaderModifiers = [.surface: flatNormal]
            geometry.materials = [material]
            root.addChildNode(SCNNode(geometry: geometry))
        }
        return (root, (lo, hi))
    }

    static func bedNode(_ a: SIMD2<Float>, _ b: SIMD2<Float>, label: String?) -> SCNNode {
        let node = SCNNode()
        let size = b - a
        let slab = SCNBox(width: CGFloat(size.x), height: CGFloat(size.y), length: 2, chamferRadius: 0)
        let m = SCNMaterial()
        m.diffuse.contents = bedColour
        m.lightingModel = .constant
        slab.materials = [m]
        let slabNode = SCNNode(geometry: slab)
        slabNode.simdPosition = SIMD3((a + b) / 2, -1.02)
        node.addChildNode(slabNode)

        var grid: [SIMD3<Float>] = []
        let step: Float = 25
        var x = a.x + step
        while x < b.x - 0.1 { grid += [SIMD3(x, a.y, 0.02), SIMD3(x, b.y, 0.02)]; x += step }
        var y = a.y + step
        while y < b.y - 0.1 { grid += [SIMD3(a.x, y, 0.02), SIMD3(b.x, y, 0.02)]; y += step }
        node.addChildNode(lines(grid, gridColour))
        let corners = [SIMD3(a.x, a.y, 0.04), SIMD3(b.x, a.y, 0.04), SIMD3(b.x, b.y, 0.04), SIMD3(a.x, b.y, 0.04)]
        node.addChildNode(lines(zip(corners, corners.dropFirst() + [corners[0]]).flatMap { [$0, $1] }, inkColour))

        if let label {
            let text = SCNText(string: label, extrusionDepth: 0)
            text.font = NSFont.systemFont(ofSize: CGFloat(size.x * 0.09), weight: .bold)
            text.flatness = 0.4
            let tm = SCNMaterial()
            tm.diffuse.contents = gridColour.blended(withFraction: 0.5, of: inkColour)
            tm.lightingModel = .constant
            text.materials = [tm]
            let textNode = SCNNode(geometry: text)
            textNode.simdPosition = SIMD3(a.x + size.x * 0.04, a.y + size.y * 0.04, 0.06)
            node.addChildNode(textNode)
        }
        return node
    }

    static func lines(_ points: [SIMD3<Float>], _ colour: NSColor) -> SCNNode {
        let geometry = SCNGeometry(
            sources: [source(points, .vertex)],
            elements: [SCNGeometryElement(indices: Array(0..<UInt32(points.count)), primitiveType: .line)])
        let m = SCNMaterial()
        m.diffuse.contents = colour
        m.lightingModel = .constant
        geometry.materials = [m]
        return SCNNode(geometry: geometry)
    }

    static func source(_ v: [SIMD3<Float>], _ semantic: SCNGeometrySource.Semantic) -> SCNGeometrySource {
        let data = v.withUnsafeBufferPointer { Data(buffer: $0) }
        return SCNGeometrySource(data: data, semantic: semantic, vectorCount: v.count, usesFloatComponents: true,
                                 componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0,
                                 dataStride: MemoryLayout<SIMD3<Float>>.stride)
    }

    // MARK: legenda

    static func overlay(_ image: NSImage, size: CGSize, info: ThreeMFInfo) throws -> CGImage {
        let w = Int(size.width), h = Int(size.height)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw RenderError.encode }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        let pad = CGFloat(h) * 0.045
        let title = info.printerModel ?? L10n.noPrinter
        let plates = L10n.plates(info.plateCount)
        NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: CGFloat(h) * 0.045, weight: .semibold),
            .foregroundColor: inkColour,
        ]).draw(at: CGPoint(x: pad, y: CGFloat(h) - pad - CGFloat(h) * 0.055))
        NSAttributedString(string: [plates, info.printSettingsID].compactMap { $0 }.joined(separator: " · "), attributes: [
            .font: NSFont.systemFont(ofSize: CGFloat(h) * 0.026, weight: .regular),
            .foregroundColor: inkColour.withAlphaComponent(0.62),
        ]).draw(at: CGPoint(x: pad, y: CGFloat(h) - pad - CGFloat(h) * 0.095))
        NSGraphicsContext.restoreGraphicsState()
        guard let out = ctx.makeImage() else { throw RenderError.encode }
        return out
    }
}

public enum RenderError: Error { case noMetal, encode }

extension NSColor {
    convenience init(hex: String) {
        var v: UInt64 = 0
        Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).scanHexInt64(&v)
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}
