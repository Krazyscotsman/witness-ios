import UIKit

/// Tiny id-keyed image cache (memory + disk) so a generated image re-displays instantly and survives presigned
/// URL expiry. Keyed by media_id (stable), unlike URLCache (keyed by the rotating presigned URL).
final class AIImageCache {
    static let shared = AIImageCache()
    private let mem = NSCache<NSString, UIImage>()
    private let dir: URL

    private init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent("AIImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    private func file(_ id: String) -> URL {
        dir.appendingPathComponent(id.replacingOccurrences(of: "/", with: "_"))
    }

    func image(for id: String) -> UIImage? {
        if let m = mem.object(forKey: id as NSString) { return m }
        guard let data = try? Data(contentsOf: file(id)), let img = UIImage(data: data) else { return nil }
        mem.setObject(img, forKey: id as NSString)
        return img
    }
    func store(_ data: Data, image: UIImage, for id: String) {
        mem.setObject(image, forKey: id as NSString)
        try? data.write(to: file(id), options: .atomic)
    }
}
