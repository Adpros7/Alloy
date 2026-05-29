import AppKit

/// Bottom status bar on Liquid Glass. Git branch on the left; cursor position,
/// indentation, encoding, EOL and language on the right — matching VS Code.
final class StatusBarView: NSView {
    private let panel = GlassPanelView(cornerRadius: 0)

    private let branchLabel   = StatusBarView.makeLabel("⎇ main")
    private let positionLabel = StatusBarView.makeLabel("Ln 1, Col 1")
    private let indentLabel   = StatusBarView.makeLabel("Spaces: 4")
    private let encodingLabel = StatusBarView.makeLabel("UTF-8")
    private let eolLabel      = StatusBarView.makeLabel("LF")
    private let langLabel     = StatusBarView.makeLabel("Plain Text")

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        addSubview(panel)
        NSLayoutConstraint.activate([
            panel.leadingAnchor.constraint(equalTo: leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: trailingAnchor),
            panel.topAnchor.constraint(equalTo: topAnchor),
            panel.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        let host = panel.body

        let left = NSStackView(views: [branchLabel])
        left.orientation = .horizontal; left.spacing = 12
        left.translatesAutoresizingMaskIntoConstraints = false

        let right = NSStackView(views: [positionLabel, indentLabel, encodingLabel, eolLabel, langLabel])
        right.orientation = .horizontal; right.spacing = 16
        right.translatesAutoresizingMaskIntoConstraints = false

        host.addSubview(left); host.addSubview(right)
        NSLayoutConstraint.activate([
            left.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 14),
            left.centerYAnchor.constraint(equalTo: host.centerYAnchor),
            right.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -14),
            right.centerYAnchor.constraint(equalTo: host.centerYAnchor),
        ])
    }

    func setCursor(line: Int, col: Int) { positionLabel.stringValue = "Ln \(line), Col \(col)" }
    func setLanguage(_ id: String) { langLabel.stringValue = Self.pretty(id) }
    func setBranch(_ name: String) { branchLabel.stringValue = "⎇ \(name)" }

    private static func pretty(_ id: String) -> String {
        switch id {
        case "plaintext": return "Plain Text"
        case "javascript": return "JavaScript"
        case "typescript": return "TypeScript"
        case "json": return "JSON"
        default: return id.prefix(1).uppercased() + id.dropFirst()
        }
    }

    private static func makeLabel(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = Theme.uiFontSmall
        l.textColor = Theme.statusBarForeground
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }
}
