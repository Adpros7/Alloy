import AppKit

/// Hosts the sidebar panels and swaps between them as the activity bar selection
/// changes. The selected child view fills the (vibrant) sidebar split item.
///
/// Activity bar indices: 0 Explorer · 1 Search · 2 Source Control ·
/// 3 Run and Debug · 4 Extensions. Phase 2 implements Explorer + Source Control;
/// the rest show a placeholder until their phase lands.
final class SidebarContainerViewController: NSViewController {
    let explorer = SidebarViewController()
    let sourceControl = SourceControlViewController()

    private var placeholders: [Int: NSViewController] = [:]
    private var current: NSViewController?

    override func loadView() {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor(hex: 0x090B0D).cgColor
        self.view = v
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        show(index: 0)
    }

    func show(index: Int) {
        let vc: NSViewController
        switch index {
        case 0:  vc = explorer
        case 2:  vc = sourceControl
        default: vc = placeholder(for: index)
        }
        swap(to: vc)
    }

    private func swap(to vc: NSViewController) {
        guard current !== vc else { return }
        current?.view.removeFromSuperview()
        current?.removeFromParent()
        addChild(vc)
        vc.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(vc.view)
        NSLayoutConstraint.activate([
            vc.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            vc.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            vc.view.topAnchor.constraint(equalTo: view.topAnchor),
            vc.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        current = vc
    }

    private func placeholder(for index: Int) -> NSViewController {
        if let p = placeholders[index] { return p }
        let titles: [Int: String] = [1: "SEARCH", 3: "RUN AND DEBUG", 4: "EXTENSIONS"]
        let p = PlaceholderPanelViewController(title: titles[index] ?? "PANEL")
        placeholders[index] = p
        return p
    }
}

/// A simple titled sidebar panel for features not yet implemented.
final class PlaceholderPanelViewController: NSViewController {
    private let titleText: String
    init(title: String) { self.titleText = title; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let container = NSView()
        let header = NSTextField(labelWithString: titleText)
        header.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        header.textColor = Theme.sidebarHeaderFg
        header.translatesAutoresizingMaskIntoConstraints = false

        let note = NSTextField(labelWithString: "Coming in a later phase.")
        note.font = Theme.uiFontSmall
        note.textColor = Theme.sidebarHeaderFg
        note.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(header)
        container.addSubview(note)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: container.topAnchor, constant: 30),
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            note.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 16),
            note.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            note.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -12),
        ])
        self.view = container
    }
}
