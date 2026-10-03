import AppKit

// CLI para conferir sem abrir app nem roubar foco:
//   3dSlicerRouter --inspect arq.3mf…      decisão que seria tomada (não grava nada)
//   3dSlicerRouter --render arq.3mf out.png [px]
//   3dSlicerRouter --forget arq.3mf…       apaga a memória do arquivo
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
        let info = try ThreeMF.info(url: url)
        try PreviewRenderer.png(url: url, info: info, size: CGSize(width: px, height: px)).write(to: URL(fileURLWithPath: args[2]))
        print(String(format: "ok %.2fs", Date().timeIntervalSince(start)))
    } catch {
        print("erro \(error)"); exit(1)
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
