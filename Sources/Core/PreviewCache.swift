import CryptoKit
import Foundation

/// Previews renderizados pelo indexador, lidos pelas extensões do Quick Look.
/// O nome carrega caminho + tamanho + data de modificação: arquivo alterado vira outro nome (cache invalida sozinho).
public enum PreviewCache {
    /// Home real do usuário (nas extensões em sandbox, `homeDirectoryForCurrentUser` aponta para o container).
    public static let directory: URL = {
        let home = getpwuid(getuid()).flatMap { String(validatingUTF8: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Application Support/3dSlicerRouter/previews", isDirectory: true)
    }()

    public static func name(for url: URL) -> String? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let size = values.fileSize, let modified = values.contentModificationDate else { return nil }
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        let digest = SHA256.hash(data: Data(path.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
        return "\(digest)-\(size)-\(Int(modified.timeIntervalSince1970)).png"
    }

    public static func cachedURL(for url: URL) -> URL? {
        guard let name = name(for: url) else { return nil }
        let file = directory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }

    @discardableResult
    public static func store(_ png: Data, for url: URL) -> URL? {
        guard let name = name(for: url) else { return nil }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(name)
        // Remove versões antigas do mesmo arquivo (mesmo prefixo de caminho).
        let prefix = String(name.prefix(32))
        for old in (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [] where old.hasPrefix(prefix) && old != name {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(old))
        }
        return (try? png.write(to: file, options: .atomic)) == nil ? nil : file
    }
}
