import AppKit
import Combine
import Foundation

enum PlayerState: String {
    case playing, paused, stopped, notRunning, noPermission
}

struct TrackInfo: Equatable {
    var state: PlayerState = .notRunning
    var trackID: String = ""
    var title: String = ""
    var artist: String = ""
    var album: String = ""
    var duration: Int = 0
    var position: Int = 0
    var favorited = false
}

struct PlaylistEntry: Equatable, Identifiable {
    let name: String
    let contains: Bool
    var id: String { name }
}

final class MusicBridge: ObservableObject {
    @Published private(set) var info = TrackInfo()
    @Published private(set) var artwork: NSImage?

    @Published private(set) var artworkSearching = false
    @Published private(set) var playlists: [PlaylistEntry] = []

    @Published private(set) var inLibrary = false

    @Published private(set) var addingToPlaylist = false

    private let queue = DispatchQueue(label: "app.notchturne.music", qos: .utility)
    private let artQueue = DispatchQueue(label: "app.notchturne.artwork", qos: .utility)
    private let metaQueue = DispatchQueue(label: "app.notchturne.meta", qos: .utility)
    private var metaTrack = ""
    private var timer: DispatchSourceTimer?

    let lyrics = LyricsProvider()
    private let art = ArtworkProvider()
    private var artTrack = ""
    private var artPending = ""
    private var artTries = 0
    private var artBusy = false
    private var artNext = Date.distantPast

    private static let quickArtTries = 6
    private static let slowArtInterval: TimeInterval = 10

    private lazy var artworkPath: String = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("app.notchturne", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("artwork.img").path
    }()

