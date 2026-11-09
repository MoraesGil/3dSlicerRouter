import AppKit
import simd
import XCTest

final class RouterTests: XCTestCase {
    func testBackgroundAgentMigratesToOneFreshRegistrationIdentity() throws {
        let app = Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("3dSlicerRouter.app")
        let folder = app.appendingPathComponent("Contents/Library/LaunchAgents")
        let current = "com.moraesdev.3dslicerrouter.previews.v2.plist"
        let ownPlists = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { $0.hasPrefix("com.moraesdev.3dslicerrouter.") && $0.hasSuffix(".plist") }.sorted()
        XCTAssertEqual(ownPlists, [current], "Ship only the new registration identity; old per-item requirements can retain a previous ad-hoc CDHash")
        let plist = folder.appendingPathComponent(current)
        guard FileManager.default.fileExists(atPath: plist.path) else { return }
        let values = try PropertyListSerialization.propertyList(from: Data(contentsOf: plist), format: nil) as! [String: Any]
        XCTAssertEqual(values["Label"] as? String, "com.moraesdev.3dslicerrouter.previews.v2")
        XCTAssertEqual(values["BundleProgram"] as? String, "Contents/Helpers/3dSlicerIndexer")
        XCTAssertEqual(values["ProgramArguments"] as? [String], ["3dSlicerIndexer"])
        XCTAssertEqual(values["StartInterval"] as? Int, 1800)
    }

