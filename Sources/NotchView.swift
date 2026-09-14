import SwiftUI
import AppKit

final class UIState: NSObject, ObservableObject {
    @Published var expanded = false

    @Published var menuOpen = false

    @Published var hoveringPauseEar = false

    @Published var settingsOpen = false

    @Published var settingsWidth: CGFloat = PanelLayout.settingsMinWidth

    func openSettings(_ settings: Settings) {
        settingsWidth = PanelLayout.settingsWidth(settings)
        settingsOpen = true
    }

    private var onPick: ((String) -> Void)?
    private var onReveal: (() -> Void)?

    func showPlaylistMenu(_ entries: [PlaylistEntry], text: Localized, inLibrary: Bool,
                          add: @escaping (String) -> Void,
                          reveal: @escaping () -> Void) {
        onPick = add
        onReveal = reveal
        let menu = NSMenu()

        if !inLibrary {
            let note = NSMenuItem(title: text.willSaveToLibrary,
                                  action: nil, keyEquivalent: "")
            note.isEnabled = false
            menu.addItem(note)
            menu.addItem(.separator())
        }

        if entries.isEmpty {
        } else if entries.isEmpty {
            let empty = NSMenuItem(title: text.noPlaylists, action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for entry in entries {
                let item = NSMenuItem(title: entry.name,
                                      action: #selector(pick(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = entry.name
                item.state = entry.contains ? .on : .off
                item.isEnabled = !entry.contains
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        let open = NSMenuItem(title: text.revealInMusic,
                              action: #selector(openInMusic), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        menuOpen = true
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        menuOpen = false
    }

    @objc private func openInMusic() { onReveal?() }

    @objc private func pick(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        onPick?(name)
    }
}

struct NotchView: View {
    @ObservedObject var music: MusicBridge
    @ObservedObject var lyrics: LyricsProvider
    @ObservedObject var ui: UIState
    @ObservedObject var settings: Settings
    @ObservedObject var clipboard: ClipboardProvider
    @ObservedObject var calendar: CalendarProvider
    let notchSize: CGSize

    let earWidth: CGFloat

    @State private var gearHovered = false

    private var open: Bool { ui.expanded }
    private var hasTrack: Bool {
        music.info.state == .playing || music.info.state == .paused
    }

    private var collapsedSize: CGSize {
        hasTrack ? CGSize(width: notchSize.width + earWidth * 2, height: notchSize.height)
                 : notchSize
    }

    private var showLyrics: Bool { settings.lyrics }
    private var panelSize: CGSize {
        ui.settingsOpen
            ? CGSize(width: ui.settingsWidth, height: PanelLayout.settingsHeight)
            : PanelLayout.size(settings, hasTrack: hasTrack)
    }
    private var size: CGSize { open ? panelSize : collapsedSize }

    private let hPad: CGFloat = 18
    private let topPad: CGFloat = 12
    private let bottomPad: CGFloat = 14

    private var contentHeight: CGFloat {
        panelSize.height - notchSize.height - topPad - bottomPad
    }

    private let collapsedRadius: CGFloat = 5

    private var topRadius: CGFloat { open ? 9 : collapsedRadius }
    private var bottomRadius: CGFloat { open ? 22 : 10 }
    private var shape: NotchShape { NotchShape(topRadius: topRadius, bottomRadius: bottomRadius) }

    var body: some View {
        VStack(spacing: 0) {
            shape.fill(Color.black)
                .frame(width: size.width, height: size.height)
                .overlay(alignment: .top) {
                    collapsedContent
                        .opacity(open ? 0 : 1)
                        .allowsHitTesting(!open)
                }
                .overlay(alignment: .top) {
                    content
                        .frame(width: panelSize.width, height: panelSize.height, alignment: .top)
                        .opacity(open ? 1 : 0)
                        .allowsHitTesting(open)
                }
                .overlay(alignment: .topLeading) { artworkLayer }
                .overlay(alignment: .topTrailing) {
                    gearButton

                        .padding(.trailing, 12)
                        .padding(.top, (notchSize.height - 18) / 2)
                        .opacity(open ? 1 : 0)
                        .allowsHitTesting(open)
                }
                .clipShape(shape)

                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.black)
                        .frame(width: max(size.width - topRadius * 2, 0), height: 1)
                }
                .compositingGroup()

                .shadow(color: .black.opacity(open ? 0.5 : 0), radius: 6, y: 4)
                .animation(.spring(response: 0.34, dampingFraction: 0.9), value: panelSize)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var gearButton: some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                if ui.settingsOpen { ui.settingsOpen = false } else { ui.openSettings(settings) }
            }
        } label: {
            Image(systemName: ui.settingsOpen ? "xmark" : "gearshape.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(gearHovered ? 0.9 : 0.35))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { gearHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: gearHovered)
    }

    private var panelArt: CGFloat { min(max(contentHeight - 36, 76), 100) }

    private var artworkLayer: some View {
        let side = open ? panelArt : earBox
        let x = open ? hPad : collapsedRadius + (earWidth - collapsedRadius - earBox) / 2
        let y = open ? notchSize.height + topPad : (notchSize.height - earBox) / 2

        return artworkImage
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: open ? 9 : 4, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                sourceBadge
                    .opacity(open ? 1 : 0)
                    .padding(5)
            }
            .offset(x: x, y: y)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            .opacity(hasTrack && !ui.settingsOpen ? 1 : 0)
    }

    private static let sourceIcon: NSImage? = {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music")
        else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }()

    @ViewBuilder
    private var sourceBadge: some View {
        if let icon = Self.sourceIcon {
            Button(action: { music.revealInApp() }) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 17, height: 17)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .shadow(color: .black.opacity(0.55), radius: 2.5, y: 1)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .help(settings.text.revealInMusic)
        }
    }

    private var artworkImage: some View {
        ZStack {
            if music.artworkSearching {
                Skeleton()
            } else {
                LinearGradient(colors: [.white.opacity(0.14), .white.opacity(0.05)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "music.note")
                    .font(.system(size: open ? 22 : 8))
                    .foregroundStyle(.white.opacity(0.4))
            }

            if let art = music.artwork {
                Image(nsImage: art)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.35), value: music.artwork)
        .animation(.easeInOut(duration: 0.25), value: music.artworkSearching)
    }

    private var collapsedContent: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: collapsedRadius)
            Color.clear.frame(width: earBox, height: earBox)
                .frame(maxWidth: .infinity)
            Color.clear.frame(width: notchSize.width)
            rightEar.frame(maxWidth: .infinity)
            Color.clear.frame(width: collapsedRadius)
        }
        .frame(width: collapsedSize.width, height: notchSize.height)
    }

