import Foundation
import XCTest
@testable import ProbeCore

final class MarkerStoreTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChainProbeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return directory
    }

    func testRestartAndRepeatedCreationKeepOriginalMarker() throws {
        let directory = try temporaryDirectory()
        let store = MarkerStore(directory: directory)
        XCTAssertNil(try store.load())
        let created = try store.createIfMissing(now: Date(timeIntervalSince1970: 1_700_000_000.75))
        let originalBytes = try Data(contentsOf: store.fileURL)
        let reopened = MarkerStore(directory: directory)
        XCTAssertEqual(try reopened.load(), created)
        XCTAssertEqual(try reopened.createIfMissing(now: Date(timeIntervalSince1970: 1_800_000_000)), created)
        XCTAssertEqual(try Data(contentsOf: store.fileURL), originalBytes)
    }

    func testCorruptFileIsNeverReplacedWithNewMarker() throws {
        let store = MarkerStore(directory: try temporaryDirectory())
        let corrupt = Data("truncated-json{".utf8)
        try corrupt.write(to: store.fileURL)
        XCTAssertThrowsError(try store.load())
        XCTAssertThrowsError(try store.createIfMissing())
        XCTAssertEqual(try Data(contentsOf: store.fileURL), corrupt)
    }

    func testUnknownSchemaIsPreservedAndRejected() throws {
        let store = MarkerStore(directory: try temporaryDirectory())
        let data = Data("""
        {"schemaVersion":99,"id":"12345678-1234-4234-8234-123456789012","createdAt":"2026-01-01T00:00:00Z"}
        """.utf8)
        try data.write(to: store.fileURL)
        XCTAssertThrowsError(try store.createIfMissing()) { error in
            guard case MarkerStoreError.unsupportedSchema(99) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: store.fileURL), data)
    }

    func testParentDirectoryIsCreatedAndWriteFailureIsReported() throws {
        let directory = try temporaryDirectory()
        let nested = MarkerStore(directory: directory.appendingPathComponent("nested"))
        XCTAssertNotNil(try nested.createIfMissing())
        let blockedParent = directory.appendingPathComponent("plain-file")
        let bytes = Data("must stay a file".utf8)
        try bytes.write(to: blockedParent)
        let blocked = MarkerStore(directory: blockedParent)
        XCTAssertThrowsError(try blocked.createIfMissing())
        XCTAssertEqual(try Data(contentsOf: blockedParent), bytes)
    }
}