    func testBackgroundAgentDoesNotLaunchTheFinderHandler() throws {
        let app = Bundle(for: Self.self).bundleURL.deletingLastPathComponent()
            .appendingPathComponent("3dSlicerRouter.app")
        let plist = app.appendingPathComponent("Contents/Library/LaunchAgents/\(Indexer.agentPlist)")
        let values = try PropertyListSerialization.propertyList(from: Data(contentsOf: plist), format: nil) as! [String: Any]
        let program = try XCTUnwrap(values["BundleProgram"] as? String)
        let worker = app.appendingPathComponent(program)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: worker.path))
        let process = Process()
        process.executableURL = worker
        process.arguments = ["--version"]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines),
                       "3dSlicerIndexer", "The agent must launch the headless helper directly")
    }

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
        XCTAssertEqual(decide("Snapmaker U1"), .open(officialOrca, reason: "regra Snapmaker"))
    }

    var officialOrca: SlicerApp {
        SlicerApp(bundleID: "com.orcaslicer.OrcaSlicer", path: "/Applications/OrcaSlicer.app", name: "OrcaSlicer")
    }

    func testUnknownPrinterUsesOfficialOrcaByDefault() {
        XCTAssertEqual(decide("Elegoo Centauri Carbon"), .open(officialOrca, reason: "regra Elegoo"))
    }

    func testBothOrcaApplicationsCanBeChosenAndRememberedSeparately() throws {
        XCTAssertTrue(SlicerApp.known.contains(officialOrca))
        XCTAssertTrue(SlicerApp.known.contains(.snapmakerOrca))
        try withTempDirectory { directory in
            let store = Store(directory: directory.appendingPathComponent("store"))
            for (index, app) in [officialOrca, .snapmakerOrca].enumerated() {
                let file = directory.appendingPathComponent("choice-\(index).3mf")
                try Data("synthetic".utf8).write(to: file)
                let choice = FileRecord(uuid: "choice-\(index)", printerModel: "Snapmaker U1", app: app,
                                        override: true, settingsHash: nil)
                store.save(choice, for: file, reason: "test")
                XCTAssertEqual(FileRecord.read(from: file)?.app, app)
                XCTAssertEqual(decide("Snapmaker U1", store.record(for: file)), .open(app, reason: "lembrado"))
                FileRecord.remove(from: file)
                XCTAssertEqual(store.record(for: file)?.app, app, "SQLite must preserve the exact app after a slicer replaces the file")
            }
        }
    }

    func testLearnedModelMapping() {
        var m = Mappings()
        m.byModel["Prusa MK4"] = .snapmakerOrca
        XCTAssertEqual(decide("Prusa MK4", mappings: m), .open(.snapmakerOrca, reason: "regra Prusa"))
    }

    func testPrusaOpensOfficialOrca() {
        for model in ["Prusa MK4", "Original Prusa MK4S", "Original Prusa i3 MK3S", "prusa XL"] {
            XCTAssertEqual(decide(model), .open(officialOrca, reason: "regra Prusa"))
        }
        XCTAssertEqual(decide("Prusa MK4", option: true), .ask(.manual, suggested: officialOrca))
    }

    func testNoPrinterAsksUnlessTheOwnerAlreadyChose() {
        XCTAssertEqual(decide(nil), .ask(.noPrinter, suggested: nil))
        XCTAssertEqual(decide(nil, record(nil, officialOrca)), .ask(.noPrinter, suggested: nil),
                       "An old automatic fallback must not suppress the new chooser")
        XCTAssertEqual(decide(nil, record(nil, .bambuStudio, override: true)),
                       .open(.bambuStudio, reason: "lembrado (sem impressora)"))
    }

    func testSlicerDiscoveryListsOnlyExecutableInstallationsAndRefreshesAfterRemoval() throws {
        try withTempDirectory { directory in
            let apps = directory.resolvingSymlinksInPath().appendingPathComponent("Applications")
            let orca = try slicerBundle(in: apps, name: "OrcaSlicer", id: "com.orcaslicer.OrcaSlicer")
            let bambu = try slicerBundle(in: apps, name: "BambuStudio", id: "com.bambulab.bambu-studio")
            let prusa = try slicerBundle(in: apps.appendingPathComponent("3D"), name: "PrusaSlicer", id: "test.prusa")
            _ = try slicerBundle(in: apps, name: "TextEditor", id: "test.editor")
            let incomplete = try slicerBundle(in: apps, name: "SuperSlicer", id: "test.incomplete")
            try FileManager.default.removeItem(at: incomplete.appendingPathComponent("Contents/MacOS/slicer"))
            let stale = SlicerApp(bundleID: "test.removed", path: apps.appendingPathComponent("Missing.app").path, name: "Removed")
            let installed = SlicerApp.installed(directories: [apps], registeredURLs: [], suggested: stale)
            XCTAssertEqual(installed.map(\.bundleID), ["com.orcaslicer.OrcaSlicer", "com.bambulab.bambu-studio", "test.prusa"])
            XCTAssertEqual(installed.map { URL(fileURLWithPath: $0.path).resolvingSymlinksInPath().path },
                           [orca, bambu, prusa].map { $0.resolvingSymlinksInPath().path })
            try FileManager.default.removeItem(at: prusa)
            XCTAssertEqual(SlicerApp.installed(directories: [apps], registeredURLs: [prusa]).map(\.bundleID),
                           ["com.orcaslicer.OrcaSlicer", "com.bambulab.bambu-studio"])
        }
    }

    func testDiscoveryFindsRenamedAppsAndSymlinksAndKeepsInstalledSuggestionFirst() throws {
        try withTempDirectory { directory in
            let renamed = try slicerBundle(in: directory, name: "Renamed", id: "com.orcaslicer.OrcaSlicer")
            let runtime = try slicerBundle(in: directory.appendingPathComponent("runtime"), name: "Snapmaker Orca", id: "com.snapmaker.snapmaker-orca")
            let apps = directory.appendingPathComponent("Applications")
            try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
            let link = apps.appendingPathComponent("Snapmaker Orca.app")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: runtime)
            let suggestion = SlicerApp(bundleID: "com.snapmaker.snapmaker-orca", path: link.path, name: "Snapmaker Orca")
            let installed = SlicerApp.installed(directories: [apps], registeredURLs: [renamed, link], suggested: suggestion)
            XCTAssertEqual(installed.map(\.bundleID), ["com.snapmaker.snapmaker-orca", "com.orcaslicer.OrcaSlicer"])
            XCTAssertEqual(installed.first?.path, link.path)
            XCTAssertEqual(installed.last?.path, renamed.path)
            try FileManager.default.removeItem(at: runtime)
            XCTAssertEqual(SlicerApp.installed(directories: [apps], registeredURLs: [link, renamed], suggested: suggestion).map(\.bundleID),
                           ["com.orcaslicer.OrcaSlicer"], "A stale registration or dangling symlink is not an installation")
        }
    }

    func slicerBundle(in directory: URL, name: String, id: String) throws -> URL {
        let app = directory.appendingPathComponent(name + ".app")
        let macos = app.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": id, "CFBundleName": name,
                                    "CFBundleExecutable": "slicer", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        let executable = macos.appendingPathComponent("slicer")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return app
    }

    func testSamePrinterKeepsRememberedOverride() {
        // U1 aberto à mão no Bambu Studio continua indo para o Bambu enquanto a impressora não mudar.
        XCTAssertEqual(decide("Snapmaker U1", record("Snapmaker U1", .bambuStudio, override: true)),
                       .open(.bambuStudio, reason: "lembrado"))
        // Changing the default must also preserve previous automatic Snapmaker decisions.
        XCTAssertEqual(decide("Snapmaker U1", record("Snapmaker U1", .snapmakerOrca)),
                       .open(.snapmakerOrca, reason: "lembrado"))
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
                       .ask(.printerChanged(from: "Bambu Lab A1", to: "Snapmaker U1"), suggested: officialOrca))
    }

    func testOptionAlwaysAsks() {
        XCTAssertEqual(decide("Bambu Lab A1", record("Bambu Lab A1", .bambuStudio), option: true),
                       .ask(.manual, suggested: .bambuStudio))
    }

    func testExpectedAppFollowsPrinterChange() {
        let m = Mappings()
        // Escolha manual vale enquanto a impressora não muda.
        XCTAssertEqual(Router.expectedApp(info: info("Snapmaker U1"), record: record("Snapmaker U1", .bambuStudio, override: true), mappings: m), .bambuStudio)
        // Retargeted para A1: o ícone já mostra o Bambu Studio.
        XCTAssertEqual(Router.expectedApp(info: info("Bambu Lab A1"), record: record("Snapmaker U1", .snapmakerOrca), mappings: m), .bambuStudio)
        // Mudou para Snapmaker: o router vai perguntar, o ícone mostra a sugestão.
        XCTAssertEqual(Router.expectedApp(info: info("Snapmaker U1"), record: record("Bambu Lab A1", .bambuStudio), mappings: m), officialOrca)
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

    func testDetectsOfficialOrcaProjectWithoutConfusingTheSnapmakerFork() throws {
        try withTempDirectory { tmp in
            let file = tmp.appendingPathComponent("synthetic.3mf")
            let session = tmp.appendingPathComponent("orcaslicer_model/Sun_Nov_08/10_00_00#444#1")
            try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
            try file.path.write(to: session.appendingPathComponent("origin.txt"), atomically: true, encoding: .utf8)
            let found = OpenProjects.find(file, tmp: tmp) { _ in .init(bundleID: self.officialOrca.bundleID, launched: nil) }
            XCTAssertEqual(found, OpenProject(pid: 444, bundleID: officialOrca.bundleID, origin: file.path, dirty: false))
            XCTAssertNil(OpenProjects.find(file, tmp: tmp) { _ in .init(bundleID: SlicerApp.snapmakerOrca.bundleID, launched: nil) })
        }
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
            ("snapmaker-u1-four-colors.3mf", .open(officialOrca, reason: "regra Snapmaker")),
            ("unknown-printer-prusa-mk4s.3mf", .open(officialOrca, reason: "regra Prusa")),
            ("no-printer-declared.3mf", .ask(.noPrinter, suggested: nil)),
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

    func testQuickLookExtensionsCarrySandboxEntitlements() throws {
        let app = Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("3dSlicerRouter.app")
        for name in ["Thumbnail", "Preview"] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            process.arguments = ["-d", "--entitlements", ":-", app.appendingPathComponent("Contents/PlugIns/SlicerRouter\(name).appex").path]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0)
            XCTAssertFalse(data.isEmpty, "\(name) must carry signed entitlements, not just an entitlements file in source")
            if data.isEmpty { continue }
            let values = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
            XCTAssertEqual(values["com.apple.security.app-sandbox"] as? Bool, true)
            XCTAssertEqual(values["com.apple.security.files.user-selected.read-only"] as? Bool, true)
        }
    }

    func testEmbeddedThumbnailRepresentsFirstPlate() throws {
        try withArchive(files: [
            "Metadata/model_settings.config": Data("<config><plate/><plate/></config>".utf8),
            "Metadata/plate_1.png": Data([1]),
            "Auxiliaries/.thumbnails/thumbnail_middle.png": Data([2]),
        ]) { url in
            XCTAssertEqual(try ThreeMF.info(url: url).embeddedThumbnail, "Metadata/plate_1.png")
        }
        try withArchive(files: [
            "Metadata/model_settings.config": Data("<config><plate></plate><plate></plate></config>".utf8),
            "Auxiliaries/.thumbnails/thumbnail_middle.png": Data([2]),
        ]) { url in
            XCTAssertNil(try ThreeMF.info(url: url).embeddedThumbnail, "A multi-plate overview cannot stand in for the first plate")
        }
    }

    func testSameSizeSubsecondSaveInvalidatesPreviewName() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("preview-\(UUID().uuidString).3mf")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data([1]).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_700_000_000.1)], ofItemAtPath: url.path)
        let before = try XCTUnwrap(PreviewCache.name(for: URL(fileURLWithPath: url.path)))
        try Data([2]).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_700_000_000.2)], ofItemAtPath: url.path)
        XCTAssertNotEqual(PreviewCache.name(for: URL(fileURLWithPath: url.path)), before)
    }

    func testStaticPreviewSelectsTheFirstPlatesActualInstance() throws {
        // Both build items share an object ID. Plate 1 contains its SECOND instance.
        let first = #"<item objectid="1" transform="1 0 0 0 1 0 0 0 1 20 20 0"/>"#
        let other = #"<item objectid="1" transform="1 0 0 0 1 0 0 0 1 500 20 0"/>"#
        let instance: (Int) -> String = { #"<model_instance><metadata key="object_id" value="1"/><metadata key="instance_id" value="\#($0)"/></model_instance>"# }
        let multiple = "<config><plate>\(instance(1))</plate><plate>\(instance(0))</plate></config>"
        let single = "<config><plate>\(instance(0))</plate></config>"
        try withArchive(files: sceneFiles(build: other + first, settings: multiple)) { multi in
            try withArchive(files: sceneFiles(build: first, settings: single)) { expected in
                let info = try ThreeMF.info(url: multi)
                let scene = try PrintScene.load(url: multi, info: info)
                XCTAssertEqual(scene.beds.count, 2, "The rich Space scene must retain every plate")
                XCTAssertGreaterThan(scene.boundsMax.x, 500)
                let firstScene = try PrintScene.load(url: multi, info: info, firstPlateOnly: true)
                XCTAssertEqual(firstScene.beds.count, 1)
                XCTAssertEqual(firstScene.triangleCount, 1)
                XCTAssertEqual(firstScene.boundsMax.x, 50, "Plate 1 contains the second build instance at x=20, not the one at x=500")
                let size = CGSize(width: 256, height: 256)
                let expectedPNG = try PreviewRenderer.png(url: expected, info: ThreeMF.info(url: expected), size: size)
                let actualPNG = try PreviewRenderer.png(url: multi, info: info, size: size)
                XCTAssertLessThan(try pixelDifference(actualPNG, expectedPNG), 0.5, "Allow subpixel raster jitter, not other plates")
                let panorama = try PreviewRenderer.encode(PreviewRenderer.render(url: multi, info: info, size: size))
                XCTAssertGreaterThan(try pixelDifference(panorama, expectedPNG), 1, "The comparison must reject the old all-plate image")
            }
        }
    }

    func testCurrentIndexedGeometryOverridesStaleEmbeddedImage() throws {
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
        var files = sceneFiles(build: #"<item objectid="1"/>"#, settings: "<config><plate></plate></config>")
        files["Metadata/plate_1.png"] = png
        try withArchive(files: files) { url in
            let directory = url.deletingLastPathComponent().appendingPathComponent("previews")
            let info = try ThreeMF.info(url: url)
            let fresh = try PreviewRenderer.png(url: url, info: info, size: CGSize(width: 128, height: 128))
            XCTAssertNotNil(PreviewCache.store(fresh, for: url, directory: directory))
            let image = try PreviewRenderer.thumbnail(url: url, info: info, size: CGSize(width: 256, height: 256), cacheDirectory: directory)
            XCTAssertEqual(image.width, 128, "Use the current indexed geometry instead of the old embedded 1px image")
        }
    }

    func testColdThumbnailRendersCurrentGeometryBeforeStaleEmbeddedImage() throws {
        let size = CGSize(width: 128, height: 128)
        var files = sceneFiles(build: #"<item objectid="1"/>"#, settings: "<config/>")
        let model = String(decoding: files["3D/3dmodel.model"]!, as: UTF8.self)
            .replacingOccurrences(of: "30", with: "160")
        files["3D/3dmodel.model"] = Data(model.utf8)
        try withArchive(files: files) { original in
            let oldBluePNG = try PreviewRenderer.png(url: original, info: ThreeMF.info(url: original), size: size)
            var changed = files
            let config = String(decoding: changed["Metadata/project_settings.config"]!, as: UTF8.self)
                .replacingOccurrences(of: "#2F6FED", with: "#EE6B24")
            changed["Metadata/project_settings.config"] = Data(config.utf8)
            changed["Metadata/plate_1.png"] = oldBluePNG
            try withArchive(files: changed) { current in
                let info = try ThreeMF.info(url: current)
                let freshOrangePNG = try PreviewRenderer.png(url: current, info: info, size: size)
                let emptyCache = current.deletingLastPathComponent().appendingPathComponent("no-indexed-cache")
                let actual = try PreviewRenderer.encode(PreviewRenderer.thumbnail(url: current, info: info, size: size, cacheDirectory: emptyCache))
                XCTAssertGreaterThan(try pixelDifference(oldBluePNG, freshOrangePNG), 1, "The fixture must distinguish old blue from current orange geometry")
                XCTAssertLessThan(try pixelDifference(actual, freshOrangePNG), 0.5, "Never seed the system cache with an old embedded image while current geometry can render")
            }
        }
    }

    func testUnrenderableGeometryCanUseFirstPlateEmbeddedFallback() throws {
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
        try withArchive(files: ["Metadata/plate_1.png": png]) { url in
            let image = try PreviewRenderer.thumbnail(url: url, info: ThreeMF.info(url: url), size: CGSize(width: 128, height: 128),
                                                       cacheDirectory: url.deletingLastPathComponent().appendingPathComponent("no-indexed-cache"))
            XCTAssertEqual(image.width, 1, "An unavailable model may fall back to the saved first-plate image")
        }
    }

    func testCatalogRetriesFailedAndMissingPreviews() throws {
        try withArchive(files: sceneFiles(build: #"<item objectid="1"/>"#, settings: "<config/>")) { url in
            let directory = url.deletingLastPathComponent()
            let store = Store(directory: directory.appendingPathComponent("database"))
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = try XCTUnwrap(values.fileSize), modified = try XCTUnwrap(values.contentModificationDate)
            var entry = Indexer.Entry(path: url.path, kind: "3mf", size: size, modified: modified)
            entry.error = "render failed"
            store.upsertCatalog(entry)
            XCTAssertFalse(store.isCatalogued(url.path, size: size, modified: modified))
            entry.error = nil
            entry.preview = PreviewCache.store(Data([1]), for: url, directory: directory.appendingPathComponent("previews"))?.path
            store.upsertCatalog(entry)
            XCTAssertTrue(store.isCatalogued(url.path, size: size, modified: modified))
            try FileManager.default.removeItem(atPath: XCTUnwrap(entry.preview))
            XCTAssertFalse(store.isCatalogued(url.path, size: size, modified: modified))
        }
    }

    func testCatalogDistinguishesSubsecondRevisions() throws {
        try withArchive(files: ["data": Data([1])]) { url in
            let store = Store(directory: url.deletingLastPathComponent().appendingPathComponent("database"))
            let first = Date(timeIntervalSince1970: 1_700_000_000.1)
            let second = Date(timeIntervalSince1970: 1_700_000_000.2)
            let entry = Indexer.Entry(path: url.path, kind: "3mf", size: 1, modified: first)
            store.upsertCatalog(entry)
            XCTAssertFalse(store.isCatalogued(url.path, size: 1, modified: second))
        }
    }

    func testIndexerRendersCurrentGeometryEvenWithEmbeddedImage() throws {
        var files = sceneFiles(build: #"<item objectid="1"/>"#, settings: "<config/>")
        files["Metadata/plate_1.png"] = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
        try withArchive(files: files) { url in
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let result = Indexer.index(url, size: try XCTUnwrap(values.fileSize), modified: try XCTUnwrap(values.contentModificationDate),
                                       cacheDirectory: url.deletingLastPathComponent().appendingPathComponent("previews"))
            XCTAssertNil(result.error)
            XCTAssertTrue(result.embedded)
            XCTAssertTrue(result.rendered, "The idle pass must regenerate current geometry even if the slicer image is old")
            let png = try Data(contentsOf: URL(fileURLWithPath: XCTUnwrap(result.preview)))
            XCTAssertEqual(PreviewRenderer.decode(png)?.width, 1024)
        }
    }

    func testIndexerRejectsSaveWhileReadingSourceMetadata() throws {
        let original = sceneFiles(build: #"<item objectid="1"/>"#, settings: "<config/>")
        var changed = original
        changed["Metadata/project_settings.config"] = Data(##"{"printer_model":"Snapmaker U1","filament_colour":["#EE6B24"]}"##.utf8)
        try withArchive(files: original) { url in
            try withArchive(files: changed) { replacement in
                let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                let cache = url.deletingLastPathComponent().appendingPathComponent("previews")
                let entry = Indexer.index(url, size: try XCTUnwrap(values.fileSize),
                                          modified: try XCTUnwrap(values.contentModificationDate), cacheDirectory: cache) { source in
                    let oldInfo = try ThreeMF.info(url: source)
                    try Data(contentsOf: replacement).write(to: source, options: .atomic)
                    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_800_000_000)], ofItemAtPath: source.path)
                    return oldInfo
                }
                XCTAssertEqual(entry.error, "changedDuringRender")
                XCTAssertFalse(entry.rendered)
                XCTAssertNil(PreviewCache.cachedURL(for: url, directory: cache))
            }
        }
    }

    func testCacheRejectsAResultFromBeforeAConcurrentSave() throws {
        try withArchive(files: ["data": Data([1])]) { url in
            let old = try XCTUnwrap(PreviewCache.name(for: url))
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_700_000_000.5)], ofItemAtPath: url.path)
            let cache = url.deletingLastPathComponent().appendingPathComponent("previews")
            XCTAssertNil(PreviewCache.store(Data([1]), for: url, directory: cache, expectedName: old))
            XCTAssertNil(PreviewCache.cachedURL(for: url, directory: cache))
        }
    }

    func sceneFiles(build: String, settings: String) -> [String: Data] {
        let model = """
        <model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
        <resources><object id="1" type="model"><mesh><vertices>
        <vertex x="0" y="0" z="0"/><vertex x="30" y="0" z="0"/><vertex x="0" y="30" z="30"/>
        </vertices><triangles><triangle v1="0" v2="1" v3="2"/></triangles></mesh></object></resources>
        <build>\(build)</build></model>
        """
        return ["3D/3dmodel.model": Data(model.utf8), "Metadata/model_settings.config": Data(settings.utf8),
                "Metadata/project_settings.config": Data(##"{"printer_model":"Snapmaker U1","filament_colour":["#2F6FED"]}"##.utf8)]
    }

    func pixelDifference(_ a: Data, _ b: Data) throws -> Double {
        let lhs = try XCTUnwrap(NSBitmapImageRep(data: a)), rhs = try XCTUnwrap(NSBitmapImageRep(data: b))
        XCTAssertEqual(lhs.pixelsWide, rhs.pixelsWide)
        XCTAssertEqual(lhs.pixelsHigh, rhs.pixelsHigh)
        XCTAssertEqual(lhs.samplesPerPixel, rhs.samplesPerPixel)
        let l = try XCTUnwrap(lhs.bitmapData), r = try XCTUnwrap(rhs.bitmapData)
        var total = 0
        for y in 0..<lhs.pixelsHigh {
            for x in 0..<(lhs.pixelsWide * lhs.samplesPerPixel) {
                total += abs(Int(l[y * lhs.bytesPerRow + x]) - Int(r[y * rhs.bytesPerRow + x]))
            }
        }
        return Double(total) / Double(lhs.pixelsWide * lhs.pixelsHigh * lhs.samplesPerPixel)
    }

    func withTempDirectory(body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("router-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    func withArchive(files: [String: Data], body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("router-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for (name, data) in files {
            let file = directory.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file)
        }
        let archive = directory.appendingPathComponent("fixture.3mf")
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.currentDirectoryURL = directory
        zip.arguments = ["-q", "-r", archive.path] + files.keys.sorted()
        try zip.run(); zip.waitUntilExit()
        XCTAssertEqual(zip.terminationStatus, 0)
        try body(archive)
    }
}
