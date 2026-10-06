import simd
import XCTest

final class RouterTests: XCTestCase {
    func info(_ model: String?) -> ThreeMFInfo {
        var i = ThreeMFInfo()
        i.printerModel = model
        return i
    }

    func record(_ model: String?, _ app: SlicerApp, override: Bool = false) -> FileRecord {
        FileRecord(uuid: "u", printerModel: model, app: app, override: override, settingsHash: nil)
    }

    func decide(_ model: String?, _ rec: FileRecord? = nil, option: Bool = false, mappings: Mappings = Mappings()) -> Decision {
        Router.decide(info: info(model), record: rec, mappings: mappings, optionHeld: option)
    }

    func testBrandRules() {
        XCTAssertEqual(decide("Bambu Lab A1"), .open(.bambuStudio, reason: "regra Bambu Lab"))
        XCTAssertEqual(decide("Bambu Lab H2C"), .open(.bambuStudio, reason: "regra Bambu Lab"))
        XCTAssertEqual(decide("Snapmaker U1"), .open(.snapmakerOrca, reason: "regra Snapmaker"))
    }

    func testUnknownPrinterAsks() {
        XCTAssertEqual(decide("Prusa MK4"), .ask(.unknownPrinter("Prusa MK4"), suggested: nil))
    }

    func testLearnedModelMapping() {
        var m = Mappings()
        m.byModel["Prusa MK4"] = .snapmakerOrca
        XCTAssertEqual(decide("Prusa MK4", mappings: m), .open(.snapmakerOrca, reason: "regra Prusa"))
    }

    func testNoPrinterClassifies() {
        XCTAssertEqual(decide(nil), .classify)
        XCTAssertEqual(decide(nil, record(nil, .bambuStudio)), .open(.bambuStudio, reason: "lembrado (sem impressora)"))
    }

    func testSamePrinterKeepsRememberedOverride() {
        // U1 aberto à mão no Bambu Studio continua indo para o Bambu enquanto a impressora não mudar.
        XCTAssertEqual(decide("Snapmaker U1", record("Snapmaker U1", .bambuStudio, override: true)),
                       .open(.bambuStudio, reason: "lembrado"))
    }

    func testBambuToBambuDoesNotAsk() {
        XCTAssertEqual(decide("Bambu Lab A1 mini", record("Bambu Lab A1", .bambuStudio)),
                       .open(.bambuStudio, reason: "mesma marca (Bambu Lab)"))
    }

    func testSnapmakerToA1OpensBambuDirectly() {
        XCTAssertEqual(decide("Bambu Lab A1", record("Snapmaker U1", .snapmakerOrca)),
                       .open(.bambuStudio, reason: "mudou para Bambu Lab A1"))
    }

    func testBambuToSnapmakerAsks() {
        XCTAssertEqual(decide("Snapmaker U1", record("Bambu Lab A1", .bambuStudio)),
                       .ask(.printerChanged(from: "Bambu Lab A1", to: "Snapmaker U1"), suggested: .snapmakerOrca))
    }

    func testOptionAlwaysAsks() {
        XCTAssertEqual(decide("Bambu Lab A1", record("Bambu Lab A1", .bambuStudio), option: true),
                       .ask(.manual, suggested: .bambuStudio))
    }

    func testFinderIconFollowsPrinterChange() {
        let m = Mappings()
        // Escolha manual vale enquanto a impressora não muda.
        XCTAssertEqual(Router.expectedApp(info: info("Snapmaker U1"), record: record("Snapmaker U1", .bambuStudio, override: true), mappings: m), .bambuStudio)
        // Retargeted para A1: o ícone já mostra o Bambu Studio.
        XCTAssertEqual(Router.expectedApp(info: info("Bambu Lab A1"), record: record("Snapmaker U1", .snapmakerOrca), mappings: m), .bambuStudio)
        // Mudou para Snapmaker: o router vai perguntar, o ícone mostra a sugestão.
        XCTAssertEqual(Router.expectedApp(info: info("Snapmaker U1"), record: record("Bambu Lab A1", .bambuStudio), mappings: m), .snapmakerOrca)
        XCTAssertNil(Router.expectedApp(info: info(nil), record: nil, mappings: m))
    }

