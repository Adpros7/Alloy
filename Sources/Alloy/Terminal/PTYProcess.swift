import Foundation
import CPTY
import Darwin

/// Spawns a shell attached to a pseudo-terminal and streams its output.
/// Reading happens on a background GCD source; `onData`/`onExit` fire on main.
final class PTYProcess {
    private(set) var masterFD: Int32 = -1
    private var pid: pid_t = -1
    private var readSource: DispatchSourceRead?
    private let ioQueue = DispatchQueue(label: "com.alloy.pty.io")

    var onData: ((Data) -> Void)?
    var onExit: (() -> Void)?

    var isRunning: Bool { pid > 0 }

    /// Start the shell. Defaults to `$SHELL` or `/bin/zsh`.
    func start(shell: String? = nil, rows: Int, cols: Int) {
        let shellPath = shell ?? ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"

        var master: Int32 = -1
        let childPid = shellPath.withCString { cstr in
            alloy_pty_spawn(cstr, Int32(rows), Int32(cols), &master)
        }
        guard childPid > 0, master >= 0 else { return }
        pid = childPid
        masterFD = master

        let source = DispatchSource.makeReadSource(fileDescriptor: master, queue: ioQueue)
        source.setEventHandler { [weak self] in self?.readAvailable() }
        source.setCancelHandler { [weak self] in
            if let fd = self?.masterFD, fd >= 0 { close(fd) }
        }
        readSource = source
        source.resume()
    }

    private func readAvailable() {
        var buffer = [UInt8](repeating: 0, count: 1 << 16)
        let n = read(masterFD, &buffer, buffer.count)
        if n > 0 {
            let data = Data(buffer[0..<n])
            DispatchQueue.main.async { [weak self] in self?.onData?(data) }
        } else if n == 0 || (n < 0 && errno != EAGAIN && errno != EINTR) {
            DispatchQueue.main.async { [weak self] in self?.onExit?() }
            readSource?.cancel()
        }
    }

    func write(_ data: Data) {
        guard masterFD >= 0 else { return }
        ioQueue.async { [masterFD] in
            data.withUnsafeBytes { raw in
                var ptr = raw.bindMemory(to: UInt8.self).baseAddress!
                var remaining = data.count
                while remaining > 0 {
                    let w = Darwin.write(masterFD, ptr, remaining)
                    if w <= 0 { break }
                    ptr = ptr.advanced(by: w)
                    remaining -= w
                }
            }
        }
    }

    func write(_ string: String) { write(Data(string.utf8)) }

    func resize(rows: Int, cols: Int) {
        guard masterFD >= 0 else { return }
        alloy_pty_set_size(masterFD, Int32(rows), Int32(cols))
    }

    func terminate() {
        if pid > 0 { kill(pid, SIGTERM) }
        readSource?.cancel()
        readSource = nil
        pid = -1
        masterFD = -1
    }

    deinit { terminate() }
}
