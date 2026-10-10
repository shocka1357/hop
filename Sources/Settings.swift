import AppKit
import Carbon.HIToolbox

struct Hotkey: Equatable {
    var keyCode: Int
    var modifiers: UInt32 // Carbon modifier mask (cmdKey, optionKey, …)
    var keyName: String

    static let `default` = Hotkey(keyCode: kVK_Space, modifiers: UInt32(optionKey), keyName: "Space")

    var displayString: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + keyName
    }

    /// Builds a hotkey from a recorded key press. Returns nil unless ⌘, ⌥ or ⌃ is held.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.isDisjoint(with: [.command, .option, .control]) else { return nil }
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        self.init(keyCode: Int(event.keyCode), modifiers: mods,
                  keyName: Self.name(forKeyCode: Int(event.keyCode), characters: event.charactersIgnoringModifiers))
    }

    init(keyCode: Int, modifiers: UInt32, keyName: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyName = keyName
    }

    private static func name(forKeyCode code: Int, characters: String?) -> String {
        let special: [Int: String] = [
            kVK_Space: "Space", kVK_Escape: "Esc", kVK_Tab: "Tab", kVK_Return: "Return",
            kVK_Delete: "Delete", kVK_ForwardDelete: "⌦", kVK_LeftArrow: "←", kVK_RightArrow: "→",
            kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_Home: "Home", kVK_End: "End",
            kVK_PageUp: "Page Up", kVK_PageDown: "Page Down",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        ]
        if let name = special[code] { return name }
        if let characters, !characters.isEmpty { return characters.uppercased() }
        return "Key \(code)"
    }
}

enum Settings {
    static let slotCount = 4
    private static let defaults = UserDefaults.standard

    /// The app assigned to each slot (nil = empty, or the app was deleted).
    static var slots: [URL?] {
        get {
            let paths = defaults.stringArray(forKey: "slots") ?? []
            return (0..<slotCount).map { i in
                guard i < paths.count, !paths[i].isEmpty,
                      FileManager.default.fileExists(atPath: paths[i]) else { return nil }
                return URL(fileURLWithPath: paths[i])
            }
        }
        set { defaults.set(newValue.map { $0?.path ?? "" }, forKey: "slots") }
    }

    static var hotkey: Hotkey {
        get {
            guard defaults.object(forKey: "hotkeyCode") != nil else { return .default }
            return Hotkey(keyCode: defaults.integer(forKey: "hotkeyCode"),
                          modifiers: UInt32(defaults.integer(forKey: "hotkeyModifiers")),
                          keyName: defaults.string(forKey: "hotkeyName") ?? "?")
        }
        set {
            defaults.set(newValue.keyCode, forKey: "hotkeyCode")
            defaults.set(Int(newValue.modifiers), forKey: "hotkeyModifiers")
            defaults.set(newValue.keyName, forKey: "hotkeyName")
        }
    }

    static var hideMenuBarIcon: Bool {
        get { defaults.bool(forKey: "hideMenuBarIcon") }
        set { defaults.set(newValue, forKey: "hideMenuBarIcon") }
    }

    static var hasWelcomed: Bool {
        get { defaults.bool(forKey: "welcomed") }
        set { defaults.set(newValue, forKey: "welcomed") }
    }
}

func appName(_ url: URL) -> String {
    let name = FileManager.default.displayName(atPath: url.path)
    return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
}
