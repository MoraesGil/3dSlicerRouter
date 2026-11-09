import AppKit

extension SlicerApp {
    public static func installed(directories: [URL] = applicationDirectories,
                                 registeredURLs: [URL]? = nil, suggested: SlicerApp? = nil) -> [SlicerApp] {
        let manager = FileManager.default
        var urls = suggested.map { [URL(fileURLWithPath: $0.path)] } ?? []
        for directory in directories {
            guard let entries = manager.enumerator(at: directory, includingPropertiesForKeys: nil,
                                                  options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in entries {
                if url.pathExtension.lowercased() == "app" {
                    urls.append(url)
                    entries.skipDescendants()
                } else if entries.level >= 3 {
                    entries.skipDescendants()
                }
            }
        }
        urls += registeredURLs ?? known.flatMap { NSWorkspace.shared.urlsForApplications(withBundleIdentifier: $0.bundleID) }
        var seen = Set<String>()
        let apps = urls.compactMap(installation).filter { app in
            (isSlicer(app) || app.bundleID == suggested?.bundleID) && seen.insert(app.bundleID).inserted
        }
        func rank(_ app: SlicerApp) -> Int {
            if app.bundleID == suggested?.bundleID { return -1 }
            return known.firstIndex { $0.bundleID == app.bundleID } ?? known.count
        }
        return apps.sorted {
            rank($0) == rank($1) ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending : rank($0) < rank($1)
        }
    }

    public static var applicationDirectories: [URL] {
        [URL(fileURLWithPath: "/Applications"), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
    }

    /// A LaunchServices registration alone does not prove the app still exists.
    /// Preserve an exact recorded installation before considering another copy.
    public static func installedURL(for app: SlicerApp) -> URL? {
        let saved = URL(fileURLWithPath: app.path)
        if installation(at: saved)?.bundleID == app.bundleID { return saved }
        return NSWorkspace.shared.urlsForApplications(withBundleIdentifier: app.bundleID)
            .first { installation(at: $0)?.bundleID == app.bundleID }
    }

    private static func installation(at url: URL) -> SlicerApp? {
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier, !id.isEmpty,
              id != "com.moraesdev.3dslicerrouter", let executable = bundle.executableURL,
              FileManager.default.isExecutableFile(atPath: executable.path) else { return nil }
        let name = known.first { $0.bundleID == id }?.name
            ?? bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        return SlicerApp(bundleID: id, path: url.path, name: name)
    }

    private static func isSlicer(_ app: SlicerApp) -> Bool {
        if known.contains(where: { $0.bundleID == app.bundleID }) { return true }
        let names = ["prusaslicer", "superslicer", "cura", "ultimakercura", "crealityprint",
                     "anycubicslicer", "anycubicslicernext", "qidislicer", "qidistudio", "elegooslicer",
                     "flashprint", "ideamaker", "simplify3d"]
        return [app.name, URL(fileURLWithPath: app.path).deletingPathExtension().lastPathComponent].contains { name in
            names.contains(name.lowercased().filter { $0.isLetter || $0.isNumber })
        }
    }
}
