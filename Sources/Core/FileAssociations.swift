import AppKit
import UniformTypeIdentifiers

/// Claim only the registered types for our two document extensions, never public.data.
public enum FileAssociations {
    public static let extensions = ["3mf", "gcode"]
    public static let threeMF = UTType(importedAs: "org.3mf.3mf")
    public static let gcode = UTType(importedAs: "com.moraesdev.gcode")

    public static var types: [UTType] {
        var seen = Set<String>()
        return ([threeMF, gcode] + extensions.flatMap {
            UTType.types(tag: $0, tagClass: .filenameExtension, conformingTo: .data)
        }).filter { type in
            !type.isDynamic && type != .data && type != .content && type != .plainText
                && seen.insert(type.identifier).inserted
        }
    }

    public typealias Setter = (URL, UTType, @escaping (Error?) -> Void) -> Void

    public static func makeDefault(at app: URL, types: [UTType] = FileAssociations.types,
                                   setter: @escaping Setter = { url, type, reply in
                                       NSWorkspace.shared.setDefaultApplication(at: url, toOpen: type) { error in reply(error) }
                                   }, completion: @escaping (Error?) -> Void) {
        let group = DispatchGroup()
        let lock = NSLock()
        var failures: [String] = []
        for type in types {
            group.enter()
            setter(app, type) { error in
                if error != nil {
                    lock.lock(); failures.append(type.identifier); lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            let error: Error? = failures.isEmpty ? nil : NSError(domain: "3dSlicerRouter.FileAssociations", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not set the default application for: \(failures.sorted().joined(separator: ", "))"])
            completion(error)
        }
    }
}
