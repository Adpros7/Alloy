import AppKit

/// A single key + modifier combination.
struct KeyCombo: Equatable {
    let keyCode: UInt16
    let modifiers: NSEvent.ModifierFlags

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection([.command, .shift, .option, .control])
    }
}

/// A binding: either a single combo or a two-key chord (first, then second).
enum KeySequence: Equatable {
    case single(KeyCombo)
    case chord(KeyCombo, KeyCombo)   // first key, then second key
}

struct KeyBinding {
    let sequence: KeySequence
    let command: String
    let when: String?
}

/// Intercepts all key events before AppKit's standard handling.
/// Loaded from DefaultKeyBindings.json at startup; user overrides layer on top.
final class KeyBindingManager {

    static let shared = KeyBindingManager()

    private var bindings: [KeyBinding] = []
    private var pendingChordFirst: KeyCombo?

    private init() {
        loadDefaults()
        loadUserOverrides()
    }

    // MARK: - Loading

    private func loadDefaults() {
        guard let url = Bundle.main.url(forResource: "DefaultKeyBindings", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: String]]
        else { return }

        bindings = json.compactMap { dict in
            guard let keyStr = dict["key"], let command = dict["command"] else { return nil }
            guard let seq = parseKeySequence(keyStr) else { return nil }
            return KeyBinding(sequence: seq, command: command, when: dict["when"])
        }
    }

    private func loadUserOverrides() {
        let url = userKeybindingsURL()
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: String]]
        else { return }

        let overrides = json.compactMap { dict -> KeyBinding? in
            guard let keyStr = dict["key"], let command = dict["command"] else { return nil }
            guard let seq = parseKeySequence(keyStr) else { return nil }
            return KeyBinding(sequence: seq, command: command, when: dict["when"])
        }
        bindings = overrides + bindings
    }

    private func userKeybindingsURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Alloy", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("keybindings.json")
    }

    // MARK: - Event handling

    /// Returns true if the event was consumed (handled as a command).
    func handleKeyDown(_ event: NSEvent) -> Bool {
        let combo = KeyCombo(keyCode: event.keyCode, modifiers: event.modifierFlags)

        // Check if we're completing a chord.
        if let first = pendingChordFirst {
            pendingChordFirst = nil
            if let binding = bindings.first(where: {
                if case .chord(let a, let b) = $0.sequence { return a == first && b == combo }
                return false
            }) {
                return fire(command: binding.command)
            }
            return true  // swallow incomplete chord
        }

        // Check for chord starters.
        let isStarter = bindings.contains {
            if case .chord(let a, _) = $0.sequence { return a == combo }
            return false
        }
        if isStarter {
            pendingChordFirst = combo
            return true
        }

        if let binding = bindings.first(where: {
            if case .single(let k) = $0.sequence { return k == combo }
            return false
        }) {
            return fire(command: binding.command)
        }
        return false
    }

    private func fire(command: String) -> Bool {
        // Route to the active responder chain.
        switch command {
        case "workbench.action.quickOpen":
            NSApp.sendAction(#selector(AppCommands.quickOpen), to: nil, from: nil)
        case "workbench.action.showCommands":
            NSApp.sendAction(#selector(AppCommands.openCommandPalette), to: nil, from: nil)
        case "workbench.action.terminal.toggleTerminal":
            NSApp.sendAction(#selector(AppCommands.toggleTerminal), to: nil, from: nil)
        case "workbench.action.toggleSidebarVisibility":
            NSApp.sendAction(#selector(AppCommands.toggleSidebar), to: nil, from: nil)
        case "workbench.action.files.newUntitledFile":
            NSApp.sendAction(#selector(AppCommands.newFile), to: nil, from: nil)
        case "workbench.action.files.openFile":
            NSApp.sendAction(#selector(AppCommands.openFile), to: nil, from: nil)
        case "workbench.action.files.save":
            NSApp.sendAction(#selector(AppCommands.saveFile), to: nil, from: nil)
        case "workbench.action.files.saveAs":
            NSApp.sendAction(#selector(AppCommands.saveFileAs), to: nil, from: nil)
        case "workbench.action.openSettings":
            NSApp.sendAction(#selector(MainWindowController.openSettings), to: nil, from: nil)
        case "undo":
            NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
        case "redo":
            NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
        default:
            // Unknown command — don't consume; let AppKit handle.
            return false
        }
        return true
    }

    // MARK: - Key combo parsing

    private func parseKeySequence(_ string: String) -> KeySequence? {
        let parts = string.split(separator: " ", maxSplits: 1).map(String.init)
        if parts.count == 2 {
            guard let first = parseSingleCombo(parts[0]),
                  let second = parseSingleCombo(parts[1]) else { return nil }
            return .chord(first, second)
        }
        return parseSingleCombo(string).map { .single($0) }
    }

    private func parseSingleCombo(_ string: String) -> KeyCombo? {
        var mods: NSEvent.ModifierFlags = []
        let tokens = string.lowercased().components(separatedBy: "+")
        var keyToken: String = ""

        for token in tokens {
            switch token {
            case "cmd", "command":  mods.insert(.command)
            case "shift":           mods.insert(.shift)
            case "option", "alt":   mods.insert(.option)
            case "ctrl", "control": mods.insert(.control)
            default: keyToken = token
            }
        }

        guard !keyToken.isEmpty, let code = keyCode(for: keyToken) else { return nil }
        return KeyCombo(keyCode: code, modifiers: mods)
    }

    private func keyCode(for key: String) -> UInt16? {
        // Common key name → macOS virtual key code mapping.
        let map: [String: UInt16] = [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
            "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
            "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
            "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
            "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
            "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43,
            "/": 44, "n": 45, "m": 46, ".": 47,
            "tab": 48, "space": 49, "`": 50,
            "delete": 51, "escape": 53, "esc": 53,
            "return": 36, "enter": 36,
            "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
            "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
            "up": 126, "down": 125, "left": 123, "right": 124,
            "pageup": 116, "pagedown": 121, "home": 115, "end": 119,
            "comma": 43,
        ]
        return map[key]
    }
}
