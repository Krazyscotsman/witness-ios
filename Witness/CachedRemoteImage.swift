import SwiftUI

/// Loads a media image by media_id with an on-disk id cache (instant re-display + survives presigned expiry).
/// Cache-first; on miss loads the presigned URL, refreshing once via /media/{id}/url on failure; caches on
/// success. (AsyncImage can't populate an id cache, so this is a small auth-aware URLSession loader.)
struct CachedRemoteImage: View {
    let mediaId: String
    let rawURL: String
    @ObservedObject var vm: MemoryVisualizeViewModel
    let auth: AuthManager

    @State private var image: UIImage?
    @State private var state: LoadState = .loading
    private enum LoadState { case loading, failed }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else if state == .loading {
                ZStack { WV.teal.opacity(0.06); ProgressView().tint(WV.teal) }
            } else {
                ZStack {
                    WV.teal.opacity(0.06)
                    Image(systemName: "photo").font(.system(size: 26)).foregroundStyle(WT.ink.opacity(0.25))
                }
            }
        }
        .task(id: mediaId) { await load() }
    }

    private func load() async {
        if let cached = AIImageCache.shared.image(for: mediaId) { image = cached; return }
        await fetch(vm.resolvedURL(rawURL), allowRefresh: true)
    }

    private func fetch(_ url: URL?, allowRefresh: Bool) async {
        guard let url else { state = .failed; return }
        var req = URLRequest(url: url)
        if url.host == APIClient.baseURL.host, let token = KeychainStore.shared.token() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")   // relative /file needs Bearer
        }
        if let (data, resp) = try? await URLSession.shared.data(for: req),
           (resp as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false,
           let img = UIImage(data: data) {
            AIImageCache.shared.store(data, image: img, for: mediaId)
            image = img
            return
        }
        if allowRefresh, let fresh = await vm.refreshURL(mediaId: mediaId, auth: auth) {
            await fetch(vm.resolvedURL(fresh), allowRefresh: false)
        } else {
            state = .failed
        }
    }
}
