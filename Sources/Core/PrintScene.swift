import Foundation
import simd

/// Malha em coordenadas de mundo, agrupada por cor do filamento.
public struct PrintScene {
    public struct Bed {
        public let index: Int
        public let min: SIMD2<Double>
        public let max: SIMD2<Double>
    }

    /// Malha indexada (vértices já em coordenadas de mundo).
    public struct Buffer {
        public var positions: [SIMD3<Float>] = []
        public var indices: [UInt32] = []
    }

    public var beds: [Bed] = []
    /// cor "#RRGGBB" → malha em mm.
    public var meshes: [String: Buffer] = [:]
    public var boundsMin = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
    public var boundsMax = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)

    public var triangleCount: Int { meshes.values.reduce(0) { $0 + $1.indices.count / 3 } }

    /// Layout das mesas do Bambu Studio/Orca: grade com ceil(√n) colunas, passo de 1,2× a mesa,
    /// linhas crescendo para −Y. Conferido num projeto real de H2C com 4 mesas.
    public static func bedLayout(count: Int, min: SIMD2<Double>, max: SIMD2<Double>) -> [Bed] {
        let cols = Int(ceil(sqrt(Double(count))))
        let size = max - min
        return (0..<count).map { i in
            let o = SIMD2(Double(i % cols) * size.x * 1.2, -Double(i / cols) * size.y * 1.2)
            return Bed(index: i + 1, min: min + o, max: max + o)
        }
    }

    public static func load(url: URL, info: ThreeMFInfo) throws -> PrintScene {
        let zip = try ZipArchive(url: url)
        var scene = PrintScene()
        scene.beds = bedLayout(count: info.plateCount, min: info.bedMin, max: info.bedMax)

        let settings = (try? zip.read("Metadata/model_settings.config")).map(ModelSettings.init) ?? ModelSettings()
        var models: [String: ModelFile] = [:]
        func model(_ path: String) -> ModelFile? {
            if let m = models[path] { return m }
            guard let data = try? zip.read(path) else { return nil }
            let m = ModelFile(data: data)
            models[path] = m
            return m
        }
        let root = "3D/3dmodel.model"
        guard let main = model(root) else { throw ZipError.missing(root) }

        func colour(_ extruder: Int) -> String {
            let list = info.filamentColours
            guard !list.isEmpty else { return "#B8B4AC" }
            let c = list[Swift.max(0, Swift.min(list.count - 1, extruder - 1))]
            return c.count >= 7 ? String(c.prefix(7)).uppercased() : "#B8B4AC"
        }

        func emit(path: String, id: String, transform: simd_float4x4, extruder: Int, top: String, depth: Int) {
            guard depth < 16, let file = model(path), let object = file.objects[id] else { return }
            if let mesh = object.mesh, !mesh.triangles.isEmpty {
                let key = colour(extruder)
                let base = UInt32(scene.meshes[key]?.positions.count ?? 0)
                for v in mesh.vertices {
                    let p4 = transform * SIMD4(v, 1)
                    let p = SIMD3(p4.x, p4.y, p4.z)
                    scene.boundsMin = simd_min(scene.boundsMin, p)
                    scene.boundsMax = simd_max(scene.boundsMax, p)
                    scene.meshes[key, default: Buffer()].positions.append(p)
                }
                scene.meshes[key, default: Buffer()].indices.append(contentsOf: mesh.triangles.lazy.map { $0 + base })
            }
            for c in object.components {
                let part = settings.parts[top]?[c.objectID]
                if let subtype = part?.subtype, subtype != "normal_part" { continue }
                emit(path: c.path.map(ModelFile.normalize) ?? path, id: c.objectID,
                     transform: transform * c.transform, extruder: part?.extruder ?? extruder,
                     top: top, depth: depth + 1)
            }
        }
        for item in main.build {
            emit(path: root, id: item.objectID, transform: item.transform,
                 extruder: settings.objectExtruder[item.objectID] ?? 1, top: item.objectID, depth: 0)
        }
        return scene
    }
}

/// `Metadata/model_settings.config` do Bambu/Orca: extrusora por objeto e por peça.
struct ModelSettings {
    struct Part { var extruder: Int?; var subtype: String? }
    var objectExtruder: [String: Int] = [:]
    var parts: [String: [String: Part]] = [:]

