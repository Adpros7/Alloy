import Foundation

/// Per-line change kind for gutter decorations.
enum GitLineStatus { case added, modified, deleted }

/// One entry from `git status --porcelain`. A class so it can serve as a stable
/// NSOutlineView item (which tracks rows by reference identity).
final class GitChange {
    let path: String            // relative to repo root
    let index: Character        // staged status (X)
    let work: Character         // unstaged status (Y)

    init(path: String, index: Character, work: Character) {
        self.path = path
        self.index = index
        self.work = work
    }

    var isStaged: Bool { index != " " && index != "?" }
    var isUnstaged: Bool { work != " " || (index == "?" && work == "?") }

    /// A single-letter badge for display.
    var badge: String {
        if index == "?" && work == "?" { return "U" }      // untracked
        let c = isStaged ? index : work
        return String(c)
    }
}

/// Git integration via the `git` CLI (same model VS Code uses). All calls are
/// synchronous; callers run them off the main thread and marshal results back.
final class GitService {
    let root: URL
    private init(root: URL) { self.root = root }

    /// Find the repository containing `url`, if any.
    static func discover(at url: URL) -> GitService? {
        let r = run(["rev-parse", "--show-toplevel"], cwd: url)
        let path = r.out.trimmingCharacters(in: .whitespacesAndNewlines)
        guard r.code == 0, !path.isEmpty else { return nil }
        return GitService(root: URL(fileURLWithPath: path))
    }

    func branch() -> String? {
        let r = GitService.run(["rev-parse", "--abbrev-ref", "HEAD"], cwd: root)
        let b = r.out.trimmingCharacters(in: .whitespacesAndNewlines)
        return (r.code == 0 && !b.isEmpty) ? b : nil
    }

    /// All local branch names (current branch first).
    func branches() -> [String] {
        let r = GitService.run(["branch", "--format=%(refname:short)"], cwd: root)
        guard r.code == 0 else { return [] }
        let all = r.out.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let cur = branch() else { return all }
        return [cur] + all.filter { $0 != cur }
    }

    /// Commits ahead of / behind the upstream, if any.
    func aheadBehind() -> (ahead: Int, behind: Int)? {
        let r = GitService.run(["rev-list", "--left-right", "--count", "@{upstream}...HEAD"], cwd: root)
        guard r.code == 0 else { return nil }
        let parts = r.out.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
        guard parts.count == 2, let behind = Int(parts[0]), let ahead = Int(parts[1]) else { return nil }
        return (ahead, behind)
    }

    func status() -> [GitChange] {
        let r = GitService.run(["status", "--porcelain"], cwd: root)
        guard r.code == 0 else { return [] }
        var changes: [GitChange] = []
        for raw in r.out.split(separator: "\n", omittingEmptySubsequences: true) {
            let s = String(raw)
            guard s.count >= 3 else { continue }
            let chars = Array(s)
            var path = String(s.dropFirst(3))
            if let arrow = path.range(of: " -> ") { path = String(path[arrow.upperBound...]) }  // renames
            path = path.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            changes.append(GitChange(path: path, index: chars[0], work: chars[1]))
        }
        return changes
    }

    /// Per-line decoration map (0-based editor line → status) for a file vs HEAD.
    func diffLineStatus(relativePath path: String) -> [Int: GitLineStatus] {
        let r = GitService.run(["diff", "HEAD", "-U0", "--", path], cwd: root)
        guard r.code == 0 else { return [:] }
        return GitService.parseHunks(r.out)
    }

    func relativePath(for url: URL) -> String? {
        let full = url.standardizedFileURL.path
        let base = root.standardizedFileURL.path
        guard full.hasPrefix(base) else { return nil }
        return String(full.dropFirst(base.count).drop(while: { $0 == "/" }))
    }

    // MARK: Mutations

    func stage(_ path: String)   { _ = GitService.run(["add", "--", path], cwd: root) }
    func unstage(_ path: String) { _ = GitService.run(["restore", "--staged", "--", path], cwd: root) }
    func stageAll()              { _ = GitService.run(["add", "-A"], cwd: root) }
    func discard(_ path: String) { _ = GitService.run(["checkout", "HEAD", "--", path], cwd: root) }

    @discardableResult
    func commit(message: String) -> Bool {
        GitService.run(["commit", "-m", message], cwd: root).code == 0
    }

    @discardableResult
    func checkout(_ branch: String) -> Bool {
        GitService.run(["checkout", branch], cwd: root).code == 0
    }

    /// Push the current branch. Returns success + combined git output (for an alert).
    func push() -> (ok: Bool, message: String) {
        let r = GitService.run(["push"], cwd: root)
        return (r.code == 0, (r.err + r.out).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func pull() -> (ok: Bool, message: String) {
        let r = GitService.run(["pull", "--ff-only"], cwd: root)
        return (r.code == 0, (r.err + r.out).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: Helpers

    private static let hunkRegex = try! NSRegularExpression(
        pattern: #"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@"#, options: [.anchorsMatchLines])

    static func parseHunks(_ diff: String) -> [Int: GitLineStatus] {
        var result: [Int: GitLineStatus] = [:]
        let ns = diff as NSString
        hunkRegex.enumerateMatches(in: diff, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m else { return }
            func num(_ i: Int, _ def: Int) -> Int {
                let r = m.range(at: i)
                return r.location == NSNotFound ? def : Int(ns.substring(with: r)) ?? def
            }
            let oldCount = num(2, 1)
            let newStart = num(3, 1)
            let newCount = num(4, 1)

            if oldCount == 0 {                         // pure addition
                for l in newStart..<(newStart + newCount) { result[l - 1] = .added }
            } else if newCount == 0 {                  // pure deletion
                result[max(0, newStart - 1)] = .deleted
            } else {                                   // modification
                for l in newStart..<(newStart + newCount) { result[l - 1] = .modified }
            }
        }
        return result
    }

    @discardableResult
    static func run(_ args: [String], cwd: URL) -> (out: String, err: String, code: Int32) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = args
        p.currentDirectoryURL = cwd
        let outPipe = Pipe(), errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        do { try p.run() } catch { return ("", "git not found", -1) }
        // Read both pipes before waiting to avoid deadlock on large output.
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (String(decoding: outData, as: UTF8.self),
                String(decoding: errData, as: UTF8.self),
                p.terminationStatus)
    }
}
