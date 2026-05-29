import Foundation

/// A pragmatic VT100/VT220/xterm parser. Covers what an interactive shell and
/// common TUIs need: printable UTF-8, the C0 controls, CSI cursor motion / erase /
/// SGR / insert-delete, DEC private modes (cursor keys, cursor visibility, alt
/// screen), OSC (title, consumed), and the common ESC sequences. Full xterm 366
/// conformance is a later milestone (see README terminal risk row).
final class VTParser {
    private let grid: TerminalGrid

    private enum State { case ground, esc, csi, osc, oscEsc, charset }
    private var state: State = .ground

    private var params: [Int] = []
    private var paramAccum: Int?
    private var privateMarker: UInt8?

    // Incremental UTF-8 decoding (multibyte only appears as printable in ground).
    private var utf8Buf: [UInt8] = []
    private var utf8Needed = 0

    init(grid: TerminalGrid) { self.grid = grid }

    func feed(_ bytes: [UInt8]) { for b in bytes { step(b) } }

    private func step(_ b: UInt8) {
        switch state {
        case .ground:    ground(b)
        case .esc:       escape(b)
        case .csi:       csi(b)
        case .osc:       osc(b)
        case .oscEsc:    if b == 0x5C { state = .ground } else { state = .osc }
        case .charset:   state = .ground            // consume the charset designator
        }
    }

    // MARK: - Ground

    private func ground(_ b: UInt8) {
        if utf8Needed > 0 {
            if b & 0xC0 == 0x80 {
                utf8Buf.append(b); utf8Needed -= 1
                if utf8Needed == 0 { flushScalar() }
                return
            }
            utf8Buf.removeAll(); utf8Needed = 0   // malformed; fall through
        }

        switch b {
        case 0x1B: state = .esc
        case 0x07: break                          // BEL
        case 0x08: grid.backspace()
        case 0x09: grid.tab()
        case 0x0A, 0x0B, 0x0C: grid.lineFeed()
        case 0x0D: grid.carriageReturn()
        case 0x00..<0x20, 0x7F: break             // other C0 / DEL ignored
        case 0x20..<0x80: grid.put(UnicodeScalar(b))
        default:                                   // 0x80+: start UTF-8 multibyte
            if b & 0xE0 == 0xC0 { utf8Buf = [b]; utf8Needed = 1 }
            else if b & 0xF0 == 0xE0 { utf8Buf = [b]; utf8Needed = 2 }
            else if b & 0xF8 == 0xF0 { utf8Buf = [b]; utf8Needed = 3 }
        }
    }

    private func flushScalar() {
        let s = String(decoding: utf8Buf, as: UTF8.self)
        utf8Buf.removeAll()
        if let scalar = s.unicodeScalars.first { grid.put(scalar) }
    }

    // MARK: - Escape

    private func escape(_ b: UInt8) {
        switch b {
        case 0x5B: params = []; paramAccum = nil; privateMarker = nil; state = .csi   // '['
        case 0x5D: state = .osc                                                       // ']'
        case 0x4D: grid.cursorUp(1); state = .ground                                  // RI
        case 0x37: grid.saveCursor(); state = .ground                                 // DECSC
        case 0x38: grid.restoreCursor(); state = .ground                              // DECRC
        case 0x63: grid.eraseInDisplay(2); grid.setCursor(row: 1, col: 1); state = .ground // RIS
        case 0x28, 0x29, 0x2A, 0x2B: state = .charset                                 // '(' ')' '*' '+'
        default: state = .ground
        }
    }

    // MARK: - CSI

    private func csi(_ b: UInt8) {
        switch b {
        case 0x30...0x39:                          // digit
            paramAccum = (paramAccum ?? 0) * 10 + Int(b - 0x30)
        case 0x3B:                                 // ';'
            params.append(paramAccum ?? 0); paramAccum = nil
        case 0x3C...0x3F:                          // '<' '=' '>' '?'
            privateMarker = b
        case 0x40...0x7E:                          // final byte
            if let acc = paramAccum { params.append(acc); paramAccum = nil }
            dispatchCSI(final: b)
            state = .ground
        default:
            break
        }
    }

    private func param(_ i: Int, _ def: Int) -> Int {
        (i < params.count) ? params[i] : def
    }

    private func dispatchCSI(final: UInt8) {
        let isPrivate = (privateMarker == 0x3F)   // '?'
        switch final {
        case 0x41: grid.cursorUp(param(0, 1))                              // A
        case 0x42: grid.cursorDown(param(0, 1))                            // B
        case 0x43: grid.cursorForward(param(0, 1))                         // C
        case 0x44: grid.cursorBack(param(0, 1))                            // D
        case 0x45: grid.cursorDown(param(0, 1)); grid.carriageReturn()     // E
        case 0x46: grid.cursorUp(param(0, 1)); grid.carriageReturn()       // F
        case 0x47: grid.setColumn(param(0, 1))                             // G
        case 0x48, 0x66: grid.setCursor(row: param(0, 1), col: param(1, 1))// H / f
        case 0x4A: grid.eraseInDisplay(param(0, 0))                        // J
        case 0x4B: grid.eraseInLine(param(0, 0))                           // K
        case 0x40: grid.insertBlankChars(param(0, 1))                      // @
        case 0x50: grid.deleteChars(param(0, 1))                           // P
        case 0x64: grid.setRow(param(0, 1))                                // d
        case 0x6D: grid.applySGR(params)                                   // m
        case 0x68: if isPrivate { for p in normalizedParams() { grid.setMode(p, enabled: true) } }   // h
        case 0x6C: if isPrivate { for p in normalizedParams() { grid.setMode(p, enabled: false) } }  // l
        case 0x73: grid.saveCursor()                                       // s
        case 0x75: grid.restoreCursor()                                    // u
        default: break
        }
    }

    private func normalizedParams() -> [Int] { params.isEmpty ? [] : params }

    // MARK: - OSC (e.g. window title) — consumed; terminated by BEL or ESC \

    private func osc(_ b: UInt8) {
        if b == 0x07 { state = .ground }          // BEL
        else if b == 0x1B { state = .oscEsc }     // ESC (expect '\')
    }
}
