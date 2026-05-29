import AppKit

/// Ties a PTY-backed shell to a grid, a parser, and a view. Output flows
/// PTY → parser → grid → view; input flows view → PTY.
final class TerminalSession {
    let grid: TerminalGrid
    let view: TerminalView
    private let parser: VTParser
    private let pty = PTYProcess()

    var onExit: (() -> Void)?

    init(rows: Int = 24, cols: Int = 80) {
        grid = TerminalGrid(rows: rows, cols: cols)
        parser = VTParser(grid: grid)
        view = TerminalView(grid: grid)

        view.onInput = { [weak self] data in self?.pty.write(data) }
        view.onResize = { [weak self] r, c in self?.pty.resize(rows: r, cols: c) }

        pty.onData = { [weak self] data in
            guard let self else { return }
            self.parser.feed([UInt8](data))
            self.view.refresh()
        }
        pty.onExit = { [weak self] in self?.onExit?() }
    }

    func start() {
        guard !pty.isRunning else { return }
        pty.start(rows: grid.rows, cols: grid.cols)
    }

    func terminate() { pty.terminate() }
}
