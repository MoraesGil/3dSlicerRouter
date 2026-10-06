import simd

/// Pintura multicolor por triângulo (`paint_color` no Bambu/Orca, `slic3rpe:mmu_segmentation` no Prusa).
///
/// Porte de `TriangleSelector::deserialize` + `perform_split` (BambuStudio v02.07.01.62) e de
/// `FacetsAnnotation::set_triangle_from_string`: os dígitos hex são lidos do fim para o começo e cada
/// um é um nibble. Nó: bits 0-1 = lados divididos (0 = folha); folha: bits 2-3 = estado, com `0b11`
/// estendendo para `3 + próximos nibbles`; nó dividido: bits 2-3 = lado especial e os filhos vêm em
/// ordem reversa. Estado 0 = cor da peça; estado k = filamento k.
public enum PaintDecoder {
    /// Chama `leaf` para cada triângulo final da subdivisão.
    public static func decode(_ code: Substring, _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>,
                              leaf: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>, Int) -> Void) {
        var reader = Reader(code.utf8)
        node(&reader, a, b, c, depth: 0, leaf: leaf)
    }

    struct Reader {
        let digits: [UInt8]
        var position: Int
        init<S: Sequence>(_ chars: S) where S.Element == UInt8 {
            digits = Array(chars)
            position = digits.count - 1
        }
        mutating func next() -> Int? {
            while position >= 0 {
                let ch = digits[position]
                position -= 1
                switch ch {
                case 48...57: return Int(ch - 48)          // 0-9
                case 65...70: return Int(ch - 55)          // A-F
                case 97...102: return Int(ch - 87)         // a-f (tolerância)
                default: continue
                }
            }
            return nil
        }
    }

    static func node(_ r: inout Reader, _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, depth: Int,
                     leaf: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>, Int) -> Void) {
        guard depth < 32, let code = r.next() else { return }
        let split = code & 0b11
        if split == 0 {
            var state = code >> 2
            if code & 0b1100 == 0b1100 {
                var extra = 0
                var next = r.next() ?? 0
                while next == 0b1111 { extra += 1; next = r.next() ?? 0 }
                state = next + 15 * extra + 3
            }
            leaf(a, b, c, state)
            return
        }
        let special = code >> 2
        let t = [a, b, c]
        let v0 = t[special % 3], v1 = t[(special + 1) % 3], v2 = t[(special + 2) % 3]
        @inline(__always) func mid(_ p: SIMD3<Float>, _ q: SIMD3<Float>) -> SIMD3<Float> { (p + q) * 0.5 }
        let children: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)]
        switch split {
        case 1:
            let m = mid(v1, v2)
            children = [(v0, v1, m), (m, v2, v0)]
        case 2:
            let m01 = mid(v0, v1), m02 = mid(v0, v2)
            children = [(v0, m01, m02), (m01, v1, m02), (v1, v2, m02)]
        default:
            let m01 = mid(v0, v1), m12 = mid(v1, v2), m20 = mid(v2, v0)
            children = [(v0, m01, m20), (m01, v1, m12), (m12, v2, m20), (m01, m12, m20)]
        }
        // Serializados do último filho para o primeiro.
        for child in children.reversed() {
            node(&r, child.0, child.1, child.2, depth: depth + 1, leaf: leaf)
        }
    }
}
