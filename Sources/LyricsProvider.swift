import Foundation
import CryptoKit

struct LyricLine: Equatable {
    let time: Double
    let text: String
}

final class LyricsProvider: ObservableObject {
    static let enabledDefaultsKey = "lyricsEnabled"

    enum Status: Equatable { case idle, loading, missing, plain, synced }

    @Published private(set) var lines: [LyricLine] = []
    @Published private(set) var status: Status = .idle

    var hasLyrics: Bool { status == .plain || status == .synced }

    var enabled: Bool {
        UserDefaults.standard.object(forKey: Self.enabledDefaultsKey) as? Bool ?? true
    }

    private let queue = DispatchQueue(label: "app.notchturne.lyrics", qos: .utility)
    private let session: URLSession
    private let cacheDir: URL
    private var loadedKey = ""

    init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("app.notchturne/lyrics", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        cacheDir = base

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        session = URLSession(configuration: config)
    }

    func clear() {
        loadedKey = ""
        publish([], .idle)
    }

    func load(for track: TrackInfo) {
        let key = cacheKey(track)
        guard key != loadedKey else { return }
        loadedKey = key

        guard enabled else { publish([], .idle); return }
        publish([], .loading)

        queue.async { [weak self] in
            guard let self else { return }
            if let raw = self.readCache(key) {
                self.apply(raw)
                return
            }
            guard let raw = self.fetch(track) else {
                self.publish([], .missing)
                return
            }
            self.writeCache(key, raw)
            self.apply(raw)
        }
    }

    private func apply(_ raw: Raw) {
        if let synced = raw.synced, !synced.isEmpty {
            publish(Self.parseLRC(synced), .synced)
        } else if let plain = raw.plain, !plain.isEmpty {
            let lines = plain.components(separatedBy: .newlines)
                .map { LyricLine(time: -1, text: $0.trimmingCharacters(in: .whitespaces)) }
                .filter { !$0.text.isEmpty }
            publish(lines, lines.isEmpty ? .missing : .plain)
        } else {
            publish([], .missing)
        }
    }

    private func publish(_ lines: [LyricLine], _ status: Status) {
        DispatchQueue.main.async { [weak self] in
            self?.lines = lines
            self?.status = status
        }
    }

    func index(at position: Int) -> Int? {
        guard status == .synced, !lines.isEmpty else { return nil }
        let t = Double(position)
        var found: Int? = nil
        for (i, line) in lines.enumerated() where line.time <= t { found = i }
        return found
    }

    private struct Raw { let synced: String?; let plain: String? }

    private func fetch(_ track: TrackInfo) -> Raw? {
        if let exact = get(url(path: "/api/get", items: [
            .init(name: "artist_name", value: track.artist),
            .init(name: "track_name", value: track.title),
            .init(name: "album_name", value: track.album),
            .init(name: "duration", value: String(track.duration)),
        ])), let raw = decodeOne(exact) { return raw }

        if let found = get(url(path: "/api/search", items: [
            .init(name: "q", value: "\(track.artist) \(track.title)"),
        ])), let raw = decodeList(found) { return raw }

        let plainTitle = Self.stripped(track.title)
        let mainArtist = Self.primaryArtist(track.artist)
        if plainTitle != track.title || mainArtist != track.artist,
           let found = get(url(path: "/api/search", items: [
               .init(name: "q", value: "\(mainArtist) \(plainTitle)"),
           ])), let raw = decodeList(found) { return raw }

        return nil
    }

    static func stripped(_ title: String) -> String {
        var out = title
        for pattern in ["\\([^)]*\\)", "\\[[^\\]]*\\]"] {
            out = out.replacingOccurrences(of: pattern, with: "",
                                           options: .regularExpression)
        }
        for tail in [" - Single", " - EP", " - Remix"] {
            if out.hasSuffix(tail) { out = String(out.dropLast(tail.count)) }
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    static func primaryArtist(_ artist: String) -> String {
        for separator in [" & ", ", ", " feat", " x ", " и "] {
            if let range = artist.range(of: separator, options: .caseInsensitive) {
                return String(artist[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
        }
        return artist.trimmingCharacters(in: .whitespaces)
    }

    private func url(path: String, items: [URLQueryItem]) -> URL {
        var c = URLComponents(string: "https://lrclib.net")!
        c.path = path
        c.queryItems = items.filter { !($0.value ?? "").isEmpty }
        return c.url!
    }

    private func decodeOne(_ data: Data) -> Raw? {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return raw(from: o)
    }

    private func decodeList(_ data: Data) -> Raw? {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }

        if let synced = list.first(where: { ($0["syncedLyrics"] as? String)?.isEmpty == false }) {
            return raw(from: synced)
        }
        return list.first.flatMap(raw(from:))
    }

    private func raw(from o: [String: Any]) -> Raw? {
        let synced = o["syncedLyrics"] as? String
        let plain = o["plainLyrics"] as? String
        if (synced ?? "").isEmpty && (plain ?? "").isEmpty { return nil }
        return Raw(synced: synced, plain: plain)
    }

    private func get(_ url: URL) -> Data? {
        var request = URLRequest(url: url)
        request.setValue("Notchturne (local build)", forHTTPHeaderField: "User-Agent")
        var result: Data?
        let done = DispatchSemaphore(value: 0)
        session.dataTask(with: request) { data, response, _ in
            if let http = response as? HTTPURLResponse, http.statusCode == 200 { result = data }
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + 10)
        return result
    }

    static func parseLRC(_ text: String) -> [LyricLine] {
        var out: [LyricLine] = []
        for row in text.components(separatedBy: .newlines) {
            var stamps: [Double] = []
            var rest = Substring(row)

            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                let parts = tag.split(whereSeparator: { $0 == ":" || $0 == "." })
                if parts.count >= 2, let m = Double(parts[0]), let s = Double(parts[1]) {
                    let frac = parts.count >= 3 ? (Double(parts[2]) ?? 0) / 100 : 0
                    stamps.append(m * 60 + s + frac)
                }
                rest = rest[rest.index(after: close)...]
            }

            let body = rest.trimmingCharacters(in: .whitespaces)
            guard !stamps.isEmpty else { continue }
            for stamp in stamps { out.append(LyricLine(time: stamp, text: body)) }
        }
        return out.sorted { $0.time < $1.time }
    }

    private func cacheKey(_ track: TrackInfo) -> String {
        let raw = "\(track.artist)|\(track.title)|\(track.duration)".lowercased()
        return SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func cacheURL(_ key: String) -> URL {
        cacheDir.appendingPathComponent(key).appendingPathExtension("json")
    }

    private func readCache(_ key: String) -> Raw? {
        guard let data = try? Data(contentsOf: cacheURL(key)),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return Raw(synced: o["synced"] as? String, plain: o["plain"] as? String)
    }

    private func writeCache(_ key: String, _ raw: Raw) {
        var o: [String: Any] = [:]
        if let s = raw.synced { o["synced"] = s }
        if let p = raw.plain { o["plain"] = p }
        guard let data = try? JSONSerialization.data(withJSONObject: o) else { return }
        try? data.write(to: cacheURL(key), options: .atomic)
    }
}
