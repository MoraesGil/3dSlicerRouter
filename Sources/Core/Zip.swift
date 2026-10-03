import Compression
import Foundation

/// Leitor mínimo de zip (stored + deflate, com ZIP64) só para ler 3MF sem dependências.
public struct ZipArchive {
    struct Entry {
        let method: UInt16
        let compressedSize: Int
        let size: Int
        let localHeaderOffset: Int
    }

    let data: Data
    let entries: [String: Entry]

    public var names: [String] { Array(entries.keys) }

    public init(url: URL) throws {
        try self.init(data: Data(contentsOf: url, options: .alwaysMapped))
    }

    public init(data: Data) throws {
        self.data = data
        guard let eocd = data.lastIndex(ofSignature: 0x0605_4B50, searchBack: 65_557) else {
            throw ZipError.notZip
        }
        var count = Int(data.u16(eocd + 10))
        var cdOffset = Int(data.u32(eocd + 16))
        if count == 0xFFFF || cdOffset == 0xFFFF_FFFF, eocd >= 20, data.u32(eocd - 20) == 0x0706_4B50 {
            let z64 = Int(data.u64(eocd - 12))
            guard data.u32(z64) == 0x0606_4B50 else { throw ZipError.corrupt }
            count = Int(data.u64(z64 + 32))
            cdOffset = Int(data.u64(z64 + 48))
        }
        var entries: [String: Entry] = [:]
        var p = cdOffset
        for _ in 0..<count {
            guard p + 46 <= data.count, data.u32(p) == 0x0201_4B50 else { throw ZipError.corrupt }
            let method = data.u16(p + 10)
            var csize = Int(data.u32(p + 20))
            var usize = Int(data.u32(p + 24))
            let nameLen = Int(data.u16(p + 28))
            let extraLen = Int(data.u16(p + 30))
            let commentLen = Int(data.u16(p + 32))
            var offset = Int(data.u32(p + 42))
            let name = String(decoding: data.subdata(in: (p + 46)..<(p + 46 + nameLen)), as: UTF8.self)
            // Extra ZIP64 (0x0001): só traz os campos que estavam saturados, nesta ordem.
            var e = p + 46 + nameLen
            let extraEnd = e + extraLen
            while e + 4 <= extraEnd {
                let id = data.u16(e), len = Int(data.u16(e + 2))
                if id == 0x0001 {
                    var q = e + 4
                    if usize == 0xFFFF_FFFF { usize = Int(data.u64(q)); q += 8 }
                    if csize == 0xFFFF_FFFF { csize = Int(data.u64(q)); q += 8 }
                    if offset == 0xFFFF_FFFF { offset = Int(data.u64(q)) }
                }
                e += 4 + len
            }
            entries[name] = Entry(method: method, compressedSize: csize, size: usize, localHeaderOffset: offset)
            p = extraEnd + commentLen
        }
        self.entries = entries
    }

    public func contains(_ name: String) -> Bool { entries[name] != nil }

    /// `prefix` limita os bytes descomprimidos (ex.: só o cabeçalho de um .model gigante).
    public func read(_ name: String, prefix: Int? = nil) throws -> Data {
        guard let entry = entries[name] else { throw ZipError.missing(name) }
        let h = entry.localHeaderOffset
        guard data.u32(h) == 0x0403_4B50 else { throw ZipError.corrupt }
        let start = h + 30 + Int(data.u16(h + 26)) + Int(data.u16(h + 28))
        let raw = data.subdata(in: start..<(start + entry.compressedSize))
        let size = min(entry.size, prefix ?? .max)
        switch entry.method {
        case 0: return raw.prefix(size)
        case 8: return try inflate(raw, size: size)
        default: throw ZipError.unsupported(entry.method)
        }
    }

    private func inflate(_ raw: Data, size: Int) throws -> Data {
        if size == 0 { return Data() }
        var out = Data(count: size)
        let written = out.withUnsafeMutableBytes { dst in
            raw.withUnsafeBytes { src in
                compression_decode_buffer(
                    dst.bindMemory(to: UInt8.self).baseAddress!, size,
                    src.bindMemory(to: UInt8.self).baseAddress!, raw.count,
                    nil, COMPRESSION_ZLIB)
            }
        }
        guard written == size else { throw ZipError.corrupt }
        return out
    }
}

public enum ZipError: Error {
    case notZip, corrupt, missing(String), unsupported(UInt16)
}

extension Data {
    func u16(_ i: Int) -> UInt16 { UInt16(self[startIndex + i]) | UInt16(self[startIndex + i + 1]) << 8 }
    func u32(_ i: Int) -> UInt32 { UInt32(u16(i)) | UInt32(u16(i + 2)) << 16 }
    func u64(_ i: Int) -> UInt64 { UInt64(u32(i)) | UInt64(u32(i + 4)) << 32 }

    func lastIndex(ofSignature sig: UInt32, searchBack: Int) -> Int? {
        guard count >= 22 else { return nil }
        var i = count - 22
        let floor = Swift.max(0, count - searchBack)
        while i >= floor {
            if u32(i) == sig { return i }
            i -= 1
        }
        return nil
    }
}
