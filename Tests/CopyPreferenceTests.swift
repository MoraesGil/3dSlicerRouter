import Foundation
import XCTest

final class CopyPreferenceTests: XCTestCase {
    private func fixture(_ body: (URL, URL, Store) throws -> Void) throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("copy-choice-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("A.gcode"), b = dir.appendingPathComponent("B.gcode")
        try Data("; synthetic\n".utf8).write(to: a)
        try body(a, b, Store(directory: dir.appendingPathComponent("db")))
    }
    private func choice(_ id: String, _ app: SlicerApp) -> FileRecord {
        FileRecord(uuid: id, printerModel: nil, app: app, override: true, settingsHash: nil)
    }
    func testCopyInheritsThenSaveForksAndKeepsBothChoices() throws {
        try fixture { a, b, store in
            store.save(choice("original", .orcaSlicer), for: a, reason: "test")
            try FileManager.default.copyItem(at: a, to: b)
            let inherited = try XCTUnwrap(store.record(for: b))
            XCTAssertEqual(inherited.app, .orcaSlicer)
            store.save(choice(inherited.uuid, .bambuStudio), for: b, reason: "test")
            let first = try XCTUnwrap(store.record(for: a)), second = try XCTUnwrap(store.record(for: b))
            XCTAssertEqual(first.app, .orcaSlicer)
            XCTAssertEqual(second.app, .bambuStudio)
            XCTAssertNotEqual(first.uuid, second.uuid)
            XCTAssertEqual(FileRecord.read(from: b)?.uuid, second.uuid)
            XCTAssertEqual(RoutingPreferences.read(for: a, directory: a.deletingLastPathComponent().appendingPathComponent("db")).record?.app, .orcaSlicer)
            XCTAssertEqual(RoutingPreferences.read(for: b, directory: a.deletingLastPathComponent().appendingPathComponent("db")).record?.app, .bambuStudio)
        }
    }
    func testForgetEitherCopyPreservesOther() throws {
        for forgetFirst in [true, false] {
            try fixture { a, b, store in
                store.save(choice("original", .orcaSlicer), for: a, reason: "test")
                try FileManager.default.copyItem(at: a, to: b)
                store.save(choice(try XCTUnwrap(store.record(for: b)).uuid, .bambuStudio), for: b, reason: "test")
                store.forget(forgetFirst ? a : b)
                XCTAssertNil(store.record(for: forgetFirst ? a : b))
                XCTAssertEqual(store.record(for: forgetFirst ? b : a)?.app, forgetFirst ? .bambuStudio : .orcaSlicer)
            }
        }
    }
    func testRenameRetainsChoiceAndMissingXattrUsesPath() throws {
        try fixture { a, b, store in
            store.save(choice("original", .orcaSlicer), for: a, reason: "test")
            try FileManager.default.moveItem(at: a, to: b)
            let moved = try XCTUnwrap(store.record(for: b))
            XCTAssertEqual(moved.uuid, "original")
            store.save(moved, for: b, reason: "test")
            let newID = try XCTUnwrap(store.record(for: b)?.uuid)
            XCTAssertNotEqual(newID, "original")
            FileRecord.remove(from: b)
            XCTAssertEqual(store.record(for: b)?.app, .orcaSlicer)
            XCTAssertEqual(store.record(for: b)?.uuid, newID)
        }
    }
    func testUnavailableOriginalKeepsItsChoiceAfterCopyChanges() throws {
        try fixture { a, b, store in
            let source = a.deletingLastPathComponent().appendingPathComponent("source")
            let hidden = a.deletingLastPathComponent().appendingPathComponent("offline")
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            let original = source.appendingPathComponent("A.gcode")
            try FileManager.default.moveItem(at: a, to: original)
            store.save(choice("original", .orcaSlicer), for: original, reason: "test")
            try FileManager.default.copyItem(at: original, to: b)
            try FileManager.default.moveItem(at: source, to: hidden)
            let inherited = try XCTUnwrap(store.record(for: b))
            XCTAssertEqual(inherited.app, .orcaSlicer)
            store.save(choice(inherited.uuid, .bambuStudio), for: b, reason: "test")
            try FileManager.default.moveItem(at: hidden, to: source)
            XCTAssertEqual(store.record(for: original)?.app, .orcaSlicer)
            XCTAssertEqual(store.record(for: b)?.app, .bambuStudio)
            XCTAssertNotEqual(store.record(for: original)?.uuid, store.record(for: b)?.uuid)
        }
    }

    func testRenameBackUsesCurrentLocalUUIDInsteadOfStalePath() throws {
        try fixture { a, b, store in
            let database = a.deletingLastPathComponent().appendingPathComponent("db")
            store.save(choice("original", .orcaSlicer), for: a, reason: "test")
            try FileManager.default.moveItem(at: a, to: b)
            let inherited = try XCTUnwrap(store.record(for: b))
            store.save(choice(inherited.uuid, .bambuStudio), for: b, reason: "test")
            let current = try XCTUnwrap(store.record(for: b))
            try FileManager.default.moveItem(at: b, to: a)
            XCTAssertEqual(store.record(for: a)?.app, .bambuStudio)
            XCTAssertEqual(store.record(for: a)?.uuid, current.uuid)
            XCTAssertEqual(RoutingPreferences.read(for: a, directory: database).record?.app, .bambuStudio)
            XCTAssertEqual(RoutingPreferences.read(for: a, directory: database).record?.uuid, current.uuid)
        }
    }

    func testUnknownPortableUUIDFallsBackToLocalPath() throws {
        try fixture { a, _, store in
            let database = a.deletingLastPathComponent().appendingPathComponent("db")
            store.save(choice("local", .orcaSlicer), for: a, reason: "test")
            XCTAssertTrue(choice("foreign", .bambuStudio).write(to: a))
            XCTAssertEqual(store.record(for: a)?.app, .orcaSlicer)
            XCTAssertEqual(RoutingPreferences.read(for: a, directory: database).record?.app, .orcaSlicer)
            FileRecord.remove(from: a)
            XCTAssertEqual(store.record(for: a)?.app, .orcaSlicer)
            XCTAssertEqual(RoutingPreferences.read(for: a, directory: database).record?.app, .orcaSlicer)
        }
    }

}
