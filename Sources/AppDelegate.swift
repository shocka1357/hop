import AppKit
import Carbon.HIToolbox
import ServiceManagement
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let hud = HUD()

    private var triggerID: UInt32?
    /// Hotkeys (1–4, Esc) that only exist while the HUD is on screen.
    private var sessionIDs: [UInt32] = []
    private var dismissTimer: Timer?
    private var mouseMonitor: Any?
    private var appSwitchObserver: NSObjectProtocol?
    private var recorder: HotkeyRecorder?

    private static let numberKeys = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4]
    private static let keypadKeys = [kVK_ANSI_Keypad1, kVK_ANSI_Keypad2, kVK_ANSI_Keypad3, kVK_ANSI_Keypad4]

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "Hop")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        statusItem.isVisible = !Settings.hideMenuBarIcon

        hud.onPick = { [weak self] in self?.open(slot: $0) }
        registerTrigger()

        if !Settings.hasWelcomed {
            Settings.hasWelcomed = true
            DispatchQueue.main.async { self.showWelcome() }
        }
    }

    /// Opening Hop again (Finder, Spotlight, Launchpad) brings back a hidden icon and opens its menu.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if Settings.hideMenuBarIcon {
            Settings.hideMenuBarIcon = false
            statusItem.isVisible = true
        }
        DispatchQueue.main.async { self.statusItem.button?.performClick(nil) }
        return false
    }

    // MARK: - Hotkey flow

    private func registerTrigger() {
        if let triggerID { HotKeyCenter.shared.unregister(triggerID) }
        let hotkey = Settings.hotkey
        triggerID = HotKeyCenter.shared.register(keyCode: hotkey.keyCode, modifiers: hotkey.modifiers) { [weak self] in
            guard let self else { return }
            self.hud.isVisible ? self.dismiss() : self.present()
        }
    }

    private func present() {
        hud.show(apps: Settings.slots)

        // Accept plain 1–4 (and keypad), plus 1–4 with the trigger's modifiers still held down.
        let triggerMods = Settings.hotkey.modifiers
        let modifierSets: [UInt32] = triggerMods == 0 ? [0] : [0, triggerMods]
        for slot in 0..<Settings.slotCount {
            for key in [Self.numberKeys[slot], Self.keypadKeys[slot]] {
                for mods in modifierSets {
                    addSessionKey(key, mods) { [weak self] in self?.open(slot: slot) }
                }
            }
        }
        addSessionKey(kVK_Escape, 0) { [weak self] in self?.dismiss() }

        dismissTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in self?.dismiss() }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            self?.dismiss()
        }
        appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.dismiss() }
    }

    private func addSessionKey(_ keyCode: Int, _ modifiers: UInt32, _ action: @escaping () -> Void) {
        if let id = HotKeyCenter.shared.register(keyCode: keyCode, modifiers: modifiers, handler: action) {
            sessionIDs.append(id)
        }
    }

    private func dismiss() {
        sessionIDs.forEach(HotKeyCenter.shared.unregister)
        sessionIDs = []
        dismissTimer?.invalidate()
        dismissTimer = nil
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
        if let appSwitchObserver { NSWorkspace.shared.notificationCenter.removeObserver(appSwitchObserver) }
        appSwitchObserver = nil
        hud.hide()
    }

    private func open(slot: Int) {
        guard let url = Settings.slots[slot] else {
            NSSound.beep()
            return
        }
        hud.highlight(slot)
        dismiss()
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            guard let error else { return }
            DispatchQueue.main.async {
                self.alert("Couldn't open \(appName(url))", error.localizedDescription)
            }
        }
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let hotkey = Settings.hotkey.displayString
        if triggerID == nil {
            menu.addItem(.sectionHeader(title: "⚠︎ \(hotkey) is used by another app. Pick a different hotkey."))
        } else {
            menu.addItem(.sectionHeader(title: "Press \(hotkey), then 1–4"))
        }

        for (i, url) in Settings.slots.enumerated() {
            let item = NSMenuItem(title: "\(i + 1)   \(url.map(appName) ?? "Not set")", action: nil, keyEquivalent: "")
            if let url {
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                icon.size = NSSize(width: 16, height: 16)
                item.image = icon
            } else {
                item.image = NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)
            }
            let submenu = NSMenu()
            let choose = submenu.addItem(withTitle: url == nil ? "Choose App…" : "Change App…",
                                         action: #selector(chooseApp(_:)), keyEquivalent: "")
            choose.target = self
            choose.tag = i
            if url != nil {
                let clear = submenu.addItem(withTitle: "Remove", action: #selector(clearSlot(_:)), keyEquivalent: "")
                clear.target = self
                clear.tag = i
            }
            item.submenu = submenu
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let change = menu.addItem(withTitle: "Change Hotkey (\(hotkey))…", action: #selector(changeHotkey), keyEquivalent: "")
        change.target = self
        let login = menu.addItem(withTitle: "Open at Login", action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        let hide = menu.addItem(withTitle: "Hide Menu Bar Icon…", action: #selector(hideMenuBarIcon), keyEquivalent: "")
        hide.target = self

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Hop", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc private func chooseApp(_ sender: NSMenuItem) {
        let panel = NSOpenPanel()
        panel.message = "Choose the app for key \(sender.tag + 1)"
        panel.prompt = "Choose"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var slots = Settings.slots
        slots[sender.tag] = url
        Settings.slots = slots
    }

    @objc private func clearSlot(_ sender: NSMenuItem) {
        var slots = Settings.slots
        slots[sender.tag] = nil
        Settings.slots = slots
    }

    @objc private func changeHotkey() {
        dismiss()
        if let triggerID { HotKeyCenter.shared.unregister(triggerID) }
        triggerID = nil
        recorder = HotkeyRecorder { [weak self] newHotkey in
            guard let self else { return }
            self.recorder = nil
            guard let newHotkey else { return self.registerTrigger() }
            let previous = Settings.hotkey
            Settings.hotkey = newHotkey
            self.registerTrigger()
            if self.triggerID == nil {
                Settings.hotkey = previous
                self.registerTrigger()
                self.alert("\(newHotkey.displayString) is already in use",
                           "Another app has claimed that shortcut. Hop is still using \(previous.displayString).")
            }
        }
        recorder?.start()
    }

    @objc private func toggleLoginItem() {
        setLoginItem(SMAppService.mainApp.status != .enabled)
    }

    @objc private func hideMenuBarIcon() {
        let alert = NSAlert()
        alert.messageText = "Hide Hop's menu bar icon?"
        alert.informativeText = """
            Hop keeps working in the background. Press \(Settings.hotkey.displayString) as usual.

            To bring the icon back, open Hop again from your Applications folder or Spotlight.
            """
        alert.addButton(withTitle: "Hide Icon")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Settings.hideMenuBarIcon = true
        statusItem.isVisible = false
    }

    private func setLoginItem(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            alert("Couldn't change the login setting", error.localizedDescription)
        }
        if SMAppService.mainApp.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    // MARK: - Alerts

    private func showWelcome() {
        let alert = NSAlert()
        alert.messageText = "Hop is in your menu bar"
        alert.informativeText = """
            Click the grid icon in the menu bar to pick your four apps.

            Then press \(Settings.hotkey.displayString) from anywhere and tap 1, 2, 3 or 4 to jump to that app. \
            Press Esc, or just wait, to dismiss.
            """
        alert.addButton(withTitle: "Choose My Apps")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Open Hop automatically at login"
        alert.suppressionButton?.state = .on
        NSApp.activate()
        alert.runModal()
        if alert.suppressionButton?.state == .on { setLoginItem(true) }
        statusItem.button?.performClick(nil)
    }

    private func alert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        NSApp.activate()
        alert.runModal()
    }
}

/// A tiny window that captures the next key combination you press.
final class HotkeyRecorder: NSObject, NSWindowDelegate {
    private let window: NSPanel
    private let hint: NSTextField
    private var monitor: Any?
    private var completion: ((Hotkey?) -> Void)?

    init(completion: @escaping (Hotkey?) -> Void) {
        self.completion = completion
        window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 130),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        hint = NSTextField(labelWithString: "Include ⌘, ⌥ or ⌃ · Esc to cancel")
        super.init()

        window.title = "Change Hotkey"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.delegate = self

        let title = NSTextField(labelWithString: "Press your new shortcut")
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [title, hint])
        stack.orientation = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = window.contentView!
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
    }

    func start() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
            return nil
        }
        window.center()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func handle(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if Int(event.keyCode) == kVK_Escape && flags.isDisjoint(with: [.command, .option, .control]) {
            return finish(nil)
        }
        guard let hotkey = Hotkey(event: event) else {
            NSSound.beep()
            hint.stringValue = "Needs ⌘, ⌥ or ⌃. Try again (Esc to cancel)"
            return
        }
        finish(hotkey)
    }

    func windowWillClose(_ notification: Notification) {
        finish(nil)
    }

    private func finish(_ hotkey: Hotkey?) {
        guard let completion else { return }
        self.completion = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        window.close()
        completion(hotkey)
    }
}
