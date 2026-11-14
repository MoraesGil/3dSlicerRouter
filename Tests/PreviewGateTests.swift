import Foundation
import XCTest

final class PreviewGateTests: XCTestCase {
    func testAdmissionBoundaries() {
        func permits(_ cpu: Double?, _ gpu: Double?, idle: Double = 0, available: Double = 0.25,
                     thermal: ProcessInfo.ThermalState = .nominal, lowPower: Bool = false) -> Bool {
            PreviewGate.permits(cpu: cpu, gpu: gpu, idle: idle, available: available, thermal: thermal, lowPower: lowPower)
        }
        XCTAssertTrue(permits(29.9, 29.9))
        XCTAssertFalse(permits(30, 0, idle: 3600))
        XCTAssertFalse(permits(0, 30, idle: 3600))
        XCTAssertFalse(permits(nil, 0, idle: 3600))
        XCTAssertFalse(permits(0, nil, idle: 179))
        XCTAssertTrue(permits(0, nil, idle: 180))
        XCTAssertFalse(permits(0, 0, available: 0.249))
        XCTAssertFalse(permits(0, 0, thermal: .serious))
        XCTAssertFalse(permits(0, 0, lowPower: true))
    }

    func testSlotRejectsOverlapAndReleasesAfterInterruption() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data().write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertThrowsError(try PreviewGate.withSlot(at: file) {
            XCTAssertThrowsError(try PreviewGate.withSlot(at: file) { XCTFail("Overlapping render") })
            throw PreviewGate.Busy()
        })
        XCTAssertEqual(try PreviewGate.withSlot(at: file) { 42 }, 42)
    }

    func testMeshParserPropagatesInterruption() {
        let vertices = String(repeating: "<vertex x=\"0\" y=\"0\" z=\"0\"/>", count: 8192)
        let data = Data("<object id=\"1\"><mesh><vertices>\(vertices)</vertices></mesh></object>".utf8)
        XCTAssertThrowsError(try ModelFile(data: data) { throw PreviewGate.Busy() }) {
            XCTAssertTrue($0 is PreviewGate.Busy)
        }
    }
}