    func testDetectsProjectAlreadyOpenFromSlicerBackup() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("op-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        func session(_ root: String, _ name: String, origin: String, dirty: Bool = false) throws {
            let dir = tmp.appendingPathComponent("\(root)/Sun_Oct_04/\(name)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try origin.write(to: dir.appendingPathComponent("origin.txt"), atomically: true, encoding: .utf8)
            if dirty { try Data().write(to: dir.appendingPathComponent(".3mf")) }
        }
        let file = tmp.appendingPathComponent("work/tray.3mf")
        try session("bamboo_model", "10_00_00#111#1", origin: file.path, dirty: true)
        try session("bamboo_model", "09_00_00#222#1", origin: file.path)              // processo morto
        try session("snapmaker_orca_model", "10_00_00#333#1", origin: "work/tray.3mf") // caminho relativo
        let alive: [Int32: OpenProjects.Process] = [
            111: .init(bundleID: "com.bambulab.bambu-studio", launched: nil),
            333: .init(bundleID: "com.snapmaker.snapmaker-orca", launched: nil),
        ]
        let found = OpenProjects.find(file, tmp: tmp) { alive[$0] }
        XCTAssertNotNil(found)
        XCTAssertTrue([111, 333].contains(found!.pid))
        XCTAssertEqual(OpenProjects.find(file, tmp: tmp) { $0 == 111 ? alive[111] : nil },
                       OpenProject(pid: 111, bundleID: "com.bambulab.bambu-studio", origin: file.path, dirty: true))
        XCTAssertNil(OpenProjects.find(file, tmp: tmp) { _ in nil })
        XCTAssertNil(OpenProjects.find(tmp.appendingPathComponent("other.3mf"), tmp: tmp) { alive[$0] })
        // PID com bundle errado (reciclado por outro app) não conta.
        XCTAssertNil(OpenProjects.find(file, tmp: tmp) { _ in .init(bundleID: "com.apple.TextEdit", launched: nil) })
    }

    func paintLeaves(_ code: String) -> [(centre: SIMD3<Float>, state: Int)] {
        var out: [(SIMD3<Float>, Int)] = []
        PaintDecoder.decode(code[...], SIMD3(0, 0, 0), SIMD3(2, 0, 0), SIMD3(0, 2, 0)) { a, b, c, s in
            out.append(((a + b + c) / 3, s))
        }
        return out
    }

    func testPaintLeafStates() {
        XCTAssertEqual(paintLeaves("8").map(\.state), [2])     // 0b1000: folha, filamento 2
        XCTAssertEqual(paintLeaves("1C").map(\.state), [4])    // 0b1100 estendido: 3 + 1
        XCTAssertEqual(paintLeaves("2FC").map(\.state), [20])  // 3 + 15 + 2
    }

    func testPaintSplitIntoFourChildrenInReverseOrder() {
        // Nibbles na ordem de leitura: 3 (divide 3 lados), filhos 3,2,1,0 = estados 1,0,2,1. Hex invertido.
        let leaves = paintLeaves("48043")
        XCTAssertEqual(leaves.count, 4)
        func state(near p: SIMD3<Float>) -> Int? {
            leaves.min(by: { simd_distance($0.centre, p) < simd_distance($1.centre, p) })?.state
        }
        XCTAssertEqual(state(near: SIMD3(0.3, 0.3, 0)), 1)   // filho 0: canto de a
        XCTAssertEqual(state(near: SIMD3(1.6, 0.2, 0)), 2)   // filho 1: canto de b
        XCTAssertEqual(state(near: SIMD3(0.2, 1.6, 0)), 0)   // filho 2: canto de c (cor da peça)
        XCTAssertEqual(state(near: SIMD3(0.67, 0.67, 0)), 1) // filho 3: central
    }

