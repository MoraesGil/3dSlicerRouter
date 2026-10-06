import AppKit
import ServiceManagement

// CLI para conferir sem abrir app nem roubar foco:
//   3dSlicerRouter --inspect arq.3mf…      decisão que seria tomada (não grava nada)
//   3dSlicerRouter --render arq.3mf out.png [px]
//   3dSlicerRouter --forget arq.3mf…       apaga a memória do arquivo
//   3dSlicerRouter --map "<printer_model>" /Applications/App.app   impressora → qualquer fatiador
//   3dSlicerRouter --mappings              lista os mapeamentos
//   3dSlicerRouter --set-default           torna o router o app padrão de .3mf
let args = Array(CommandLine.arguments.dropFirst())

func describe(_ d: Decision) -> String {
    switch d {
    case let .open(app, reason): return "open \(app.name) (\(reason))"
    case let .ask(why, suggested): return "ask \(why) suggested=\(suggested?.name ?? "-")"
    case .classify: return "classify (LAYA)"
    }
}

switch args.first {
case "--inspect":
    let store = Store()
    for path in args.dropFirst() {
        let url = URL(fileURLWithPath: path)
        do {
            let info = try ThreeMF.info(url: url)
            let record = store.record(for: url)
            let decision = Router.decide(info: info, record: record, mappings: store.mappings(), optionHeld: false)
            let laya = decision == .classify
                ? Laya.classify(info: info, fileName: url.lastPathComponent).map { String(format: "%@ %.0f%%", $0.app.name, $0.probability * 100) } ?? "sem palpite"
                : "-"
            print("""
            \(url.lastPathComponent)
              printer_model: \(info.printerModel ?? "-")  brand: \(info.brand ?? "-")
              application:   \(info.application ?? "-")
              plates: \(info.plateCount)  bed: \(info.bedMin) … \(info.bedMax)
              thumbnail:     \(info.embeddedThumbnail ?? "nenhuma (gera preview)")
              record:        \(record.map { "\($0.uuid) \($0.printerModel ?? "-") → \($0.app.name)" } ?? "-")
              decision:      \(describe(decision))
              laya:          \(laya) (abre direto a partir de \(Int(Laya.minProbability * 100))%)
              aberto agora:  \(OpenProjects.find(url, running: RouterApp.process(pid:)).map { "\($0.bundleID) pid \($0.pid)\($0.dirty ? " (alterações não salvas)" : "")" } ?? "não")
            """)
        } catch {
            print("\(path): erro \(error)")
        }
    }
case "--render":
    guard args.count >= 3 else { print("uso: --render arq.3mf out.png [px]"); exit(2) }
    let url = URL(fileURLWithPath: args[1])
    let px = args.count > 3 ? Double(args[3]) ?? 1024 : 1024
    do {
        let start = Date()
        let size = CGSize(width: px, height: px)
        let png: Data
        if url.pathExtension.lowercased() == "gcode" {
            png = try PreviewRenderer.encode(PreviewRenderer.renderGCode(url: url, info: GCode.metadata(url: url).info, size: size))
        } else {
            png = try PreviewRenderer.png(url: url, info: ThreeMF.info(url: url), size: size)
        }
        try png.write(to: URL(fileURLWithPath: args[2]))
        print(String(format: "ok %.2fs", Date().timeIntervalSince(start)))
    } catch {
        print("erro \(error)"); exit(1)
    }
case "--map":
    guard args.count == 3 else { print("uso: --map \"<printer_model>\" /Applications/Slicer.app"); exit(2) }
    let appURL = URL(fileURLWithPath: args[2])
    guard let bundle = Bundle(url: appURL) else { print("não é um app: \(args[2])"); exit(1) }
    let name = (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? appURL.deletingPathExtension().lastPathComponent
    Store().remember(printer: args[1], app: SlicerApp(bundleID: bundle.bundleIdentifier ?? "", path: appURL.path, name: name))
    print("\(args[1]) → \(name)")
case "--mappings":
    let m = Store().mappings()
    for (brand, app) in m.byBrand.sorted(by: { $0.key < $1.key }) { print("\(brand) …  → \(app.name)  (padrão)") }
    for (model, app) in m.byModel.sorted(by: { $0.key < $1.key }) { print("\(model)  → \(app.name)") }
case "--index":
    // Passada manual: ignora as condições de ociosidade. --limit N limita renders.
    let limit = args.firstIndex(of: "--limit").flatMap { args.count > $0 + 1 ? Int(args[$0 + 1]) : nil }
    let s = Indexer.run(store: Store(), force: true, limit: limit, budget: .infinity)
    print("achados \(s.found), renderizados \(s.rendered), já ok \(s.skipped), erros \(s.failed)")
case "--index-agent":
    // Chamado pelo LaunchAgent: só trabalha na tomada e com o Mac ocioso.
    Indexer.run(store: Store(), force: false)
case "--index-status":
    print("background: \(Indexer.statusText())")
    print("agora: \(Indexer.whyNotNow() ?? "pronto para indexar (na tomada e ocioso)")")
    print(Store().catalogStats())
    print("log: \(Indexer.log.path)")
case "--catalog":
    for row in Store().catalog(matching: args.count > 1 ? args[1] : nil) { print(row) }
case "--background":
    do {
        switch args.count > 1 ? args[1] : "status" {
        case "on": try Indexer.service.register()
        case "off": try Indexer.service.unregister()
        default: break
        }
        print("background: \(Indexer.statusText())")
        if Indexer.service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    } catch {
        print("erro: \(error.localizedDescription)"); exit(1)
    }
case "--version":
    print(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")
case "--forget":
    let store = Store()
    for path in args.dropFirst() { store.forget(URL(fileURLWithPath: path)) }
case "--set-default":
    var failure: Error?
    var done = false
    RouterApp.makeDefault { failure = $0; done = true }
    while !done { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
    if let failure { print("erro \(failure)"); exit(1) }
    print("padrão .3mf → \(NSWorkspace.shared.urlForApplication(toOpen: RouterApp.threeMFType)?.path ?? "?")")
default:
    let app = NSApplication.shared
    let delegate = RouterApp()
    app.delegate = delegate
    app.run()
}
