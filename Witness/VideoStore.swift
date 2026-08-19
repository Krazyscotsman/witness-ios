import Foundation

/// Keeps captured videos on-device, linked to a memory id by filename. Server upload is deferred (the 50MB cap
/// isn't raised yet), so video stays LOCAL only — this is the durable, memory-linked home for it.
enum VideoStore {
    static var dir: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WitnessVideos", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// Move a temp capture to a stable per-memory location. Returns the stable URL (or nil on failure).
    @discardableResult
    static func link(_ src: URL, to memoryID: String) -> URL? {
        let ext = src.pathExtension.isEmpty ? "mov" : src.pathExtension
        let dest = dir.appendingPathComponent("\(memoryID).\(ext)")
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.moveItem(at: src, to: dest)
            return dest
        } catch {
            try? FileManager.default.copyItem(at: src, to: dest)
            return FileManager.default.fileExists(atPath: dest.path) ? dest : nil
        }
    }

    static func url(for memoryID: String) -> URL? {
        (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
            .first { $0.deletingPathExtension().lastPathComponent == memoryID }
    }
}
