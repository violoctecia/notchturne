import AppKit
import CryptoKit
import Foundation

final class ArtworkProvider {
    static let lookupDefaultsKey = "artworkLookupEnabled"

    private let cacheDir: URL
    private var missing = Set<String>()
    private let session: URLSession

    var lookupEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.lookupDefaultsKey) as? Bool ?? true
    }

    init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("app.notchturne/art", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        cacheDir = base

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        session = URLSession(configuration: config)
    }

    func artwork(for info: TrackInfo, allowOnline: Bool,
                 localData: @escaping () -> Data?) -> NSImage? {
        if let data = localData(), let image = NSImage(data: data) { return image }

        let key = cacheKey(for: info)
        guard !key.isEmpty else { return nil }

        if let cached = readCache(key) { return cached }
        guard allowOnline, lookupEnabled, !missing.contains(key) else { return nil }

        guard let data = lookupOnline(info) else {
            missing.insert(key)
            return nil
        }
        writeCache(key, data)
        return NSImage(data: data)
    }

    private func lookupOnline(_ info: TrackInfo) -> Data? {
        if let url = searchURL(term: "\(info.artist) \(info.album)", entity: "album"),
           let data = fetchArtwork(from: url) { return data }
        if let url = searchURL(term: "\(info.artist) \(info.title)", entity: "song"),
           let data = fetchArtwork(from: url) { return data }
        return nil
    }

    private func searchURL(term: String, entity: String) -> URL? {
        let trimmed = term.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        var c = URLComponents(string: "https://itunes.apple.com/search")!
        c.queryItems = [
            .init(name: "term", value: trimmed),
            .init(name: "media", value: "music"),
            .init(name: "entity", value: entity),
            .init(name: "limit", value: "1"),
        ]
        return c.url
    }

    private func fetchArtwork(from url: URL) -> Data? {
        guard let json = get(url),
              let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let results = root["results"] as? [[String: Any]],
              let first = results.first,
              let small = first["artworkUrl100"] as? String
        else { return nil }

        let big = small.replacingOccurrences(of: "100x100bb", with: "600x600bb")
        guard let imageURL = URL(string: big) else { return nil }
        return get(imageURL)
    }

    private func get(_ url: URL) -> Data? {
        var result: Data?
        let done = DispatchSemaphore(value: 0)
        session.dataTask(with: url) { data, response, _ in
            if let http = response as? HTTPURLResponse, http.statusCode == 200 { result = data }
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + 10)
        return result
    }

    private func cacheKey(for info: TrackInfo) -> String {
        let raw = "\(info.artist)|\(info.album)|\(info.title)".lowercased()
        guard raw.count > 2 else { return "" }
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func cacheURL(_ key: String) -> URL {
        cacheDir.appendingPathComponent(key).appendingPathExtension("img")
    }

    private func readCache(_ key: String) -> NSImage? {
        guard let data = try? Data(contentsOf: cacheURL(key)) else { return nil }
        return NSImage(data: data)
    }

    private func writeCache(_ key: String, _ data: Data) {
        try? data.write(to: cacheURL(key), options: .atomic)
    }
}
