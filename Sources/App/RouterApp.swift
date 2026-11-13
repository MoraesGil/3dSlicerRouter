import AppKit
import UniformTypeIdentifiers

/// Recebe os .3mf do Finder, decide o fatiador, abre lá e sai.
final class RouterApp: NSObject, NSApplicationDelegate {
    let store = Store()
    private var handledFiles = false
    private var pending = 0

    func applicationDidFinishLaunching(_ note: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [self] in
            if !handledFiles { showAbout() }
        }
    }

    func application(_ app: NSApplication, open urls: [URL]) {
        handledFiles = true
        pending += 1
        defer { pending -= 1; finishWhenIdle() }
        let option = NSEvent.modifierFlags.contains(.option)
        for url in urls { route(url, optionHeld: option) }
    }

    // MARK: roteamento

    func route(_ url: URL, optionHeld: Bool, checkOpen: Bool = true) {
        if checkOpen, let project = OpenProjects.find(url, running: Self.process(pid:)) {
            handleAlreadyOpen(url, project, optionHeld: optionHeld)
            return
        }
        let document = (try? RoutableDocument.read(url: url)) ?? RoutableDocument(info: ThreeMFInfo(), generator: nil,
            originatingSlicer: nil, isGCode: url.pathExtension.lowercased() == "gcode")
        let info = document.info
        let record = store.record(for: url)
        let mappings = store.mappings()
        var decision = document.decide(record: record, mappings: mappings, optionHeld: optionHeld)

        if case let .open(app, _) = decision, SlicerApp.installedURL(for: app) == nil {
            decision = .ask(.appUnavailable(app.name), suggested: nil)
        }

        let app: SlicerApp, reason: String, override: Bool
        switch decision {
        case let .open(a, r):
            app = SlicerApp.installedApplication(for: a) ?? a; reason = r; override = record?.override ?? false
        case let .ask(why, suggested):
            guard let choice = Prompt.choose(url: url, info: info, reason: why, suggested: suggested) else { return }
            app = choice.app; reason = "escolha do dono"
            // A deliberate per-file choice survives a later change of G-code generator.
            override = true
            if choice.remember, let model = info.printerModel { store.remember(printer: model, app: choice.app) }
        }

        guard open(url, with: app) else { return }
        let uuid = record?.uuid ?? UUID().uuidString
        store.save(FileRecord(uuid: uuid, printerModel: info.printerModel, app: app, override: override,
                              settingsHash: info.settingsHash), for: url, reason: reason)
        // Notify Finder after updating this file's routing metadata.
        NSWorkspace.shared.noteFileSystemChanged(url.path)
    }

    @discardableResult
    func open(_ url: URL, with app: SlicerApp) -> Bool {
        guard let appURL = SlicerApp.installedURL(for: app) else {
            Prompt.error(L10n.notFound(app.name), detail: app.path)
            return false
        }
        pending += 1
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            DispatchQueue.main.async { [self] in
                if let error { Prompt.error(L10n.openFailed(app.name), detail: error.localizedDescription) }
                pending -= 1
                finishWhenIdle()
            }
        }
        return true
    }

    // MARK: arquivo já aberto

    /// Bambu Studio/Orca abririam uma segunda instância com o mesmo projeto; aqui o dono decide.
    func handleAlreadyOpen(_ url: URL, _ project: OpenProject, optionHeld: Bool) {
        let app = SlicerApp.known.first { $0.bundleID == project.bundleID }
        let name = app?.name ?? project.bundleID
        let running = NSRunningApplication(processIdentifier: project.pid)
        switch Prompt.alreadyOpen(url: url, appName: name, appPath: app?.path, dirty: project.dirty) {
        case .switchTo:
            running?.activate()
        case .reload:
            guard let running, running.terminate() else {
                Prompt.error(L10n.alreadyOpen(url.lastPathComponent, name), detail: L10n.closeItFirst(name))
                return
            }
            waitForExit(running, timeout: 300) { [self] in route(url, optionHeld: optionHeld, checkOpen: false) }
        case .anotherCopy:
            route(url, optionHeld: optionHeld, checkOpen: false)
        case .cancel:
            break
        }
    }

    /// O fatiador pode perguntar "Salvar?" antes de sair; se o dono cancelar, desiste sem reabrir.
    private func waitForExit(_ app: NSRunningApplication, timeout: TimeInterval, then reopen: @escaping () -> Void) {
        pending += 1
        let deadline = Date().addingTimeInterval(timeout)
        Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [self] timer in
            guard app.isTerminated || Date() > deadline else { return }
            timer.invalidate()
            if app.isTerminated { reopen() }
            pending -= 1
            finishWhenIdle()
        }
    }

    /// Instância viva com esse PID. As que o próprio fatiador lança podem não estar no NSWorkspace:
    /// nesse caso identifica pelo executável.
    static func process(pid: Int32) -> OpenProjects.Process? {
        if let app = NSRunningApplication(processIdentifier: pid), let id = app.bundleIdentifier {
            return .init(bundleID: id, launched: app.launchDate)
        }
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let path = String(cString: buffer)
        return SlicerApp.known.first { path.hasPrefix($0.path + "/") }.map { .init(bundleID: $0.bundleID, launched: nil) }
    }

    private func finishWhenIdle() {
        if handledFiles, pending == 0 { NSApp.terminate(nil) }
    }

    // MARK: sem arquivo

    func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "3dSlicerRouter"
        let current = NSWorkspace.shared.urlForApplication(toOpen: Self.threeMFType).map { $0.lastPathComponent } ?? L10n.none
        let gcode = NSWorkspace.shared.urlForApplication(toOpen: UTType(filenameExtension: "gcode") ?? FileAssociations.gcode)
            .map { $0.lastPathComponent } ?? L10n.none
        alert.informativeText = L10n.about(current: current, gcode: gcode)
        alert.addButton(withTitle: L10n.makeDefault)
        alert.addButton(withTitle: L10n.refreshIcons)
        alert.addButton(withTitle: L10n.close)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            Self.makeDefault { error in
                if let error { Prompt.error(L10n.defaultFailed, detail: error.localizedDescription) }
                NSApp.terminate(nil)
            }
        } else if response == .alertSecondButtonReturn {
            refreshFileIcons()
            NSApp.terminate(nil)
        } else {
            NSApp.terminate(nil)
        }
    }

    static let threeMFType = UTType(filenameExtension: "3mf") ?? UTType(importedAs: "org.3mf.3mf")

    static func makeDefault(_ done: @escaping (Error?) -> Void) {
        FileAssociations.makeDefault(at: Bundle.main.bundleURL, completion: done)
    }

    private func refreshFileIcons() {
        let picker = NSOpenPanel()
        picker.title = L10n.refreshIcons
        picker.allowedContentTypes = FileAssociations.types
        picker.allowsMultipleSelection = true
        picker.canChooseDirectories = false
        guard picker.runModal() == .OK else { return }
        var updated = 0
        for url in picker.urls {
            guard let document = try? RoutableDocument.read(url: url) else { continue }
            let app = document.expectedApp(record: store.record(for: url), mappings: store.mappings())
            if RouterFileIcon.apply(to: url, app: app) { updated += 1 }
        }
        let result = NSAlert()
        result.messageText = L10n.refreshedIcons(updated, total: picker.urls.count)
        result.informativeText = L10n.iconMetadataOnly
        result.runModal()
    }
}
