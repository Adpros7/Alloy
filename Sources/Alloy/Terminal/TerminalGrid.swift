import Foundation

/// The terminal screen model: a live `screen` of rows×cols cells plus a capped
/// `scrollback` of lines that have scrolled off the top (primary screen only).
/// All cursor motion, erasing, SGR and alt-screen logic lives here; the VT parser
/// drives it and the view renders it.
final class TerminalGrid {
    private(set) var rows: Int
    private(set) var cols: Int

    private(set) var screen: [[Cell]]
    private(set) var scrollback: [[Cell]] = []
    private let maxScrollback = 5000

    var cursorRow = 0
    var cursorCol = 0
    var cursorVisible = true

    // Current pen.
    private var curFg: TermColor = .defaultFg
    private var curBg: TermColor = .defaultBg
    private var curAttrs: CellAttrs = []

    // Cursor-keys application mode (DECCKM, CSI ?1 h/l).
    private(set) var applicationCursorKeys = false

    // Alt screen state.
    private(set) var altActive = false
    private var savedPrimaryScreen: [[Cell]]?
    private var savedCursor: (Int, Int)?

    init(rows: Int, cols: Int) {
        self.rows = max(1, rows)
        self.cols = max(1, cols)
        self.screen = TerminalGrid.blankScreen(rows: self.rows, cols: self.cols)
    }

    /// Total renderable lines (history + live screen). Alt screen has no history.
    var totalLines: Int { (altActive ? 0 : scrollback.count) + rows }

    /// Line `i` in the combined (scrollback + screen) coordinate space.
    func renderLine(_ i: Int) -> [Cell] {
        let sb = altActive ? 0 : scrollback.count
        if i < sb { return scrollback[i] }
        let s = i - sb
        return (s >= 0 && s < rows) ? screen[s] : TerminalGrid.blankRow(cols: cols)
    }

    /// Cursor's line index in the combined space.
    var cursorRenderLine: Int { (altActive ? 0 : scrollback.count) + cursorRow }

    // MARK: - Resize

    func resize(rows newRows: Int, cols newCols: Int) {
        let nr = max(1, newRows), nc = max(1, newCols)
        guard nr != rows || nc != cols else { return }

        var newScreen = TerminalGrid.blankScreen(rows: nr, cols: nc)
        for r in 0..<min(rows, nr) {
            for c in 0..<min(cols, nc) {
                newScreen[r][c] = screen[r][c]
            }
        }
        screen = newScreen
        rows = nr
        cols = nc
        cursorRow = min(cursorRow, rows - 1)
        cursorCol = min(cursorCol, cols - 1)
    }

    // MARK: - Printing & control

    func put(_ scalar: UnicodeScalar) {
        if cursorCol >= cols {
            cursorCol = 0
            lineFeed()
        }
        screen[cursorRow][cursorCol] = Cell(scalar: scalar, fg: curFg, bg: curBg, attrs: curAttrs)
        cursorCol += 1
    }

    func carriageReturn() { cursorCol = 0 }

    func lineFeed() {
        cursorRow += 1
        if cursorRow >= rows {
            scrollUp(1)
            cursorRow = rows - 1
        }
    }

    func backspace() { if cursorCol > 0 { cursorCol -= 1 } }

    func tab() {
        let next = ((cursorCol / 8) + 1) * 8
        cursorCol = min(next, cols - 1)
    }

    func scrollUp(_ n: Int) {
        for _ in 0..<n {
            let top = screen.removeFirst()
            if !altActive {
                scrollback.append(top)
                if scrollback.count > maxScrollback { scrollback.removeFirst() }
            }
            screen.append(TerminalGrid.blankRow(cols: cols))
        }
    }

    // MARK: - Cursor

    func cursorUp(_ n: Int)      { cursorRow = max(0, cursorRow - max(1, n)) }
    func cursorDown(_ n: Int)    { cursorRow = min(rows - 1, cursorRow + max(1, n)) }
    func cursorForward(_ n: Int) { cursorCol = min(cols - 1, cursorCol + max(1, n)) }
    func cursorBack(_ n: Int)    { cursorCol = max(0, cursorCol - max(1, n)) }

    /// 1-based row/col from CSI H; clamped.
    func setCursor(row: Int, col: Int) {
        cursorRow = min(max(0, row - 1), rows - 1)
        cursorCol = min(max(0, col - 1), cols - 1)
    }
    func setColumn(_ col: Int) { cursorCol = min(max(0, col - 1), cols - 1) }
    func setRow(_ row: Int)    { cursorRow = min(max(0, row - 1), rows - 1) }

    func saveCursor()    { savedCursor = (cursorRow, cursorCol) }
    func restoreCursor() { if let s = savedCursor { cursorRow = s.0; cursorCol = s.1 } }

    // MARK: - Erase