    private let earBox: CGFloat = 18

    private var rightEar: some View {
        ZStack {
            Equalizer(playing: music.info.state == .playing)
                .opacity(ui.hoveringPauseEar ? 0 : 1)

            Button(action: music.playPause) {
                Image(systemName: music.info.state == .playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: earBox, height: earBox)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .opacity(ui.hoveringPauseEar ? 1 : 0)
            .allowsHitTesting(ui.hoveringPauseEar)
        }
        .frame(width: earBox, height: earBox)
        .animation(.easeOut(duration: 0.15), value: ui.hoveringPauseEar)
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notchSize.height)
            body(for: music.info.state)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, hPad)
                .padding(.top, topPad)
                .padding(.bottom, bottomPad)
        }
    }

    @ViewBuilder
    private func body(for state: PlayerState) -> some View {
        if ui.settingsOpen {
            SettingsPanel(settings: settings, calendar: calendar, clipboard: clipboard)
                .frame(maxWidth: PanelLayout.settingsMinWidth - hPad * 2)
                .frame(maxWidth: .infinity)
        } else {
            switch state {
            case .noPermission:
                sidePanels {
                    message(settings.text.noMusicAccess, settings.text.allowInAutomation,
                        action: (settings.text.openSettings, openAutomationSettings))
                }
            case .notRunning:
                sidePanels {
                    message(settings.text.musicNotRunning, nil, action: (settings.text.launch, launchMusic))
                }
            case .stopped:
                sidePanels {
                    message(settings.text.nothingPlaying, nil, action: nil)
                }
            case .playing, .paused:
                player
            }
        }
    }

    private var player: some View {
        sidePanels(includeLyrics: true) {
            HStack(alignment: .top, spacing: 12) {
                Color.clear.frame(width: panelArt, height: panelArt)
                infoColumn
            }
        }
    }

    @ViewBuilder
    private func sidePanels<Leading: View>(includeLyrics: Bool = false,
                                           @ViewBuilder leading: () -> Leading) -> some View {
        HStack(alignment: .top, spacing: 0) {
            leading()
                .frame(width: PanelLayout.music - hPad * 2, height: contentHeight)

            if includeLyrics && settings.lyrics {
                column(width: PanelLayout.lyrics, fade: true) {
                    LyricsColumn(text: settings.text,
                                 lyrics: lyrics,
                                 position: music.info.position,
                                 resetKey: music.info.trackID,
                                 panelOpen: open)
                }
            }
            if settings.calendar {
                column(width: PanelLayout.calendar) {
                    CalendarColumn(text: settings.text, language: settings.language, calendar: calendar)
                }
            }
            if settings.clipboard {
                column(width: PanelLayout.clipboard, fade: true) {
                    ClipboardColumn(text: settings.text, clipboard: clipboard)
                }
            }
        }
    }

    private func column<Content: View>(width: CGFloat, fade: Bool = false,
                                       @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 0) {
            Rectangle().fill(.white.opacity(0.09))
                .frame(width: 1, height: contentHeight)
                .padding(.leading, 16)
            content()
                .frame(maxWidth: .infinity, alignment: .topLeading)

                .frame(height: contentHeight, alignment: .top)
                .clipped()

                .mask(fade ? AnyView(fadeMask) : AnyView(Color.black))
                .padding(.leading, 14)
        }
        .frame(width: width)
    }

    private var fadeMask: some View {
        LinearGradient(
            stops: [.init(color: .black, location: 0),
                    .init(color: .black, location: 0.86),
                    .init(color: .clear, location: 1)],
            startPoint: .top, endPoint: .bottom
        )
    }

    private var infoColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(music.info.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(music.info.artist)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .padding(.top, 1)

            Spacer(minLength: 4)
            progress
            Spacer(minLength: 4)

            HStack(spacing: 0) {
                controlButton(music.info.favorited ? "heart.fill" : "heart", size: 12,
                              tint: music.info.favorited ? .pink : .white.opacity(0.5),
                              action: music.toggleFavorite)
                Spacer(minLength: 0)
                HStack(spacing: 18) {
                    controlButton("backward.fill", size: 13, action: music.previous)
                    controlButton(music.info.state == .playing ? "pause.fill" : "play.fill",
                                  size: 17, action: music.playPause)
                    controlButton("forward.fill", size: 13, action: music.next)
                }
                Spacer(minLength: 0)
                if music.addingToPlaylist {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                        .tint(.white)
                        .scaleEffect(0.6)
                        .frame(width: 22, height: 22)
                } else {
                controlButton(inAnyPlaylist ? "checkmark.circle.fill" : "plus.circle", size: 12,
                              tint: inAnyPlaylist ? .green : .white.opacity(0.5)) {
                    ui.showPlaylistMenu(music.playlists, text: settings.text, inLibrary: music.inLibrary,
                                        add: { music.add(to: $0) },
                                        reveal: { music.revealInApp() })
                }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxHeight: .infinity)
    }

    private var progress: some View { ProgressBar(music: music) }

    private var inAnyPlaylist: Bool { music.playlists.contains { $0.contains } }

    private func controlButton(_ symbol: String, size: CGFloat, tint: Color = .white,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: size + 10, height: size + 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
    }

    private func message(_ title: String, _ subtitle: String?,
                         action: (String, () -> Void)?) -> some View {
        VStack(spacing: 6) {
            Spacer(minLength: 0)
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.white)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
            }
            if let action {
                Button(action: action.1) {
                    Text(action.0)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 11).padding(.vertical, 4)
                        .background(Capsule().fill(.white.opacity(0.15)))
                }
                .buttonStyle(PressableButtonStyle())
                .padding(.top, 1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func openAutomationSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
        NSWorkspace.shared.open(url)
    }

    private func launchMusic() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

private struct Skeleton: View {
    @State private var shift: CGFloat = -0.9

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.white.opacity(0.09)
                LinearGradient(
                    colors: [.clear, .white.opacity(0.22), .clear],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: geo.size.width * 0.7)
                .offset(x: shift * geo.size.width)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                shift = 1.3
            }
        }
    }
}

