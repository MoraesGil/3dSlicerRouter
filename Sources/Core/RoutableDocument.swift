import Foundation

/// Metadata and routing for a saved document. Reading never changes its contents.
public struct RoutableDocument {
    public let info: ThreeMFInfo
    public let generator: String?
    public let originatingSlicer: SlicerApp?
    public let isGCode: Bool

    public static func read(url: URL) throws -> RoutableDocument {
        guard url.pathExtension.lowercased() == "gcode" else {
            return RoutableDocument(info: try ThreeMF.info(url: url), generator: nil,
                                    originatingSlicer: nil, isGCode: false)
        }
        let metadata = try GCode.metadata(url: url)
        return RoutableDocument(info: metadata.info, generator: metadata.generator,
                                originatingSlicer: slicer(for: metadata.generator), isGCode: true)
    }

    private static func slicer(for generator: String?) -> SlicerApp? {
        guard let value = generator?.lowercased() else { return nil }
        let candidates: [(String, SlicerApp)] = [
            ("snapmaker orca", .snapmakerOrca), ("snapmakerorca", .snapmakerOrca),
            ("bambu studio", .bambuStudio), ("bambustudio", .bambuStudio),
            ("orcaslicer", .orcaSlicer), ("orca slicer", .orcaSlicer),
            ("prusaslicer", .prusaSlicer), ("cura_steamengine", .cura),
            ("ultimaker cura", .cura), ("creality print", .crealityPrint),
            ("crealityprint", .crealityPrint)
        ]
        for (name, app) in candidates where value == name || value.hasPrefix(name + " ") || value.hasPrefix(name + "-") {
            return app
        }
        return nil
    }

    public func decide(record: FileRecord?, mappings: Mappings, optionHeld: Bool) -> Decision {
        guard isGCode else { return Router.decide(info: info, record: record, mappings: mappings, optionHeld: optionHeld) }
        let explicit = info.printerModel.flatMap { mappings.byModel[$0] }
        let selected = record?.override == true ? record?.app : (explicit ?? originatingSlicer)
        // Preserve an installed custom path only when it identifies the same app.
        let target = selected.map { app in record?.app.bundleID == app.bundleID ? record!.app : app }
        if optionHeld {
            let fallback = info.printerModel.flatMap { mappings.app(for: $0) }
            return .ask(.manual, suggested: target ?? fallback)
        }
        if let target { return .open(target, reason: record?.override == true ? "escolha manual" : (explicit != nil ? "modelo mapeado" : "gerador")) }
        guard info.printerModel != nil else { return .ask(.noPrinter, suggested: nil) }
        // An automatic record reflects an older file revision, not the current metadata.
        return Router.decide(info: info, record: nil, mappings: mappings, optionHeld: false)
    }

    public func expectedApp(record: FileRecord?, mappings: Mappings) -> SlicerApp? {
        guard isGCode else { return Router.expectedApp(info: info, record: record, mappings: mappings) }
        switch decide(record: record, mappings: mappings, optionHeld: false) {
        case let .open(app, _): return app
        case let .ask(_, suggested): return suggested
        }
    }
}