    func testGCodeMetadataAndToolpath() throws {
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
        let gcode = """
        ; generated by Snapmaker Orca 2.3.4
        ; thumbnail begin 1x1 \(png.count)
        ; \(png.base64EncodedString())
        ; thumbnail end
        G90
        M83
        T0
        G1 X10 Y10 Z0.2 F3000
        G1 X20 Y10 E0.5
        G1 X20 Y20 E0.5 ; comentário X99
        T1
        G0 X30 Y30
        G1 X40 Y30 E0.4
        G1 X50 Y30 E-0.8
        ; printer_model = Snapmaker U1
        ; filament_colour = #000000;#FECB03
        ; printable_area = 0x0,270x0,270x270,0x270
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("t-\(UUID().uuidString).gcode")
        try gcode.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let meta = try GCode.metadata(url: url)
        XCTAssertEqual(meta.thumbnail, png)
        XCTAssertEqual(meta.info.printerModel, "Snapmaker U1")
        XCTAssertEqual(meta.info.filamentColours, ["#000000", "#FECB03"])
        XCTAssertEqual(meta.info.bedMax, SIMD2(270, 270))

        let scene = try GCode.toolpath(url: url, info: meta.info)
        XCTAssertEqual(scene.lines["#000000"]?.count, 4)  // 2 segmentos extrudados em T0
        XCTAssertEqual(scene.lines["#FECB03"]?.count, 2)  // 1 em T1; retração e G0 não contam
        XCTAssertEqual(scene.lines["#000000"]?.last, SIMD3(20, 20, 0.2))
    }

    func testBedLayoutMatchesBambuGrid() {
        let beds = PrintScene.bedLayout(count: 4, min: SIMD2(0, 0), max: SIMD2(330, 320))
        XCTAssertEqual(beds.map(\.min), [SIMD2(0, 0), SIMD2(396, 0), SIMD2(0, -384), SIMD2(396, -384)])
    }

    func testTransformIsRowVector3MF() {
        let m = ModelFile.transform("1 0 0 0 1 0 0 0 1 10 20 30")
        XCTAssertEqual(m * SIMD4<Float>(1, 2, 3, 1), SIMD4(11, 22, 33, 1))
    }

    static let samples = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("samples")

    func sample(_ name: String) throws -> ThreeMFInfo {
        try ThreeMF.info(url: Self.samples.appendingPathComponent(name))
    }

    func testSamplesRouteAsDocumented() throws {
        let cases: [(String, Decision)] = [
            ("bambu-a1-keychain-tray.3mf", .open(.bambuStudio, reason: "regra Bambu Lab")),
            ("bambu-a1mini-calibration.3mf", .open(.bambuStudio, reason: "regra Bambu Lab")),
            ("bambu-h2d-four-plates.3mf", .open(.bambuStudio, reason: "regra Bambu Lab")),
            ("snapmaker-u1-four-colors.3mf", .open(.snapmakerOrca, reason: "regra Snapmaker")),
            ("unknown-printer-prusa-mk4s.3mf", .ask(.unknownPrinter("Original Prusa MK4S"), suggested: nil)),
            ("no-printer-declared.3mf", .classify),
        ]
        for (name, expected) in cases {
            let info = try sample(name)
            XCTAssertEqual(Router.decide(info: info, record: nil, mappings: Mappings(), optionHeld: false), expected, name)
        }
    }

    func testSampleMetadata() throws {
        let h2d = try sample("bambu-h2d-four-plates.3mf")
        XCTAssertEqual(h2d.plateCount, 4)
        XCTAssertEqual(h2d.bedMax, SIMD2(350, 320))
        XCTAssertNotNil(h2d.settingsHash)
        XCTAssertNil(h2d.embeddedThumbnail)
        XCTAssertEqual(try sample("snapmaker-u1-four-colors.3mf").filamentColours.count, 4)
        XCTAssertNil(try sample("no-printer-declared.3mf").settingsHash)
    }

    func testSceneLoadsEveryPlateAndColour() throws {
        let url = Self.samples.appendingPathComponent("bambu-h2d-four-plates.3mf")
        let scene = try PrintScene.load(url: url, info: ThreeMF.info(url: url))
        XCTAssertEqual(scene.beds.count, 4)
        XCTAssertEqual(Set(scene.meshes.keys), ["#2F6FED", "#F2F2F2"])
        XCTAssertGreaterThan(scene.triangleCount, 1000)
    }

    func testXattrRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("xattr-\(UUID().uuidString).3mf")
        try Data("x".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let rec = record("Snapmaker U1", .bambuStudio, override: true)
        XCTAssertTrue(rec.write(to: url))
        XCTAssertEqual(FileRecord.read(from: url)?.app, .bambuStudio)
        FileRecord.remove(from: url)
        XCTAssertNil(FileRecord.read(from: url))
    }
}
