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
