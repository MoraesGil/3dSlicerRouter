import AppKit
import CryptoKit

/// The Router shape stays recognizable; its colour identifies the destination slicer.
public enum SlicerIconStyle: String, CaseIterable {
    case router, bambu, orca, snapmaker, prusa, cura, creality, elegoo

    public static func style(for app: SlicerApp?) -> SlicerIconStyle {
        guard let app else { return .router }
        let identity = (app.bundleID + " " + app.name).lowercased().filter { $0.isLetter || $0.isNumber }
        if identity.contains("snapmaker") { return .snapmaker }
        if identity.contains("bambu") { return .bambu }
        if identity.contains("prusa") { return .prusa }
        if identity.contains("orca") { return .orca }
        if identity.contains("cura") { return .cura }
        if identity.contains("creality") { return .creality }
        if identity.contains("elegoo") { return .elegoo }
        return .router
    }

    public var colour: NSColor {
        let rgb: UInt32
        switch self {
        case .router: rgb = 0x87D9B6
        case .bambu: rgb = 0x00AE42
        case .orca: rgb = 0x368BC7
        case .snapmaker: rgb = 0xF1F1F1
        case .prusa: rgb = 0xF47929
        case .cura: rgb = 0x2463D8
        case .creality: rgb = 0x00A67A
        case .elegoo: rgb = 0x266FD5
        }
        return NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255,
                       green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: 1)
    }
}

private final class RouterIconResourceAnchor: NSObject {}

public enum RouterFileIcon {
    private static let markerName = "com.moraesdev.slicer-router.icon"
    private static let lock = NSRecursiveLock()
    private static var icons: [SlicerIconStyle: NSImage] = [:]

