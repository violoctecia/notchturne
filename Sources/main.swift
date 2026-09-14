import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let music = MusicBridge()
    private let settings = Settings.shared
    private var notch: NotchController?
    private var statusItem: NSStatusItem?
    private var bag = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        music.start()
        let controller = NotchController(music: music)
        notch = controller
        follow(controller)
    }

    private func follow(_ controller: NotchController) {
        settings.$calendar
            .sink { on in
                if on {
                    controller.calendar.start()
                    controller.calendar.requestAccess()
                } else {
                    controller.calendar.stop()
                }
            }
            .store(in: &bag)

        settings.$clipboard
            .sink { on in
                if on { controller.clipboard.start() } else { controller.clipboard.stop() }
            }
            .store(in: &bag)

        settings.$clipboardLimit
            .sink { controller.clipboard.setLimit($0) }
            .store(in: &bag)

        settings.$menuBarIcon
            .sink { [weak self] visible in
                if visible { self?.buildStatusItem() } else { self?.removeStatusItem() }
            }
            .store(in: &bag)
    }

    private func removeStatusItem() {
        if let item = statusItem { NSStatusBar.system.removeStatusItem(item) }
        statusItem = nil
    }

    private func buildStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "music.note",
                                     accessibilityDescription: "Notchturne")

        let menu = NSMenu()
        add(to: menu, settings.text.settingsMenu, #selector(openSettings), key: ",")
        menu.addItem(.separator())
        add(to: menu, settings.text.automationMenu, #selector(openAutomation))
        menu.addItem(.separator())
        add(to: menu, settings.text.quit, #selector(quit), key: "q")

        item.menu = menu
        statusItem = item
    }

    private func add(to menu: NSMenu, _ title: String, _ action: Selector, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    @objc private func openSettings() {
        notch?.showSettings()
    }

    @objc private func openAutomation() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