    func eraseInLine(_ mode: Int) {
        let blank = Cell(scalar: " ", fg: .defaultFg, bg: curBg, attrs: [])
        switch mode {
        case 0: for c in cursorCol..<cols { screen[cursorRow][c] = blank }
        case 1: for c in 0...min(cursorCol, cols - 1) { screen[cursorRow][c] = blank }
        case 2: for c in 0..<cols { screen[cursorRow][c] = blank }
        default: break
        }
    }

    func eraseInDisplay(_ mode: Int) {
        let blank = Cell(scalar: " ", fg: .defaultFg, bg: curBg, attrs: [])
        switch mode {
        case 0:
            eraseInLine(0)
            if cursorRow + 1 < rows { for r in (cursorRow + 1)..<rows { screen[r] = Array(repeating: blank, count: cols) } }
        case 1:
            if cursorRow > 0 { for r in 0..<cursorRow { screen[r] = Array(repeating: blank, count: cols) } }
            eraseInLine(1)
        case 2, 3:
            for r in 0..<rows { screen[r] = Array(repeating: blank, count: cols) }
        default: break
        }
    }

    func deleteChars(_ n: Int) {
        let count = max(1, n)
        var row = screen[cursorRow]
        for _ in 0..<count where cursorCol < row.count { row.remove(at: cursorCol) }
        while row.count < cols { row.append(Cell(scalar: " ", fg: .defaultFg, bg: curBg, attrs: [])) }
        screen[cursorRow] = row
    }

    func insertBlankChars(_ n: Int) {
        let count = max(1, n)
        var row = screen[cursorRow]
        let blank = Cell(scalar: " ", fg: .defaultFg, bg: curBg, attrs: [])
        for _ in 0..<count where cursorCol <= row.count { row.insert(blank, at: cursorCol) }
        if row.count > cols { row.removeLast(row.count - cols) }
        screen[cursorRow] = row
    }

    // MARK: - SGR (colors / attributes)

    func applySGR(_ params: [Int]) {
        let p = params.isEmpty ? [0] : params
        var i = 0
        while i < p.count {
            let code = p[i]
            switch code {
            case 0:  curFg = .defaultFg; curBg = .defaultBg; curAttrs = []
            case 1:  curAttrs.insert(.bold)
            case 2:  curAttrs.insert(.dim)
            case 3:  curAttrs.insert(.italic)
            case 4:  curAttrs.insert(.underline)
            case 7:  curAttrs.insert(.inverse)
            case 22: curAttrs.remove(.bold); curAttrs.remove(.dim)
            case 23: curAttrs.remove(.italic)
            case 24: curAttrs.remove(.underline)
            case 27: curAttrs.remove(.inverse)
            case 30...37: curFg = .indexed(code - 30)
            case 39: curFg = .defaultFg
            case 40...47: curBg = .indexed(code - 40)
            case 49: curBg = .defaultBg
            case 90...97: curFg = .indexed(code - 90 + 8)
            case 100...107: curBg = .indexed(code - 100 + 8)
            case 38, 48:
                let isFg = (code == 38)
                if i + 1 < p.count, p[i + 1] == 5, i + 2 < p.count {
                    let c = TermColor.indexed(p[i + 2]); if isFg { curFg = c } else { curBg = c }
                    i += 2
                } else if i + 1 < p.count, p[i + 1] == 2, i + 4 < p.count {
                    let c = TermColor.rgb(UInt8(min(255, p[i + 2])), UInt8(min(255, p[i + 3])), UInt8(min(255, p[i + 4])))
                    if isFg { curFg = c } else { curBg = c }
                    i += 4
                }
            default: break
            }
            i += 1
        }
    }

    // MARK: - DEC private modes

    func setMode(_ code: Int, enabled: Bool) {
        switch code {
        case 1:    applicationCursorKeys = enabled            // DECCKM
        case 25:   cursorVisible = enabled                    // show/hide cursor
        case 1047, 1049, 47:                                  // alt screen
            if enabled { enterAltScreen() } else { exitAltScreen() }
        default: break
        }
    }

    private func enterAltScreen() {
        guard !altActive else { return }
        savedPrimaryScreen = screen
        savedCursor = (cursorRow, cursorCol)
        altActive = true
        screen = TerminalGrid.blankScreen(rows: rows, cols: cols)
        cursorRow = 0; cursorCol = 0
    }

    private func exitAltScreen() {
        guard altActive else { return }
        altActive = false
        if let s = savedPrimaryScreen { screen = s }
        if let c = savedCursor { cursorRow = c.0; cursorCol = c.1 }
        savedPrimaryScreen = nil
    }

    // MARK: - Helpers

    static func blankRow(cols: Int) -> [Cell] {
        Array(repeating: Cell(), count: max(1, cols))
    }
    static func blankScreen(rows: Int, cols: Int) -> [[Cell]] {
        Array(repeating: blankRow(cols: cols), count: max(1, rows))
    }
}