private struct Equalizer: View {
    let playing: Bool

    private let heights: [CGFloat] = [6, 9, 7]
    private let periods: [Double] = [0.65, 0.81, 0.97]
    private let restHeight: CGFloat = 4

    var body: some View {
        TimelineView(.animation(paused: !playing)) { timeline in
            HStack(alignment: .center, spacing: 2.5) {
                ForEach(Array(heights.enumerated()), id: \.offset) { index, full in
                    Capsule()
                        .fill(Color.white.opacity(0.7))
                        .frame(width: 2.5,
                               height: playing ? height(index, full, timeline.date) : restHeight)
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: playing)
    }

    private func height(_ index: Int, _ full: CGFloat, _ date: Date) -> CGFloat {
        let period = periods[index]
        let phase = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: period) / period
        let wave = (sin(phase * 2 * .pi - .pi / 2) + 1) / 2
        return restHeight + (full - restHeight) * CGFloat(wave)
    }
}

private struct LyricsColumn: View {
    let text: Localized
    @ObservedObject var lyrics: LyricsProvider
    let position: Int

    let resetKey: String
    let panelOpen: Bool

    @State private var autoScroll = true
    @State private var wheelMonitor: Any?

    private var current: Int? { lyrics.index(at: position) }

    var body: some View {
        Group {
            switch lyrics.status {
            case .loading:          hint(text.lookingForLyrics)
            case .missing, .idle:   hint(text.noLyrics)
            case .plain, .synced:   scrollable.id(resetKey)
            }
        }
        .onAppear {
            guard wheelMonitor == nil else { return }
            wheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                autoScroll = false
                return event
            }
        }
        .onDisappear {
            if let monitor = wheelMonitor { NSEvent.removeMonitor(monitor) }
            wheelMonitor = nil
        }
    }