    public static var logoURL: URL? {
        let bundles = [Bundle.main, Bundle(for: RouterIconResourceAnchor.self)]
        var candidates: [URL] = []
        for bundle in bundles {
            if bundle.bundleIdentifier == "com.moraesdev.3dslicerrouter",
               let resource = bundle.url(forResource: "AppIcon", withExtension: "icns") { return resource }
            var directory = bundle.bundleURL
            for _ in 0..<5 {
                if directory.lastPathComponent == "3dSlicerRouter.app" {
                    candidates.append(directory.appendingPathComponent("Contents/Resources/AppIcon.icns"))
                }
                directory = directory.deletingLastPathComponent()
            }
            candidates.append(bundle.bundleURL.deletingLastPathComponent()
                .appendingPathComponent("3dSlicerRouter.app/Contents/Resources/AppIcon.icns"))
        }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    public static func usesBrandIcon(maximumSize: CGSize) -> Bool {
        max(maximumSize.width, maximumSize.height) <= 64
    }

    public static func image(for app: SlicerApp?) -> NSImage {
        let style = SlicerIconStyle.style(for: app)
        lock.lock(); defer { lock.unlock() }
        if let image = icons[style] { return image }
        let image = render(style: style, pixels: 512)
        icons[style] = image
        return image
    }

    public static func png(style: SlicerIconStyle, pixels: Int) throws -> Data {
        guard (16...2048).contains(pixels),
              let bitmap = render(style: style, pixels: pixels).representations.first as? NSBitmapImageRep,
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "3dSlicerRouter.Icon", code: 1)
        }
        return png
    }

    private static func render(style: SlicerIconStyle, pixels: Int) -> NSImage {
        let size = NSSize(width: pixels, height: pixels)
        let image = NSImage(size: size)
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return image }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        defer { NSGraphicsContext.restoreGraphicsState() }
        let s = CGFloat(pixels)
        context.imageInterpolation = .high
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill(using: .copy)
        let outline = NSBezierPath(roundedRect: NSRect(x: s * 0.05, y: s * 0.05, width: s * 0.90, height: s * 0.90),
                                   xRadius: s * 0.20, yRadius: s * 0.20)
        NSColor(srgbRed: 0.09, green: 0.11, blue: 0.14, alpha: 1).setFill(); outline.fill()
        if let logo = logoURL.flatMap({ NSImage(contentsOf: $0) }) {
            logo.draw(in: NSRect(origin: .zero, size: size))
        } else {
            // Keep an identifiable stacked Router mark if the resource cannot be loaded.
            for y in [0.30, 0.44, 0.58] {
                style.colour.setFill()
                NSBezierPath(roundedRect: NSRect(x: s * 0.27, y: s * y, width: s * 0.46, height: s * 0.12),
                             xRadius: s * 0.025, yRadius: s * 0.025).fill()
            }
        }
        if style != .router {
            // Colour blending keeps the original lighting and relief while replacing
            // both the green and blue parts with the destination slicer's hue.
            context.cgContext.saveGState()
            context.cgContext.setBlendMode(.color)
            style.colour.setFill()
            outline.fill()
            context.cgContext.restoreGState()
        }
        outline.lineWidth = max(1, s * 0.035)
        style.colour.setStroke(); outline.stroke()
        image.addRepresentation(bitmap)
        return image
    }

    private static func marker(for url: URL) -> String? {
        let count = getxattr(url.path, markerName, nil, 0, 0, 0)
        guard count > 0, count < 256 else { return nil }
        var bytes = [UInt8](repeating: 0, count: count)
        guard getxattr(url.path, markerName, &bytes, count, 0, 0) == count else { return nil }
        return String(bytes: bytes, encoding: .utf8)
    }

    private static func hasCustomIcon(_ url: URL) -> Bool {
        var finderInfo = [UInt8](repeating: 0, count: 32)
        return getxattr(url.path, "com.apple.FinderInfo", &finderInfo, 32, 0, 0) == 32 && finderInfo[8] & 0x04 != 0
    }

    private static func resourceDigest(_ url: URL) -> String? {
        let count = getxattr(url.path, "com.apple.ResourceFork", nil, 0, 0, 0)
        guard count > 0, count <= 16_777_216 else { return nil }
        var data = Data(count: count)
        let read = data.withUnsafeMutableBytes { getxattr(url.path, "com.apple.ResourceFork", $0.baseAddress, count, 0, 0) }
        guard read == count else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func ownsIcon(_ url: URL, marker: String?) -> Bool {
        guard let marker else { return false }
        let fields = marker.split(separator: ":")
        return fields.count == 3 && ["v2", "v3"].contains(fields[0]) && resourceDigest(url) == String(fields[2])
    }

    private static func digest(_ handle: FileHandle) throws -> Data {
        try handle.seek(toOffset: 0)
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty { hash.update(data: chunk) }
        return Data(hash.finalize())
    }

    private static func sameRevision(_ a: stat, _ b: stat) -> Bool {
        a.st_dev == b.st_dev && a.st_ino == b.st_ino && a.st_size == b.st_size
            && a.st_mtimespec.tv_sec == b.st_mtimespec.tv_sec && a.st_mtimespec.tv_nsec == b.st_mtimespec.tv_nsec
    }

    private static func setIconPreservingDate(_ image: NSImage?, at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        var before = stat(), stable = stat()
        guard fstat(handle.fileDescriptor, &before) == 0, let original = try? digest(handle),
              fstat(handle.fileDescriptor, &stable) == 0, sameRevision(before, stable) else { return false }
        guard NSWorkspace.shared.setIcon(image, forFile: url.path, options: []) else { return false }
        // setIcon also changes mtime. Restore nanoseconds only if the data and file identity
        // are still the same. Use the open fd so an atomic replacement is never backdated.
        var after = stat(), currentPath = stat()
        guard let current = try? digest(handle), current == original,
              fstat(handle.fileDescriptor, &after) == 0, stat(url.path, &currentPath) == 0,
              before.st_dev == currentPath.st_dev && before.st_ino == currentPath.st_ino,
              before.st_size == after.st_size, sameRevision(after, currentPath) else { return false }
        var times = [before.st_atimespec, before.st_mtimespec]
        guard futimens(handle.fileDescriptor, &times) == 0 else { return false }
        return true
    }

    /// Finder icon metadata only. Failure must never prevent the file from opening.
    @discardableResult
    public static func apply(to url: URL, app: SlicerApp?) -> Bool {
        guard FileAssociations.extensions.contains(url.pathExtension.lowercased()),
              FileManager.default.isWritableFile(atPath: url.path) else { return false }
        let stamp = "v3:\(SlicerIconStyle.style(for: app).rawValue)"
        lock.lock(); defer { lock.unlock() }
        let previous = marker(for: url)
        let owned = ownsIcon(url, marker: previous)
        if owned, previous?.hasPrefix(stamp + ":") == true, hasCustomIcon(url) { return true }
        // A user-supplied custom icon is not ours to replace during routing or indexing.
        if hasCustomIcon(url), !owned { return false }
        guard setIconPreservingDate(image(for: app), at: url) else { return false }
        guard let resource = resourceDigest(url) else { return false }
        let bytes = Data((stamp + ":" + resource).utf8)
        _ = bytes.withUnsafeBytes { setxattr(url.path, markerName, $0.baseAddress, bytes.count, 0, 0) }
        NSWorkspace.shared.noteFileSystemChanged(url.path)
        return true
    }

    @discardableResult
    public static func remove(from url: URL) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let previous = marker(for: url)
        guard previous != nil else { return true }
        guard ownsIcon(url, marker: previous) else {
            removexattr(url.path, markerName, 0)
            return true
        }
        guard setIconPreservingDate(nil, at: url) else { return false }
        removexattr(url.path, markerName, 0)
        NSWorkspace.shared.noteFileSystemChanged(url.path)
        return true
    }
}
