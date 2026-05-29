import Foundation

/// One open text document: its rope buffer, on-disk location, and dirty state.
final class Document {
    let buffer: TextBuffer
    private(set) var url: URL?
    var isDirty: Bool = false

    var displayName: String { url?.lastPathComponent ?? "Untitled" }

    /// VS Code-style language id derived from the file extension.
    var languageId: String { Document.languageId(for: url) }

    init(url: URL) throws {
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        self.buffer = TextBuffer(text: text)
        self.url = url
        self.isDirty = false
    }

    init(untitledWith text: String = "") {
        self.buffer = TextBuffer(text: text)
        self.url = nil
        self.isDirty = false
    }

    func save() throws {
        guard let url else { throw DocumentError.noURL }
        try buffer.text().write(to: url, atomically: true, encoding: .utf8)
        isDirty = false
    }

    func save(to newURL: URL) throws {
        try buffer.text().write(to: newURL, atomically: true, encoding: .utf8)
        self.url = newURL
        isDirty = false
    }

    static func languageId(for url: URL?) -> String {
        guard let ext = url?.pathExtension.lowercased() else { return "plaintext" }
        switch ext {
        case "swift": return "swift"
        case "rs": return "rust"
        case "py": return "python"
        case "js", "mjs", "cjs": return "javascript"
        case "ts": return "typescript"
        case "tsx": return "typescriptreact"
        case "jsx": return "javascriptreact"
        case "json": return "json"
        case "yaml", "yml": return "yaml"
        case "toml": return "toml"
        case "md", "markdown": return "markdown"
        case "html", "htm": return "html"
        case "css": return "css"
        case "c", "h": return "c"
        case "cpp", "cc", "cxx", "hpp": return "cpp"
        case "go": return "go"
        case "java": return "java"
        case "rb": return "ruby"
        case "sh", "bash", "zsh": return "shellscript"
        default: return "plaintext"
        }
    }
}

enum DocumentError: Error {
    case noURL
}
