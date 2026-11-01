import Foundation

/// Test data only. This is not the future habit application's database.
public struct ProbeMarker: Codable, Equatable {
    public let schemaVersion: Int
    public let id: UUID
    public let createdAt: Date

    public init(id: UUID = UUID(), createdAt: Date = Date()) {
        self.schemaVersion = 1
        self.id = id
        // JSON uses ISO 8601 to whole seconds; retain exact equality on read-back.
        self.createdAt = Date(timeIntervalSince1970: floor(createdAt.timeIntervalSince1970))
    }
}

public enum MarkerStoreError: LocalizedError {
    case unsupportedSchema(Int)
    case verificationFailed

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            return "无法识别测试标记版本 \(version)，原文件已保留。"
        case .verificationFailed:
            return "测试标记写入后校验失败，请保留现场。"
        }
    }
}

/// Caller serializes operations. The UI uses this synchronously on MainActor.
public struct MarkerStore {
    public let fileURL: URL

    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("marker.json", isDirectory: false)
    }

    public func load() throws -> ProbeMarker? {
        let bytes: Data
        do {
            bytes = try Data(contentsOf: fileURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
        // Permission, decoding and other errors must not be treated as an empty store.
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let marker = try decoder.decode(ProbeMarker.self, from: bytes)
        guard marker.schemaVersion == 1 else {
            throw MarkerStoreError.unsupportedSchema(marker.schemaVersion)
        }
        return marker
    }

    @discardableResult
    public func createIfMissing(now: Date = Date()) throws -> ProbeMarker {
        // Never overwrite an existing valid or damaged marker.
        if let existing = try load() { return existing }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let marker = ProbeMarker(createdAt: now)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(marker).write(to: fileURL, options: .atomic)
        guard let reloaded = try load(), reloaded == marker else {
            throw MarkerStoreError.verificationFailed
        }
        return reloaded
    }
}
