import CryptoKit
import Foundation
import simd

/// O que o router precisa saber de um 3MF para decidir o fatiador.
public struct ThreeMFInfo {
    public var printerModel: String?
    public var printerSettingsID: String?
    public var printSettingsID: String?
    public var application: String?
    /// Retângulo da mesa (mm) a partir de `printable_area`.
    public var bedMin = SIMD2<Double>(0, 0)
    public var bedMax = SIMD2<Double>(256, 256)
    public var filamentColours: [String] = []
    /// SHA-256 do `project_settings.config`; nil quando o arquivo não tem o config.
    public var settingsHash: String?
    public var plateCount = 1
    public var objectNames: [String] = []
    public var embeddedThumbnail: String?

    public var brand: String? { printerModel.flatMap(ThreeMFInfo.brand(of:)) }

    /// "Bambu Lab A1 mini" → "Bambu Lab"; "Snapmaker U1" → "Snapmaker"; outros → primeira palavra.
    public static func brand(of model: String) -> String? {
        let m = model.trimmingCharacters(in: .whitespaces)
        if m.isEmpty { return nil }
        if m.lowercased().hasPrefix("bambu") { return "Bambu Lab" }
        return String(m.split(separator: " ").first ?? Substring(m))
    }

    static let thumbnailCandidates = [
        "Auxiliaries/.thumbnails/thumbnail_middle.png",
        "Metadata/plate_1.png",
        "Metadata/thumbnail.png",
        "Auxiliaries/.thumbnails/thumbnail_3mf.png",
        "Metadata/plate_1_small.png",
        "Metadata/top_1.png",
    ]
}

public enum ThreeMF {
    public static func info(url: URL) throws -> ThreeMFInfo {
        try info(zip: ZipArchive(url: url))
    }

    public static func info(zip: ZipArchive) throws -> ThreeMFInfo {
        var info = ThreeMFInfo()
        if let raw = try? zip.read("Metadata/project_settings.config") {
            info.settingsHash = SHA256.hash(data: raw).map { String(format: "%02x", $0) }.joined()
            if let json = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] {
                info.printerModel = (json["printer_model"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                info.printerSettingsID = json["printer_settings_id"] as? String
                info.printSettingsID = json["print_settings_id"] as? String
                info.filamentColours = json["filament_colour"] as? [String] ?? []
                if let area = json["printable_area"] as? [String] {
                    let pts = area.compactMap { s -> SIMD2<Double>? in
                        let p = s.split(separator: "x").compactMap { Double($0) }
                        return p.count == 2 ? SIMD2(p[0], p[1]) : nil
                    }
                    if pts.count >= 3 {
                        info.bedMin = pts.reduce(pts[0]) { simd_min($0, $1) }
                        info.bedMax = pts.reduce(pts[0]) { simd_max($0, $1) }
                    }
                }
            }
        }
        // Só o cabeçalho: o metadado Application vem antes da malha.
        if let model = try? zip.read("3D/3dmodel.model", prefix: 16_384) {
            let head = String(decoding: model, as: UTF8.self)
            info.application = head.firstMatch(#"<metadata name="Application">([^<]*)<"#)
        }
        if let settings = try? zip.read("Metadata/model_settings.config") {
            let text = String(decoding: settings, as: UTF8.self)
            info.plateCount = max(1, text.components(separatedBy: "<plate>").count - 1)
            info.objectNames = text.allMatches(#"<object id="[^"]*">\s*<metadata key="name" value="([^"]*)""#)
        }
        info.embeddedThumbnail = ThreeMFInfo.thumbnailCandidates.first(where: zip.contains)
        return info
    }
}

extension String {
    func firstMatch(_ pattern: String) -> String? { allMatches(pattern).first }

    func allMatches(_ pattern: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = self as NSString
        return re.matches(in: self, range: NSRange(location: 0, length: ns.length)).compactMap {
            $0.numberOfRanges > 1 ? ns.substring(with: $0.range(at: 1)) : nil
        }
    }
}
