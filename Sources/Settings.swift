import Foundation
import Combine

final class Settings: ObservableObject {
    static let shared = Settings()

    enum Key {
        static let lyrics = "lyricsEnabled"
        static let artworkLookup = "artworkLookupEnabled"
        static let calendar = "calendarEnabled"
        static let clipboard = "clipboardEnabled"
        static let language = "language"
        static let clipboardLimit = "clipboardLimit"
        static let menuBarIcon = "menuBarIcon"
        static let activationDelay = "activationDelayMs"
    }

    @Published var lyrics: Bool { didSet { write(Key.lyrics, lyrics) } }
    @Published var artworkLookup: Bool { didSet { write(Key.artworkLookup, artworkLookup) } }
    @Published var calendar: Bool { didSet { write(Key.calendar, calendar) } }
    @Published var clipboard: Bool { didSet { write(Key.clipboard, clipboard) } }
    @Published var menuBarIcon: Bool { didSet { write(Key.menuBarIcon, menuBarIcon) } }
    @Published var clipboardLimit: Int {
        didSet { UserDefaults.standard.set(clipboardLimit, forKey: Key.clipboardLimit) }
    }
    @Published var activationDelay: Int {
        didSet { UserDefaults.standard.set(activationDelay, forKey: Key.activationDelay) }
    }
    @Published var language: Language {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Key.language) }
    }

    var text: Localized { Localized(language: language) }

    private init() {
        lyrics = Self.read(Key.lyrics, default: true)
        artworkLookup = Self.read(Key.artworkLookup, default: true)
        calendar = Self.read(Key.calendar, default: false)
        clipboard = Self.read(Key.clipboard, default: false)
        menuBarIcon = Self.read(Key.menuBarIcon, default: true)
        let storedLimit = UserDefaults.standard.object(forKey: Key.clipboardLimit) as? Int
        clipboardLimit = storedLimit ?? 3
        let storedDelay = UserDefaults.standard.object(forKey: Key.activationDelay) as? Int
        activationDelay = storedDelay ?? 100
        language = (UserDefaults.standard.string(forKey: Key.language)
                        .flatMap(Language.init(rawValue:))) ?? .systemDefault
    }

    private static func read(_ key: String, default fallback: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? fallback
    }

    private func write(_ key: String, _ value: Bool) {
        UserDefaults.standard.set(value, forKey: key)
    }
}

enum PanelLayout {
    static let music: CGFloat = 360
    static let lyrics: CGFloat = 200
    static let calendar: CGFloat = 178
    static let clipboard: CGFloat = 200

    static let baseHeight: CGFloat = 150

    static let calendarHeight: CGFloat = 200

    static func width(_ settings: Settings, hasTrack: Bool) -> CGFloat {
        var w = music
        if settings.lyrics && hasTrack { w += lyrics }
        if settings.calendar { w += calendar }
        if settings.clipboard { w += clipboard }
        return w
    }

    static func height(_ settings: Settings) -> CGFloat {
        settings.calendar ? calendarHeight : baseHeight
    }

    static func size(_ settings: Settings, hasTrack: Bool) -> CGSize {
        CGSize(width: width(settings, hasTrack: hasTrack), height: height(settings))
    }

    static let settingsMinWidth: CGFloat = 430
    static let settingsHeight: CGFloat = 348

    static func settingsWidth(_ settings: Settings) -> CGFloat {
        max(settingsMinWidth, width(settings, hasTrack: true))
    }

    static let maxWidth = music + lyrics + calendar + clipboard
    static let maxHeight = max(calendarHeight, settingsHeight)
}