    init() {}

    init(data: Data) {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        objectExtruder = delegate.objectExtruder
        parts = delegate.parts
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var objectExtruder: [String: Int] = [:]
        var parts: [String: [String: Part]] = [:]
        var object: String?
        var part: String?
        var inPlate = false

        func parser(_ p: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes a: [String: String]) {
            switch name {
            case "plate": inPlate = true
            case "object" where !inPlate: object = a["id"]
            case "part": part = a["id"]
                if let o = object, let id = part { parts[o, default: [:]][id] = Part(subtype: a["subtype"]) }
            case "metadata" where a["key"] == "extruder":
                guard let o = object, let e = a["value"].flatMap(Int.init) else { return }
                if let id = part { parts[o]?[id]?.extruder = e } else { objectExtruder[o] = e }
            default: break
            }
        }

        func parser(_ p: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            switch name {
            case "plate": inPlate = false
            case "part": part = nil
            case "object": object = nil
            default: break
            }
        }
    }
}

/// Um arquivo `.model` do 3MF: objetos (malha ou componentes) e build items.
final class ModelFile: NSObject, XMLParserDelegate {
    struct Mesh { var vertices: [SIMD3<Float>] = []; var triangles: [UInt32] = [] }
    struct Component { let objectID: String; let path: String?; let transform: simd_float4x4 }
    struct Object { var mesh: Mesh?; var components: [Component] = [] }
    struct Item { let objectID: String; let transform: simd_float4x4 }

    private(set) var objects: [String: Object] = [:]
    private(set) var build: [Item] = []
    private var current: String?
    private var mesh: Mesh?

    init(data: Data) {
        super.init()
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
    }

    static func normalize(_ path: String) -> String {
        path.hasPrefix("/") ? String(path.dropFirst()) : path
    }

    /// "m00 m01 m02 m10 m11 m12 m20 m21 m22 m30 m31 m32" (vetor-linha) → matriz coluna.
    static func transform(_ s: String?) -> simd_float4x4 {
        guard let s else { return matrix_identity_float4x4 }
        let m = s.split(separator: " ").compactMap { Float($0) }
        guard m.count == 12 else { return matrix_identity_float4x4 }
        return simd_float4x4(columns: (
            SIMD4(m[0], m[1], m[2], 0), SIMD4(m[3], m[4], m[5], 0),
            SIMD4(m[6], m[7], m[8], 0), SIMD4(m[9], m[10], m[11], 1)))
    }

    func parser(_ p: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes a: [String: String]) {
        switch name {
        case "vertex":
            mesh?.vertices.append(SIMD3(Float(a["x"] ?? "") ?? 0, Float(a["y"] ?? "") ?? 0, Float(a["z"] ?? "") ?? 0))
        case "triangle":
            if let v1 = a["v1"].flatMap(UInt32.init), let v2 = a["v2"].flatMap(UInt32.init),
               let v3 = a["v3"].flatMap(UInt32.init) {
                mesh?.triangles.append(v1)
                mesh?.triangles.append(v2)
                mesh?.triangles.append(v3)
            }
        case "object": current = a["id"]; objects[a["id"] ?? ""] = Object()
        case "mesh": mesh = Mesh()
        case "component":
            guard let id = current, let ref = a["objectid"] else { return }
            let path = a.first(where: { $0.key.hasSuffix(":path") || $0.key == "path" })?.value
            objects[id]?.components.append(Component(objectID: ref, path: path, transform: Self.transform(a["transform"])))
        case "item":
            if let ref = a["objectid"], a["printable"] != "0" {
                build.append(Item(objectID: ref, transform: Self.transform(a["transform"])))
            }
        default: break
        }
    }

    func parser(_ p: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "mesh", let id = current, let m = mesh {
            let n = m.vertices.count
            let tris = m.triangles.allSatisfy { Int($0) < n } ? m.triangles : []
            objects[id]?.mesh = Mesh(vertices: m.vertices, triangles: tris)
            mesh = nil
        } else if name == "object" {
            current = nil
        }
    }
}
