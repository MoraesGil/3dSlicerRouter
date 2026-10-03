import AppKit
import UniformTypeIdentifiers

/// Diálogos nativos: escolher o fatiador e erros.
enum Prompt {
    struct Choice { let app: SlicerApp; let remember: Bool }

    static func choose(url: URL, info: ThreeMFInfo, reason: AskReason, suggested: SlicerApp?) -> Choice? {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L10n.openWhich(url.lastPathComponent)
        let model = info.printerModel
        switch reason {
        case .manual: alert.informativeText = L10n.reasonManual(model ?? L10n.notDeclared)
        case let .unknownPrinter(m): alert.informativeText = L10n.reasonUnknown(m)
        case let .printerChanged(from, to): alert.informativeText = L10n.reasonChanged(from ?? L10n.notDeclared, to)
        case .noPrinter: alert.informativeText = L10n.reasonNoPrinter
        }
        if let png = info.embeddedThumbnail.flatMap({ try? ZipArchive(url: url).read($0) }), let image = NSImage(data: png) {
            alert.icon = image
        }

        var apps = SlicerApp.known
        if let s = suggested { apps.removeAll { $0 == s }; apps.insert(s, at: 0) }
        for app in apps { alert.addButton(withTitle: app.name) }
        alert.addButton(withTitle: L10n.otherApp)
        alert.addButton(withTitle: L10n.cancel)

        var checkbox: NSButton?
        if let model {
            let box = NSButton(checkboxWithTitle: L10n.rememberFor(model), target: nil, action: nil)
            if case .unknownPrinter = reason { box.state = .on }
            alert.accessoryView = box
            checkbox = box
        }

        let response = alert.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        let remember = checkbox?.state == .on
        if response < apps.count { return Choice(app: apps[response], remember: remember) }
        if response == apps.count, let other = pickApplication() { return Choice(app: other, remember: remember) }
        return nil
    }

    /// Seletor nativo de apps em /Applications.
    static func pickApplication() -> SlicerApp? {
        let panel = NSOpenPanel()
        panel.title = L10n.pickTitle
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        let bundle = Bundle(url: url)
        let name = (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return SlicerApp(bundleID: bundle?.bundleIdentifier ?? "", path: url.path, name: name)
    }

    static func error(_ message: String, detail: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = detail
        alert.runModal()
    }
}
