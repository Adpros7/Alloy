import Foundation

/// One keybinding row, matching VS Code's keybindings.json schema.
struct KeyBinding: Codable {
    let key: String
    let command: String
    let when: String?
}

/// Loads VS Code-format default keybindings and (later) user overrides from
/// `~/Library/Application Support/Alloy/keybindings.json`.
///
/// Phase 1: the core File/Edit/View commands are served by the AppKit main menu's
/// key equivalents (the idiomatic macOS path). This manager owns the full binding
/// table that the upcoming command palette + NSEvent monitor will dispatch through.
final class KeyBindingManager {
    private(set) var defaults: [KeyBinding] = []
    private(set) var userOverrides: [KeyBinding] = []

    init() {
        loadDefaults()
        loadUserOverrides()
    }

    /// Effective bindings: user overrides take precedence over defaults by key.
    var effective: [KeyBinding] {
        var byKey: [String: KeyBinding] = [:]
        for b in defaults { byKey[b.key] = b }
        for b in userOverrides { byKey[b.key] = b }
        return Array(byKey.values)
    }

    private func loadDefaults() {
        guard let url = Bundle.module.url(forResource: "DefaultKeyBindings", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let parsed = try? JSONDecoder().decode([KeyBinding].self, from: data) else {
            return
        }
        defaults = parsed
    }

    private func loadUserOverrides() {
        let url = Self.userKeybindingsURL
        guard let data = try? Data(contentsOf: url),
              let parsed = try? JSONDecoder().decode([KeyBinding].self, from: data) else {
            return
        }
        userOverrides = parsed
    }

    static var userKeybindingsURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Alloy/keybindings.json")
    }
}
