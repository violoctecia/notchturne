import AppKit
import SwiftUI

final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    var interactiveRect: CGRect?

    override func hitTest(_ point: NSPoint) -> NSView? {
        if let rect = interactiveRect, !rect.contains(point) { return nil }
        return super.hitTest(point)
    }

    required init(rootView: Content) { super.init(rootView: rootView) }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
}

final class NotchController {
    private let earWidth: CGFloat = 34
    private let settings = Settings.shared
    let clipboard = ClipboardProvider()
    let calendar = CalendarProvider()
    private let hoverPadding: CGFloat = 8
    private let settingsSlack: CGFloat = 110

    private let shadowMargin: CGFloat = 40
    private var windowSize: CGSize {
        CGSize(width: PanelLayout.maxWidth + shadowMargin * 2,
               height: PanelLayout.maxHeight + shadowMargin)
    }

    private var panel: NSPanel!
    private var host: PassthroughHostingView<NotchView>!
    private let music: MusicBridge
    private let ui = UIState()
    private var tracker: Timer?

    init(music: MusicBridge) {
        self.music = music
        buildPanel()
        layout()
        startTracking()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.layout() }
    }

    private var targetScreen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 && $0.auxiliaryTopLeftArea != nil }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func notchGeometry() -> (size: CGSize, centerX: CGFloat) {
        guard let screen = targetScreen else { return (CGSize(width: 185, height: 32), 0) }
        let f = screen.frame
        let top = screen.safeAreaInsets.top

        if top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let width = f.width - left.width - right.width
            return (CGSize(width: width, height: top), f.minX + left.width + width / 2)
        }
        return (CGSize(width: 185, height: 32), f.midX)
    }

    private var hasTrack: Bool {
        music.info.state == .playing || music.info.state == .paused
    }

    private var visibleSize: CGSize {
        ui.settingsOpen
            ? CGSize(width: ui.settingsWidth, height: PanelLayout.settingsHeight)
            : PanelLayout.size(settings)
    }

    private var visibleRect: CGRect {
        let w = panel.frame
        return CGRect(x: w.midX - visibleSize.width / 2,
                      y: w.maxY - visibleSize.height,
                      width: visibleSize.width, height: visibleSize.height)
    }

    private var triggerZone: CGRect {
        guard let screen = targetScreen else { return .null }
        let (notch, centerX) = notchGeometry()
        let padLeft = hasTrack ? earWidth : 12
        let padRight: CGFloat = hasTrack ? 0 : 12
        let h = notch.height + 4
        return CGRect(x: centerX - notch.width / 2 - padLeft,
                      y: screen.frame.maxY - h,
                      width: notch.width + padLeft + padRight,
                      height: h)
    }

    private var rightEarZone: CGRect {
        guard hasTrack, let screen = targetScreen else { return .null }
        let (notch, centerX) = notchGeometry()
        return CGRect(x: centerX + notch.width / 2,
                      y: screen.frame.maxY - notch.height,
                      width: earWidth, height: notch.height)
    }

    private func buildPanel() {
        panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: windowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary,
                                    .fullScreenAuxiliary, .ignoresCycle]

        host = PassthroughHostingView(rootView: makeView())
        host.frame = CGRect(origin: .zero, size: windowSize)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        panel.orderFrontRegardless()
    }

    private func makeView() -> NotchView {
        NotchView(music: music, lyrics: music.lyrics, ui: ui,
                  settings: settings, clipboard: clipboard, calendar: calendar,
                  notchSize: notchGeometry().size, earWidth: earWidth)
    }

    private func layout() {
        guard let screen = targetScreen else { return }
        let f = screen.frame
        let (_, centerX) = notchGeometry()

        host?.rootView = makeView()

        panel.setFrame(
            CGRect(x: centerX - windowSize.width / 2,
                   y: f.maxY - windowSize.height,
                   width: windowSize.width, height: windowSize.height),
            display: true
        )
    }

    private func startTracking() {
        tracker = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(tracker!, forMode: .common)
    }

    private func tick() {
        guard !ui.menuOpen else { return }
        let mouse = NSEvent.mouseLocation

        if ui.expanded {
            if !visibleRect.insetBy(dx: -hoverPadding, dy: -hoverPadding).contains(mouse) {
                setExpanded(false)
            }
        } else if triggerZone.contains(mouse) {
            setExpanded(true)
        }

        let onEar = !ui.expanded && rightEarZone.contains(mouse)
        if ui.hoveringPauseEar != onEar { ui.hoveringPauseEar = onEar }

        let live: CGRect = ui.expanded ? visibleRect : (onEar ? rightEarZone : .null)
        panel.ignoresMouseEvents = live.isNull
        host.interactiveRect = live.isNull
            ? nil
            : live.offsetBy(dx: -panel.frame.minX, dy: -panel.frame.minY)
    }

    private static let openSpring = Animation.spring(response: 0.42, dampingFraction: 0.80,
                                                     blendDuration: 0)
    private static let closeSpring = Animation.spring(response: 0.38, dampingFraction: 1.0,
                                                      blendDuration: 0)

    func showSettings() {
        withAnimation(Self.openSpring) {
            ui.openSettings(settings)
            ui.expanded = true
        }
    }

    private func setExpanded(_ value: Bool) {
        guard ui.expanded != value else { return }
        withAnimation(value ? Self.openSpring : Self.closeSpring) {
            ui.expanded = value
        }
    }
}
