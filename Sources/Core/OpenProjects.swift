import Foundation

/// Projeto que um fatiador está com aberto agora, achado pela pasta de backup que ele mantém.
public struct OpenProject: Equatable {
    public let pid: Int32
    public let bundleID: String
    public let origin: String
    /// Há alterações não salvas (o backup `<pasta>/.3mf` existe; some quando o fatiador salva).
    public let dirty: Bool
}

/// Bambu Studio e Snapmaker Orca (base OrcaSlicer) gravam, por projeto aberto,
/// `$TMPDIR/<raiz>/<Dia_Mês_DD>/<HH_MM_SS>#<PID>#<modelId>/` com `origin.txt` (caminho do projeto).
/// Saída limpa apaga a pasta; sobras de processos mortos são ignoradas pela checagem do PID.
/// Layout lido do código-fonte das versões 02.07 (Bambu) e 2.3.6 (Snapmaker Orca), não é API pública.
public enum OpenProjects {
    public static let roots = [
        (folder: "bamboo_model", bundleID: "com.bambulab.bambu-studio"),
        (folder: "snapmaker_orca_model", bundleID: "com.snapmaker.snapmaker-orca"),
    ]

    public struct Process {
        public let bundleID: String
        public let launched: Date?
        public init(bundleID: String, launched: Date?) {
            self.bundleID = bundleID
            self.launched = launched
        }
    }

    /// `running(pid)` devolve o processo vivo com esse PID, ou nil.
    public static func find(_ file: URL, tmp: URL = FileManager.default.temporaryDirectory,
                            running: (Int32) -> Process?) -> OpenProject? {
        let target = normalize(file.path)
        let fm = FileManager.default
        var best: (project: OpenProject, stamp: Date)?
        var newestPerPID: [Int32: Date] = [:]
        var candidates: [(OpenProject, Date)] = []

        for root in roots {
            let base = tmp.appendingPathComponent(root.folder, isDirectory: true)
            for day in (try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)) ?? [] {
                for session in (try? fm.contentsOfDirectory(at: day, includingPropertiesForKeys: [.creationDateKey])) ?? [] {
                    let parts = session.lastPathComponent.split(separator: "#")
                    guard parts.count >= 2, let pid = Int32(parts[1]),
                          let process = running(pid), process.bundleID == root.bundleID else { continue }
                    let created = (try? session.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                    // PID reciclado: o processo vivo nasceu depois da pasta.
                    if let launched = process.launched, launched > created.addingTimeInterval(2) { continue }
                    let originURL = session.appendingPathComponent("origin.txt")
                    guard let origin = try? String(contentsOf: originURL, encoding: .utf8)
                        .trimmingCharacters(in: .whitespacesAndNewlines), !origin.isEmpty else { continue }
                    let stamp = (try? originURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? created
                    newestPerPID[pid] = max(newestPerPID[pid] ?? .distantPast, stamp)
                    let dirty = fm.fileExists(atPath: session.appendingPathComponent(".3mf").path)
                    candidates.append((OpenProject(pid: pid, bundleID: root.bundleID, origin: origin, dirty: dirty), stamp))
                }
            }
        }
        for (project, stamp) in candidates {
            // Um processo que já carregou outro projeto depois deste não está mais com ele aberto.
            guard stamp >= (newestPerPID[project.pid] ?? stamp), matches(project.origin, target) else { continue }
            if best == nil || stamp > best!.stamp { best = (project, stamp) }
        }
        return best?.project
    }

    static func matches(_ origin: String, _ target: String) -> Bool {
        // Fatiador aberto pela linha de comando grava caminho relativo: compara pelo final.
        origin.hasPrefix("/") ? normalize(origin) == target : target.hasSuffix("/" + origin)
    }

    static func normalize(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }
}
