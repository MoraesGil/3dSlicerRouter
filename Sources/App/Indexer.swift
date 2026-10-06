import AppKit
import IOKit
import IOKit.ps
import ServiceManagement

/// Acha todos os .3mf e .gcode pelo Spotlight, cataloga e pré-renderiza os previews que faltam,
/// só quando o Mac está na tomada e ocioso. Roda pelo LaunchAgent do app (`--index-agent`).
enum Indexer {
    static let agentPlist = "com.moraesdev.3dslicerrouter.indexer.plist"
    static let minIdle: TimeInterval = 180
    /// Arquivos maiores que isso são catalogados mas não renderizados (malhas de centenas de MB).
    static let maxRenderBytes = 250_000_000
    static let log = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Logs/3dSlicerRouter/indexer.log")

    struct Summary { var found = 0, rendered = 0, skipped = 0, failed = 0, stoppedEarly = false }

    // MARK: condições

    static var onACPower: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? else { return true }
        return type == kIOPMACPowerKey
    }

    /// Segundos desde o último evento de teclado/mouse (IOHIDSystem, sem permissão especial).
    static var idleSeconds: TimeInterval {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        defer { IOObjectRelease(service) }
        guard service != 0,
              let value = IORegistryEntryCreateCFProperty(service, "HIDIdleTime" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? NSNumber else { return 0 }
        return value.doubleValue / 1_000_000_000
    }

    static func whyNotNow() -> String? {
        if !onACPower { return "na bateria" }
        if ProcessInfo.processInfo.isLowPowerModeEnabled { return "modo de pouca energia" }
        if ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue { return "Mac quente" }
        let idle = idleSeconds
        if idle < minIdle { return String(format: "em uso (ocioso há %.0fs)", idle) }
        return nil
    }

    // MARK: descoberta

    static func discover() -> [URL] {
        let query = #"kMDItemFSName == "*.3mf"c || kMDItemFSName == "*.gcode"c"#
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = [query]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let skip = ["/.Trash/", "/Library/Caches/", ".app/Contents/", "/private/var/folders/", "/3dSlicerRouter/previews/"]
        return String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
            .filter { path in !skip.contains { path.contains($0) } }
            .map { URL(fileURLWithPath: $0) }
    }

    // MARK: passada

    /// `force` ignora as condições de ociosidade (uso manual pela linha de comando).
    @discardableResult
    static func run(store: Store, force: Bool, limit: Int? = nil, budget: TimeInterval = 20 * 60) -> Summary {
        var summary = Summary()
        if !force, let reason = whyNotNow() {
            write("pulado: \(reason)")
            return summary
        }
        let start = Date()
        var files = discover().compactMap { url -> (URL, Int, Date)? in
            guard let v = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = v.fileSize, let modified = v.contentModificationDate else { return nil }
            return (url, size, modified)
        }
        files.sort { $0.2 > $1.2 } // mais recentes primeiro
        summary.found = files.count
        store.pruneCatalog(keeping: Set(files.map { $0.0.path }))

        for (url, size, modified) in files {
            if let limit, summary.rendered >= limit { break }
            if Date().timeIntervalSince(start) > budget { summary.stoppedEarly = true; break }
            if !force, let reason = whyNotNow() {
                write("parou: \(reason)")
                summary.stoppedEarly = true
                break
            }
            if store.isCatalogued(url.path, size: size, modified: modified) { summary.skipped += 1; continue }
            autoreleasepool {
                let entry = index(url, size: size, modified: modified)
                store.upsertCatalog(entry)
                if entry.error != nil { summary.failed += 1 } else if entry.rendered { summary.rendered += 1 } else { summary.skipped += 1 }
            }
        }
        write(String(format: "achados %d, renderizados %d, já ok %d, erros %d%@ em %.0fs", summary.found, summary.rendered,
                     summary.skipped, summary.failed, summary.stoppedEarly ? " (interrompido)" : "", Date().timeIntervalSince(start)))
        return summary
    }

    struct Entry {
        let path: String, kind: String, size: Int, modified: Date
        var printer: String?, plates = 1, embedded = false, preview: String?, rendered = false, error: String?
    }

    static func index(_ url: URL, size: Int, modified: Date) -> Entry {
        let gcode = url.pathExtension.lowercased() == "gcode"
        var entry = Entry(path: url.path, kind: gcode ? "gcode" : "3mf", size: size, modified: modified)
        do {
            let render: () throws -> CGImage
            if gcode {
                let meta = try GCode.metadata(url: url)
                entry.printer = meta.info.printerModel
                entry.embedded = meta.thumbnail != nil
                render = { try PreviewRenderer.renderGCode(url: url, info: meta.info, size: CGSize(width: 1024, height: 1024)) }
            } else {
                let info = try ThreeMF.info(url: url)
                entry.printer = info.printerModel
                entry.plates = info.plateCount
                entry.embedded = info.embeddedThumbnail != nil
                render = { try PreviewRenderer.render(url: url, info: info, size: CGSize(width: 1024, height: 1024)) }
            }
            if let cached = PreviewCache.cachedURL(for: url) {
                entry.preview = cached.path
            } else if !entry.embedded, size <= maxRenderBytes {
                entry.preview = PreviewCache.store(try PreviewRenderer.encode(render()), for: url)?.path
                entry.rendered = entry.preview != nil
            }
        } catch {
            entry.error = "\(error)"
        }
        return entry
    }

    // MARK: agente em background

    static var service: SMAppService { SMAppService.agent(plistName: agentPlist) }

    static func statusText() -> String {
        switch service.status {
        case .enabled: return "ativo"
        case .requiresApproval: return "aguardando aprovação em Ajustes › Itens de Início"
        case .notRegistered: return "desligado"
        case .notFound: return "não encontrado (instale em /Applications)"
        @unknown default: return "desconhecido"
        }
    }

    static func write(_ line: String) {
        try? FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date())
        let text = "\(stamp) \(line)\n"
        if let handle = try? FileHandle(forWritingTo: log) {
            handle.seekToEndOfFile(); handle.write(Data(text.utf8)); try? handle.close()
        } else {
            try? text.write(to: log, atomically: true, encoding: .utf8)
        }
    }
}
