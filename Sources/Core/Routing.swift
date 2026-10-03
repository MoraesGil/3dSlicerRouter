import Foundation

public struct SlicerApp: Codable, Equatable, Hashable {
    public var bundleID: String
    public var path: String
    public var name: String

    public init(bundleID: String, path: String, name: String) {
        self.bundleID = bundleID
        self.path = path
        self.name = name
    }

    public static let bambuStudio = SlicerApp(
        bundleID: "com.bambulab.bambu-studio", path: "/Applications/BambuStudio.app", name: "Bambu Studio")
    public static let snapmakerOrca = SlicerApp(
        bundleID: "com.snapmaker.snapmaker-orca", path: "/Applications/Snapmaker Orca.app", name: "Snapmaker Orca")
    public static let known = [bambuStudio, snapmakerOrca]
}

/// Decisão gravada no arquivo (xattr) e no índice SQLite.
public struct FileRecord: Codable, Equatable {
    public var uuid: String
    public var printerModel: String?
    public var app: SlicerApp
    /// O dono escolheu outro app à mão para este arquivo (⌥ ou seletor).
    public var override: Bool
    public var settingsHash: String?
    public var decidedAt: Date

    public init(uuid: String, printerModel: String?, app: SlicerApp, override: Bool, settingsHash: String?, decidedAt: Date = Date()) {
        self.uuid = uuid
        self.printerModel = printerModel
        self.app = app
        self.override = override
        self.settingsHash = settingsHash
        self.decidedAt = decidedAt
    }
}

/// Memória gravada no próprio arquivo (xattr): sobrevive a cópias no APFS, some em zip/upload.
extension FileRecord {
    public static let xattrName = "com.moraesdev.slicer-router"

    public static func read(from url: URL) -> FileRecord? {
        let size = getxattr(url.path, xattrName, nil, 0, 0, 0)
        guard size > 0 else { return nil }
        var data = Data(count: size)
        let read = data.withUnsafeMutableBytes { getxattr(url.path, xattrName, $0.baseAddress, size, 0, 0) }
        guard read == size else { return nil }
        return try? JSONDecoder().decode(FileRecord.self, from: data)
    }

    @discardableResult
    public func write(to url: URL) -> Bool {
        guard let data = try? JSONEncoder().encode(self) else { return false }
        return data.withUnsafeBytes { setxattr(url.path, Self.xattrName, $0.baseAddress, data.count, 0, 0) } == 0
    }

    public static func remove(from url: URL) { removexattr(url.path, xattrName, 0) }
}

/// Impressora → app. Modelo exato vence marca; as marcas padrão valem mesmo sem SQLite.
public struct Mappings {
    public var byModel: [String: SlicerApp] = [:]
    public var byBrand: [String: SlicerApp] = ["Bambu Lab": .bambuStudio, "Snapmaker": .snapmakerOrca]

    public init() {}

    public func app(for model: String) -> SlicerApp? {
        byModel[model] ?? ThreeMFInfo.brand(of: model).flatMap { byBrand[$0] }
    }
}

public enum AskReason: Equatable {
    /// ⌥ segurado ao abrir.
    case manual
    /// Impressora sem app mapeado.
    case unknownPrinter(String)
    /// Impressora do arquivo mudou para outra marca que não Bambu.
    case printerChanged(from: String?, to: String)
    /// Arquivo sem `printer_model` e o LAYA não teve certeza.
    case noPrinter
}

public enum Decision: Equatable {
    case open(SlicerApp, reason: String)
    case ask(AskReason, suggested: SlicerApp?)
    /// Sem `printer_model`: classificar (LAYA) antes de perguntar.
    case classify
}

public enum Router {
    public static func decide(info: ThreeMFInfo, record: FileRecord?, mappings: Mappings, optionHeld: Bool) -> Decision {
        let model = info.printerModel
        let mapped = model.flatMap(mappings.app(for:))
        if optionHeld { return .ask(.manual, suggested: record?.app ?? mapped) }

        guard let model else {
            if let record, record.printerModel == nil { return .open(record.app, reason: "lembrado (sem impressora)") }
            return .classify
        }
        if let record {
            if record.printerModel == model { return .open(record.app, reason: "lembrado") }
            let oldBrand = record.printerModel.flatMap(ThreeMFInfo.brand(of:))
            // Mesma marca (A1 → A1 mini): sem perguntar, mantém a escolha do arquivo.
            if oldBrand == info.brand { return .open(record.app, reason: "mesma marca (\(oldBrand ?? "?"))") }
            // Mudou para Bambu: abre direto no app mapeado.
            if info.brand == "Bambu Lab", let mapped { return .open(mapped, reason: "mudou para \(model)") }
            return .ask(.printerChanged(from: record.printerModel, to: model), suggested: mapped)
        }
        if let mapped { return .open(mapped, reason: "regra \(info.brand ?? model)") }
        return .ask(.unknownPrinter(model), suggested: nil)
    }
}