    private var scrollable: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(lyrics.lines.indices), id: \.self) { i in
                        let active = i == current
                        Text(lyrics.lines[i].text)

                            .font(.system(size: 10.5, weight: .medium))

                            .foregroundStyle(.white.opacity(
                                active ? 1 : (current == nil ? 0.55 : 0.28)
                            ))
                            .scaleEffect(active ? 1 : 0.97, anchor: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .id(i)
                    }
                }
                .padding(.bottom, 6)

                .animation(.easeInOut(duration: 0.45), value: current)
            }
            .scrollIndicators(.never)
            .onChange(of: current) { _, line in
                guard let line, autoScroll else { return }

                withAnimation(.spring(response: 0.55, dampingFraction: 0.92)) {
                    proxy.scrollTo(line, anchor: .center)
                }
            }

            .onChange(of: panelOpen) { _, isOpen in
                guard !isOpen else { return }
                autoScroll = true
                if let line = current { proxy.scrollTo(line, anchor: .center) }
            }
            .onChange(of: resetKey) { _, _ in autoScroll = true }
        }
    }
}

private struct CalendarColumn: View {
    let text: Localized
    let language: Language
    @ObservedObject var calendar: CalendarProvider

    private var cal: Calendar { language.locale.calendar }

    private let cellWidth: CGFloat = 20
    private let cellHeight: CGFloat = 19
    private let markSize: CGFloat = 15
    private let dotSize: CGFloat = 2.5

    var body: some View {
        switch calendar.access {
        case .granted: grid
        case .denied:  hint(text.noCalendarAccess)
        case .unknown: hint(text.askingAccess)
        }
    }

    private var grid: some View {
        let now = Date()
        let today = cal.component(.day, from: now)
        let thisMonth = cal.isDate(now, equalTo: Date(), toGranularity: .month)

        return VStack(alignment: .leading, spacing: 0) {
            header(title(now))
            HStack(spacing: 0) {
                ForEach(weekdays, id: \.self) { name in
                    Text(name)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.white.opacity(0.28))
                        .frame(width: cellWidth)
                }
            }
            .padding(.bottom, 2)

            ForEach(Array(weeks(of: now).enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        cell(day, today: thisMonth ? today : 0)
                    }
                }
            }
        }
        .frame(width: cellWidth * 7, alignment: .leading)
    }

    private func cell(_ day: Int, today: Int) -> some View {
        let isToday = day != 0 && day == today
        let busy = day != 0 && calendar.busyDays.contains(day)
        return ZStack {
            if isToday {
                Circle().fill(.white).frame(width: markSize, height: markSize)
            }
            Text(day == 0 ? "" : "\(day)")
                .font(.system(size: 9.5, weight: isToday ? .bold : .regular).monospacedDigit())
                .foregroundStyle(isToday ? .black : .white.opacity(0.75))

            Circle()
                .fill(isToday ? .black.opacity(0.55) : .white.opacity(busy ? 0.55 : 0))
                .frame(width: dotSize, height: dotSize)
                .opacity(busy ? 1 : 0)
                .offset(y: markSize / 2 - 1)
        }
        .frame(width: cellWidth, height: cellHeight)
    }

    private var weekdays: [String] {
        let symbols = cal.shortStandaloneWeekdaySymbols
        let shift = cal.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    private func weeks(of date: Date) -> [[Int]] {
        guard let interval = cal.dateInterval(of: .month, for: date),
              let length = cal.range(of: .day, in: .month, for: date)?.count
        else { return [] }

        let firstWeekday = cal.component(.weekday, from: interval.start)
        let lead = (firstWeekday - cal.firstWeekday + 7) % 7

        var cells = Array(repeating: 0, count: lead) + Array(1...length)
        while cells.count % 7 != 0 { cells.append(0) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0 ..< $0 + 7]) }
    }

    private func title(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = language.locale
        f.dateFormat = "LLLL yyyy"
        return f.string(from: date)
    }
}

