import Foundation

enum Language: String, CaseIterable, Identifiable {
    case ru, en

    var id: String { rawValue }
    var short: String { self == .ru ? "Рус" : "Eng" }

    var locale: Locale { Locale(identifier: self == .ru ? "ru_RU" : "en_US") }

    static var systemDefault: Language {
        Locale.preferredLanguages.first?.hasPrefix("ru") == true ? .ru : .en
    }
}

struct Localized {
    let language: Language

    private func pick(_ ru: String, _ en: String) -> String {
        language == .ru ? ru : en
    }

    var whatToShow: String   { pick("ЧТО ПОКАЗЫВАТЬ", "WHAT TO SHOW") }
    var lyrics: String       { pick("Текст песни", "Lyrics") }
    var calendar: String     { pick("Календарь", "Calendar") }
    var clipboard: String    { pick("Буфер обмена", "Clipboard") }
    var artworkLookup: String { pick("Искать обложки в интернете", "Look up artwork online") }
    var language_: String    { pick("Язык", "Language") }
    var clipboardLimit: String { pick("Записей в буфере", "Clipboard entries") }
    var menuBarIcon: String { pick("Иконка в строке меню", "Menu bar icon") }

    var clipboardShort: String  { pick("Буфер", "Clipboard") }
    var lookingForLyrics: String { pick("Ищу текст…", "Looking for lyrics…") }
    var noLyrics: String        { pick("Текста нет", "No lyrics") }
    var clipboardEmpty: String  { pick("Пока пусто", "Nothing yet") }
    var noCalendarAccess: String { pick("Нет доступа\nк календарю", "No calendar\naccess") }
    var askingAccess: String    { pick("Запрашиваю доступ…", "Requesting access…") }

    var noMusicAccess: String   { pick("Нет доступа к Apple Music", "No access to Apple Music") }
    var allowInAutomation: String { pick("Разрешите в «Автоматизации»", "Allow under Automation") }
    var openSettings: String    { pick("Открыть настройки", "Open Settings") }
    var musicNotRunning: String { pick("Apple Music не запущен", "Apple Music isn’t running") }
    var launch: String          { pick("Запустить", "Launch") }
    var nothingPlaying: String  { pick("Ничего не играет", "Nothing playing") }

    var willSaveToLibrary: String {
        pick("Сначала сохранится в медиатеку", "Will be saved to your library first")
    }
    var noPlaylists: String { pick("Плейлистов нет", "No playlists") }
    var revealInMusic: String { pick("Показать в Music", "Reveal in Music") }
    var untitled: String { pick("Без названия", "Untitled") }

    var settingsMenu: String   { pick("Настройки…", "Settings…") }
    var automationMenu: String { pick("Доступ к Автоматизации…", "Automation access…") }
    var quit: String           { pick("Выход", "Quit") }
    var quitConfirm: String    { pick("Точно выйти?", "Quit for real?") }
}