    func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 0.2, repeating: 1.0)
        t.setEventHandler { [weak self] in self?.poll() }
        t.resume()
        timer = t
    }

    func playPause() { command("playpause") }
    func next()      { command("next track") }
    func previous()  { command("back track") }

    func seek(to seconds: Int) {
        let target = max(0, seconds)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.info.duration > 0 else { return }
            self.info.position = min(target, self.info.duration)
        }
        queue.async { [weak self] in
            _ = Self.osa("if application \"Music\" is running then "
                       + "tell application \"Music\" to set player position to \(target)")
            self?.poll()
        }
    }

    func toggleFavorite() {
        DispatchQueue.main.async { [weak self] in self?.info.favorited.toggle() }
        queue.async { [weak self] in
            _ = Self.osa("""
            if application "Music" is running then
                tell application "Music"
                    set t to current track
                    set favorited of t to (not (favorited of t))
                end tell
            end if
            """)
            self?.poll()
        }
    }

    func add(to playlist: String) {
        let safe = playlist.replacingOccurrences(of: "\"", with: "\\\"")
        DispatchQueue.main.async { [weak self] in self?.addingToPlaylist = true }

        metaQueue.async { [weak self] in
            _ = Self.osa("""
            if application "Music" is running then
                tell application "Music"
                    set nm to name of current track
                    set ar to artist of current track
                    set found to (every track of library playlist 1 whose name is nm and artist is ar)
                    if (count of found) is 0 then
                        try
                            duplicate current track to source 1
                        end try
                        repeat with i from 1 to 15
                            delay 1
                            set found to (every track of library playlist 1 whose name is nm and artist is ar)
                            if (count of found) > 0 then exit repeat
                        end repeat
                    end if
                    if (count of found) > 0 then
                        duplicate (item 1 of found) to playlist "\(safe)"
                    end if
                end tell
            end if
            """)
            guard let self else { return }
            DispatchQueue.main.async { self.addingToPlaylist = false }
            self.metaTrack = ""
            self.queue.async { self.poll() }
        }
    }

    func revealInApp() {
        metaQueue.async {
            _ = Self.osa("""
            if application "Music" is running then
                tell application "Music"
                    activate
                    try
                        reveal current track
                    end try
                end tell
            end if
            """)
        }
    }

    private func refreshPlaylists(for track: TrackInfo) {
        guard track.trackID != metaTrack else { return }
        metaTrack = track.trackID
        metaQueue.async { [weak self] in
            guard let self else { return }
            let r = Self.osa(Self.playlistScript)
            guard r.status == 0 else { return }
            var rows = r.stdout.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            let hasLibrary = rows.first == "true"
            if !rows.isEmpty { rows.removeFirst() }
            let entries = rows.compactMap { row -> PlaylistEntry? in
                let f = row.components(separatedBy: "\t")
                guard f.count >= 2 else { return nil }
                return PlaylistEntry(name: f[0], contains: f[1] == "true")
            }
            DispatchQueue.main.async {
                self.inLibrary = hasLibrary
                self.playlists = entries
            }
        }
    }

    private static let playlistScript = """
    if application "Music" is running then
        tell application "Music"
            set nm to name of current track
            set ar to artist of current track
            set hasLib to false
            try
                if (count of (every track of library playlist 1 whose name is nm and artist is ar)) > 0 then
                    set hasLib to true
                end if
            end try
            set out to (hasLib as text)
            repeat with pl in (every user playlist)
                try
                    if ((special kind of pl) as text) is "none" then
                        set n to (count of (every track of pl whose name is nm and artist is ar))
                        set out to out & linefeed & (name of pl) & tab & ((n > 0) as text)
                    end if
                end try
            end repeat
            return out
        end tell
    end if
    return "false"
    """

    private func command(_ verb: String) {
        queue.async { [weak self] in
            _ = Self.osa("if application \"Music\" is running then tell application \"Music\" to \(verb)")
            self?.poll()
        }
    }

    private func poll() {
        let result = Self.osa(Self.stateScript)

        guard result.status == 0 else {
            let denied = result.stderr.contains("-1743") || result.stderr.contains("Not authorized")
            publish(TrackInfo(state: denied ? .noPermission : .notRunning))
            return
        }

        let out = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        if out == "notrunning" {
            publish(TrackInfo(state: .notRunning))
            return
        }

        let parts = out.components(separatedBy: "\t")
        guard parts.count >= 7 else {
            publish(TrackInfo(state: .stopped))
            return
        }

        var next = TrackInfo()
        next.state = PlayerState(rawValue: parts[0]) ?? .stopped
        next.trackID = parts[1]
        next.title = parts[2]
        next.artist = parts[3]
        next.album = parts[4]
        next.duration = Int(parts[5]) ?? 0
        next.position = Int(parts[6]) ?? 0
        next.favorited = parts.count > 7 && parts[7] == "true"

        DispatchQueue.main.async { [weak self] in
            guard let self, self.info != next else { return }
            self.info = next
        }

        requestArtwork(for: next)
        lyrics.load(for: next)
        refreshPlaylists(for: next)
    }

    private func publish(_ new: TrackInfo) {
        artTrack = ""; artPending = ""; artTries = 0
        metaTrack = ""
        lyrics.clear()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.info != new { self.info = new }
            if self.artwork != nil { self.artwork = nil }
            self.artworkSearching = false
        }
    }

    private func requestArtwork(for track: TrackInfo) {
        guard track.trackID != artTrack else { return }

        if track.trackID != artPending {
            artPending = track.trackID
            artTries = 0
            artNext = .distantPast
            DispatchQueue.main.async { [weak self] in
                self?.artwork = nil
                self?.artworkSearching = true
            }
        }
        guard !artBusy, Date() >= artNext else { return }

        artBusy = true
        artTries += 1
        let tries = artTries
        artNext = Date().addingTimeInterval(
            tries < Self.quickArtTries ? 0 : Self.slowArtInterval
        )

        artQueue.async { [weak self] in
            guard let self else { return }

            let image = self.art.artwork(for: track, allowOnline: tries == Self.quickArtTries) {
                self.localArtworkData()
            }
            DispatchQueue.main.async {
                if let image { self.artwork = image }
                if image != nil || tries >= Self.quickArtTries {
                    self.artworkSearching = false
                }
            }
            self.queue.async {
                if image != nil { self.artTrack = track.trackID }
                self.artBusy = false
            }
        }
    }

    private func localArtworkData() -> Data? {
        try? FileManager.default.removeItem(atPath: artworkPath)
        let r = Self.osa(Self.artworkScript(path: artworkPath))
        guard r.status == 0, r.stdout.contains("ok") else { return nil }
        return FileManager.default.contents(atPath: artworkPath)
    }

    private static func osa(_ source: String) -> (stdout: String, stderr: String, status: Int32) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", source]
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do { try p.run() } catch { return ("", "launch failed", -1) }
        let o = out.fileHandleForReading.readDataToEndOfFile()
        let e = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (String(data: o, encoding: .utf8) ?? "",
                String(data: e, encoding: .utf8) ?? "",
                p.terminationStatus)
    }

    private static let stateScript = """
    if application "Music" is running then
        tell application "Music"
            set theState to "stopped"
            try
                set theState to (player state as text)
            end try
            if theState is "stopped" then return "stopped"
            try
                set tr to current track
                set nm to (name of tr) as text
                set ar to (artist of tr) as text
                set al to (album of tr) as text
                set du to 0
                try
                    set du to (duration of tr) as integer
                end try
                set ps to 0
                try
                    set ps to (player position) as integer
                end try
                set fav to false
                try
                    set fav to favorited of tr
                end try
                set tid to nm & "|" & ar
                try
                    set tid to (persistent ID of tr) as text
                end try
                return theState & tab & tid & tab & nm & tab & ar & tab & al & tab & (du as text) & tab & (ps as text) & tab & (fav as text)
            on error
                return theState
            end try
        end tell
    end if
    return "notrunning"
    """

    private static func artworkScript(path: String) -> String {
        """
        set thePath to "\(path)"
        set gotIt to false
        if application "Music" is running then
            tell application "Music"
                set candidates to {}
                try
                    set end of candidates to current track
                end try
                try
                    set nm to name of current track
                    set ar to artist of current track
                    repeat with t in (every track of library playlist 1 whose name is nm)
                        if (artist of t) is ar then set end of candidates to t
                    end repeat
                end try
                repeat with t in candidates
                    if not gotIt then
                        try
                            set d to raw data of artwork 1 of t
                            set gotIt to true
                        on error
                            try
                                set d to data of artwork 1 of t
                                set gotIt to true
                            end try
                        end try
                    end if
                end repeat
            end tell
        end if
        if gotIt then
            try
                set f to open for access (POSIX file thePath) with write permission
                set eof f to 0
                write d to f
                close access f
                return "ok"
            on error
                try
                    close access (POSIX file thePath)
                end try
            end try
        end if
        return "err"
        """
    }
}