private struct ClipboardColumn: View {
    let text: Localized
    @ObservedObject var clipboard: ClipboardProvider
    @State private var hovered: UUID?
    @State private var copied: UUID?

    private let inset: CGFloat = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header(text.clipboardShort).padding(.leading, inset)

            if clipboard.items.isEmpty {
                hint(text.clipboardEmpty)
            } else {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(clipboard.items) { item in row(item) }
                    }
                    .padding(.bottom, 6)
                }
                .scrollIndicators(.never)
            }
        }
        .animation(.easeOut(duration: 0.15), value: hovered)
    }

    private func row(_ item: ClipboardProvider.Entry) -> some View {
        let isHovered = hovered == item.id
        let isCopied = copied == item.id
        return HStack(alignment: .top, spacing: 6) {
            Text(item.text)
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(isHovered ? 1 : 0.6))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: isCopied ? "checkmark" : "square.on.square")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(isCopied ? Color.green : .white.opacity(isHovered ? 0.75 : 0.2))
                .frame(width: 13, height: 13)
        }

        .padding(.vertical, 4)
        .padding(.horizontal, inset)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.white.opacity(isHovered ? 0.1 : 0))
        )
        .contentShape(Rectangle())
        .onTapGesture { copy(item) }
        .onHover { hovered = $0 ? item.id : nil }
    }

    private func copy(_ item: ClipboardProvider.Entry) {
        clipboard.copyBack(item)
        withAnimation(.easeOut(duration: 0.15)) { copied = item.id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            guard copied == item.id else { return }
            withAnimation(.easeOut(duration: 0.25)) { copied = nil }
        }
    }
}

private func header(_ text: String) -> some View {
    Text(text.uppercased())
        .font(.system(size: 8, weight: .semibold))
        .foregroundStyle(.white.opacity(0.3))
        .kerning(0.6)
        .padding(.bottom, 5)
}

private func hint(_ text: String) -> some View {
    VStack {
        Spacer(minLength: 0)
        Text(text)
            .font(.system(size: 10.5))
            .foregroundStyle(.white.opacity(0.3))
            .multilineTextAlignment(.center)
        Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}

private struct ProgressBar: View {
    @ObservedObject var music: MusicBridge

    @State private var dragging = false
    @State private var hovering = false
    @State private var localRatio: Double = 0
    @State private var holdUntil = Date.distantPast

    private var duration: Int { max(music.info.duration, 1) }

    var body: some View {
        let polled = clamp(Double(music.info.position) / Double(duration))
        let ratio = (dragging || Date() < holdUntil) ? localRatio : polled
        let shown = Int(ratio * Double(duration))
        let thick = (dragging || hovering) ? 5.0 : 3.0
        let knob = 10.0

        VStack(spacing: 3) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.16))
                        .frame(height: thick)

                    Capsule().fill(.white.opacity(0.9))
                        .frame(width: max(geo.size.width * ratio, thick), height: thick)
                        .overlay(alignment: .trailing) {
                            Circle()
                                .fill(.white)
                                .frame(width: knob, height: knob)
                                .offset(x: knob / 2)
                                .opacity(dragging || hovering ? 1 : 0)
                        }
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())

                .animation(dragging ? nil : .linear(duration: 0.9), value: ratio)
                .animation(.easeOut(duration: 0.15), value: thick)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            dragging = true
                            localRatio = clamp(value.location.x / geo.size.width)
                        }
                        .onEnded { value in
                            localRatio = clamp(value.location.x / geo.size.width)
                            music.seek(to: Int(localRatio * Double(duration)))
                            holdUntil = Date().addingTimeInterval(1.2)
                            dragging = false
                        }
                )
            }
            .frame(height: 12)
            .onHover { hovering = $0 }

            HStack {
                Text(clock(shown))
                Spacer()
                Text("-" + clock(max(duration - shown, 0)))
            }
            .font(.system(size: 9, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(dragging ? 0.8 : 0.4))
        }
    }

    private func clamp(_ v: Double) -> Double { min(max(v, 0), 1) }

    private func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

struct PressableButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : (hovering ? 1.12 : 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.6),
                       value: configuration.isPressed)
            .animation(.easeOut(duration: 0.14), value: hovering)
            .onHover { hovering = $0 }
    }
}
