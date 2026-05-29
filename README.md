# Alloy — Native macOS Code Editor (Swift + Rust + Node Extension Host)

## App Name

**Alloy** — a metal formed by combining two elements into something stronger than either alone. This project literally alloys Swift (for macOS UI) and Rust (for the editor engine), and the name evokes premium craftsmanship, native performance, and precision.

---

## Icon Design

**Shape**: macOS standard rounded rectangle with generous padding (following macOS 14+ icon guidelines).

**Background**: Very deep charcoal-black (#0E0E12), not pure black — maintains visibility on dark dock.

**Symbol**: A stylized angular bond glyph — two bold angled chevrons (like `<>`) interlocked at a central vertex, with the left arm rendered in Swift orange (#F05138) and the right arm in Rust amber (#CE422B), blending to a warm gold (#E8A050) at the contact point. The merge point has a subtle metallic sheen. The overall shape simultaneously reads as: a code bracket pair, two materials bonding, and a forward-pointing arrow (speed). 

**Typography treatment**: None — icon is purely symbolic, no wordmark.

**Glow treatment**: A very subtle warm inner glow around the central bond point, mimicking molten metal. Looks excellent against both light and dark wallpapers.

**Size reference**: The central symbol occupies ~55% of the rounded rect area, centered, with significant breathing room. At 16px it remains a clean angular shape.

---

## Context

Build a native macOS code editor in Swift with a Rust engine layer and full VSCode extension compatibility via a Node.js extension host. The goal is VS Code's power and ecosystem with none of Electron's weight. The app installs .vsix extensions directly from the VS Code Marketplace with a full search UI. The UI is AppKit + SwiftUI. The editor engine is Rust. The extension host is VS Code's own MIT-licensed Node.js code adapted to run without Electron.

---

## Current Status

> **Phase 1 foundation is built and runs.** A native AppKit app (no Electron) with
> the Rust rope engine linked in, editing text live through the FFI, with a Liquid
> Glass UI.

**What works today:**
- **Rust engine** (`alloy-engine/crates/alloy-text`): `ropey` rope buffer behind a
  flat C ABI (create/edit/line/line-count/byte↔line/text), opaque integer handles,
  panic-guarded, unit-tested. Built as a static lib and linked into the Swift app.
- **C bridge** (`Sources/CAlloyEngine`): hand-written `alloy_engine.h` + modulemap.
- **Swift editor** (`EditorTextView`): flipped `NSView`, CoreText rendering of only
  the visible lines, gutter with line numbers, blinking caret, click/drag + shift
  selection, arrow/word/line motion, type/newline/tab/delete, cut/copy/paste/select-all,
  full `NSTextInputClient` conformance. Every keystroke is one FFI edit into the Rust rope.
- **Workbench UI**: activity bar, file-explorer sidebar (`NSOutlineView`), editor tabs,
  status bar (Ln/Col, language, branch). VS Code-style layout.
- **Liquid Glass (real refraction)**: the activity bar, tab bar, status bar and panel
  header are built on macOS 26 **`NSGlassEffectView`** (via `GlassPanelView`), which
  *refracts* the backdrop — edge lensing + specular highlight — not just the blur of
  `NSVisualEffectView`. The window is non-opaque so the glass bends the desktop/content
  behind it. Glass capsule accents: the active editor tab sits in a glass pill, and the
  activity-bar selection is a glass capsule that slides between icons. The Explorer uses
  the system vibrant sidebar split item. Falls back to vibrant material pre-26.
- **Menu + keybindings**: macOS main menu with VS Code key equivalents; VS Code-format
  `DefaultKeyBindings.json` loaded by `KeyBindingManager` (+ user override file support).

**Build & run:**
```bash
./build.sh            # builds the Rust engine (release) then the Swift app
swift run Alloy       # launch
```

**Toolchain note:** This machine has the **Command Line Tools**, not full Xcode, so the
app is built with **Swift Package Manager** (`Package.swift`) instead of an `.xcodeproj`.
It still uses AppKit/SwiftUI and the macOS 26 SDK. An `.xcodeproj` (for signing, the
`.app` bundle, and Sparkle updates) is generated in the Distribution phase. Requires
Rust (`cargo`) and is verified against Swift 6.3 / macOS 26.

**Integrated terminal (Phase 2 — built & verified):**
- `Sources/CPTY`: a C `forkpty`/`execvp` shim that spawns the shell on a real PTY.
- `PTYProcess.swift`: async read via a GCD read source, write, and SIGWINCH resize.
- `TerminalGrid.swift`: screen + capped scrollback, cursor, SGR, erase, insert/delete,
  DEC private modes, and the alternate screen buffer (for full-screen TUIs).
- `VTParser.swift`: ground/escape/CSI/OSC state machine with incremental UTF-8 decoding.
- `TerminalColor.swift`: the full xterm-256 palette + truecolor.
- `TerminalView.swift`: CoreText grid rendering (bold/italic/underline/inverse), block
  cursor, scrollback scrolling, and keyboard→escape-sequence translation (arrows obey
  DECCKM, Ctrl-combos, Home/End/PgUp/PgDn, paste).
- Lives in a collapsible bottom panel, toggled with **⌘`** (verified: toggling spawns
  a live `zsh`).

**Not yet built** (tracked in the session TODO + the Phased Roadmap below): tree-sitter
syntax highlighting, git, the Node extension host, debugger, and Phase 5 polish.

---

## Architecture Overview

```
┌────────────────────────────────────────────────────────────────┐
│  Swift Layer (macOS App)                                         │
│  AppKit: EditorView, Sidebar, TabBar, Terminal, StatusBar, etc. │
│  SwiftUI: Settings, Dialogs, Extensions UI, Marketplace          │
│  Swift: App lifecycle, Keybindings, Window management            │
└────────────────┬────────────────────────┬───────────────────────┘
                 │  C ABI FFI             │  Binary RPC over Unix socket
                 ▼                        ▼
┌──────────────────────────┐  ┌──────────────────────────────────┐
│  Rust Engine             │  │  Node.js Extension Host           │
│  libferrite_engine.dylib │  │  (VS Code OSS MIT, adapted)       │
│                          │  │                                    │
│  • Rope text buffer      │  │  • Full vscode.* extension API    │
│  • Tree-sitter syntax    │  │  • Runs any .vsix from Marketplace│
│  • Project search        │  │  • Language servers via extensions│
│  • File watching         │  │  • Debug adapters via extensions  │
│  • LSP/DAP msg framing   │  │  • Webviews → WKWebView panels    │
│  • Git status scanning   │  │  • Custom tree views, panels, etc │
│  • Diagnostics pipeline  │  └──────────────────────────────────┘
└──────────────────────────┘
```

---

## Swift vs. Rust Decision Table

| Component | Language | Rationale |
|---|---|---|
| EditorView, GutterView, Minimap | **Swift** | Must use AppKit / CoreText |
| Sidebar panels, StatusBar, TabBar | **Swift** | AppKit views |
| Terminal (PTY + VT parser + TerminalView) | **Swift** | PTY is POSIX; performance bounded by frame rate, not compute |
| Settings window, Dialogs | **Swift** | SwiftUI |
| Keybinding system | **Swift** | NSEvent interception, AppKit-coupled |
| Git stage/commit/push/pull UI | **Swift** | libgit2 via Swift; macOS Keychain deeply integrated |
| Extension host IPC (MainThread* impl) | **Swift** | Tightly coupled to AppKit UI |
| **Rope text buffer** | **Rust** | `ropey` crate is production-tested; edits batched, one FFI call per keystroke |
| **Tree-sitter syntax** | **Rust** | Official Rust binding; re-parses on background thread; result is compact token array |
| **Project-wide search** | **Rust** | `grep-searcher` + `ignore` (ripgrep internals); faster than subprocess, .gitignore-aware |
| **File system watching** | **Rust** | `notify` crate wraps macOS FSEvents natively; easier debounce/filter |
| **LSP/DAP message framing** | **Rust** | `lsp-types` + `serde_json`; JSON parsing off main thread |
| **Git status scanning + diff** | **Rust** | `gix` (gitoxide); ~10ms status on 10k-file repos; feeds gutter decorations |
| **Diagnostics aggregation** | **Rust** | Merge/sort LSP + lint diagnostics; tight loop |

**Rule**: Swift owns all user interaction and Apple platform APIs. Rust owns heavy background compute. The FFI boundary is a flat C ABI with simple data types — no shared object graphs, no chatty calls.

---

## Project Structure

```
alloy/
├── Alloy.xcodeproj
│
├── Alloy/                                ← Main Swift app target
│   ├── App/
│   │   ├── AlloyApp.swift
│   │   ├── AppDelegate.swift
│   │   └── AppCommands.swift
│   │
│   ├── Core/
│   │   ├── Bridge/
│   │   │   ├── AlloyEngine.h             ← cbindgen-generated header
│   │   │   └── module.modulemap
│   │   ├── TextBuffer.swift              ← Thin Swift wrapper over Rust rope FFI
│   │   ├── Document.swift                ← actor: file URL, encoding, EOL, dirty state
│   │   ├── Selection.swift               ← Multi-cursor model
│   │   ├── UndoStack.swift
│   │   └── Workspace/
│   │       ├── Workspace.swift
│   │       ├── TabGroup.swift
│   │       └── WorkspaceController.swift
│   │
│   ├── ExtensionHost/
│   │   ├── ExtHostManager.swift          ← Spawns/monitors Node process
│   │   ├── ExtHostSocket.swift           ← Binary RPC framing over Unix domain socket
│   │   ├── ExtHostRPC.swift              ← VQL encoder/decoder, message routing
│   │   ├── MainThreadRouter.swift        ← Dispatches to one of 69 MainThread handlers
│   │   ├── handlers/
│   │   │   ├── MTCommands.swift          ← MainThreadCommandsShape
│   │   │   ├── MTDocuments.swift         ← MainThreadDocumentsShape
│   │   │   ├── MTTextEditors.swift       ← MainThreadTextEditorsShape
│   │   │   ├── MTLanguageFeatures.swift  ← MainThreadLanguageFeaturesShape (40+ methods)
│   │   │   ├── MTDiagnostics.swift       ← MainThreadDiagnosticsShape
│   │   │   ├── MTMessages.swift          ← MainThreadMessageServiceShape
│   │   │   ├── MTStatusBar.swift         ← MainThreadStatusBarShape
│   │   │   ├── MTTerminal.swift          ← MainThreadTerminalServiceShape
│   │   │   ├── MTTreeViews.swift         ← MainThreadTreeViewsShape
│   │   │   ├── MTWebviews.swift          ← MainThreadWebviewsShape + WebviewPanels
│   │   │   ├── MTDebug.swift             ← MainThreadDebugServiceShape
│   │   │   ├── MTQuickOpen.swift         ← MainThreadQuickOpenShape
│   │   │   ├── MTOutputService.swift     ← MainThreadOutputServiceShape
│   │   │   ├── MTWorkspace.swift         ← MainThreadWorkspaceShape
│   │   │   ├── MTFileSystem.swift        ← MainThreadFileSystemShape
│   │   │   ├── MTSCM.swift               ← MainThreadSCMShape
│   │   │   ├── MTProgress.swift          ← MainThreadProgressShape
│   │   │   ├── MTStorage.swift           ← MainThreadStorageShape
│   │   │   ├── MTAuthentication.swift    ← MainThreadAuthenticationShape
│   │   │   ├── MTConfiguration.swift     ← MainThreadConfigurationShape
│   │   │   ├── MTEditorTabs.swift        ← MainThreadEditorTabsShape
│   │   │   ├── MTDialogs.swift           ← MainThreadDialogsShape → NSOpenPanel/NSSavePanel
│   │   │   ├── MTClipboard.swift         ← MainThreadClipboardShape → NSPasteboard
│   │   │   ├── MTNotebook.swift          ← MainThreadNotebookShape (stub MVP, full later)
│   │   │   ├── MTTask.swift              ← MainThreadTaskShape
│   │   │   ├── MTSearch.swift            ← MainThreadSearchShape
│   │   │   ├── MTExtensionService.swift  ← MainThreadExtensionServiceShape
│   │   │   ├── MTBulkEdits.swift         ← MainThreadBulkEditsShape
│   │   │   ├── MTDecorations.swift       ← MainThreadDecorationsShape
│   │   │   ├── MTComments.swift          ← MainThreadCommentsShape
│   │   │   ├── MTUrls.swift              ← MainThreadUrlsShape
│   │   │   ├── MTSecretState.swift       ← MainThreadSecretStateShape → Keychain
│   │   │   ├── MTWindow.swift            ← MainThreadWindowShape
│   │   │   ├── MTShare.swift             ← MainThreadShareShape
│   │   │   └── MTTunnel.swift            ← MainThreadTunnelServiceShape
│   │   └── ExtHostDocumentSync.swift     ← Sends textDocument/* notifications to host
│   │
│   ├── Extensions/
│   │   ├── Marketplace/
│   │   │   ├── MarketplaceClient.swift   ← POST to gallery API, parses response
│   │   │   ├── MarketplaceModels.swift   ← Codable structs for API response
│   │   │   └── VSIXInstaller.swift       ← Download + unzip .vsix to extensions dir
│   │   ├── ExtensionRegistry.swift       ← Index of installed extension manifests
│   │   ├── ThemeLoader.swift             ← VSCode JSON theme → resolved colors
│   │   └── SnippetEngine.swift           ← Snippet expansion, tab-stop navigation
│   │
│   ├── Git/
│   │   ├── GitRepository.swift           ← libgit2: stage, commit, push, pull, branch
│   │   ├── GitCredentials.swift          ← Keychain + SSH agent
│   │   └── GitStatusBridge.swift         ← Calls Rust FFI for fast status + diff
│   │
│   ├── Search/
│   │   ├── InFileSearch.swift
│   │   └── ProjectSearch.swift           ← Calls Rust search FFI
│   │
│   ├── KeyBindings/
│   │   ├── KeyBindingManager.swift       ← NSEvent.addLocalMonitorForEvents
│   │   ├── KeyCombo.swift
│   │   ├── WhenClause.swift
│   │   └── DefaultKeyBindings.json       ← VSCode macOS defaults verbatim
│   │
│   └── UI/
│       ├── Editor/
│       │   ├── EditorView.swift
│       │   ├── EditorViewController.swift
│       │   ├── GutterView.swift
│       │   ├── MinimapView.swift
│       │   ├── CompletionPopup.swift
│       │   ├── HoverTooltip.swift
│       │   └── DiagnosticLayer.swift
│       ├── Terminal/
│       │   ├── PTYProcess.swift
│       │   ├── VTParser.swift
│       │   ├── TerminalGrid.swift
│       │   ├── TerminalView.swift
│       │   └── TerminalSession.swift
│       ├── Sidebar/
│       │   ├── SidebarViewController.swift
│       │   ├── ActivityBar.swift
│       │   ├── FileExplorer/
│       │   ├── SearchPanel/
│       │   ├── SourceControl/
│       │   ├── ExtensionsPanel/          ← Marketplace search + installed extensions
│       │   └── DebugPanel/
│       ├── TabBar/
│       ├── StatusBar/
│       ├── CommandPalette/
│       ├── Debugger/
│       └── Settings/                     ← SwiftUI two-panel settings window
│
├── alloy-engine/                         ← Rust workspace
│   ├── Cargo.toml
│   └── crates/
│       ├── alloy-text/                   ← ropey rope buffer + C ABI
│       ├── alloy-syntax/                 ← tree-sitter + grammar crates + C ABI
│       ├── alloy-search/                 ← grep-searcher + ignore + C ABI
│       ├── alloy-watch/                  ← notify + debounce + C ABI
│       ├── alloy-lsp/                    ← lsp-types + framing + C ABI
│       ├── alloy-dap/                    ← DAP framing + C ABI
│       ├── alloy-git/                    ← gix status/diff + C ABI
│       ├── alloy-diagnostics/            ← merge/sort + C ABI
│       └── alloy-ffi/                    ← Unified C ABI + cbindgen config
│
└── extension-host/                       ← Node.js extension host
    ├── package.json
    ├── src/extensionHostMain.ts          ← Adapted VS Code OSS entry point
    └── out/extensionHostMain.js          ← Built bundle → copied to app Resources
```

---

## Extension Host: Full Implementation Plan

### Source

VS Code is MIT licensed. The extension host source lives in VS Code's repository at `src/vs/workbench/api/`. We adapt it to run standalone — no Electron, no DOM renderer, just Node.js + the Unix socket connection to the native Swift UI.

### Binary IPC Protocol

The protocol between extension host and native UI is VS Code's existing binary RPC protocol. It is not JSON-over-HTTP — it is a length-prefixed binary protocol over a Unix domain socket at `$TMPDIR/alloy-{pid}.sock`.

**Low-level message frame (9-byte header):**
```
[TYPE: 1 byte] [ID: 4 bytes u32be] [ACK: 4 bytes u32be] [DATA_LENGTH: 4 bytes u32be] [PAYLOAD: n bytes]
```

**Message type codes:**
- `1` = Initialized
- `2` = Ready
- `3` = Terminate

**RPC layer over the frame:**
- Header: 1 byte message type + 4-byte request ID (big-endian)
- Message types: 100=Promise, 101=PromiseCancel, 102=EventListen, 103=EventDispose, 200=Initialize, 201=PromiseSuccess, 202=PromiseError, 204=EventFire

**Argument serialization (VQL-encoded type-tagged format):**
| Type | Code | Encoding |
|---|---|---|
| Undefined | 0 | 1 byte |
| String | 1 | code + VQL length + UTF-8 bytes |
| Buffer | 2 | code + VQL length + raw bytes |
| VSBuffer | 3 | code + VQL length + buffer |
| Array | 4 | code + VQL count + recursive elements |
| Object | 5 | code + VQL length + JSON bytes |
| Integer | 6 | code + VQL value |

`ExtHostSocket.swift` and `ExtHostRPC.swift` implement this framing. The Swift side parses incoming messages and routes them through `MainThreadRouter.swift` to the appropriate handler.

### The 69 MainThread* Interfaces

Every `MainThread*Shape` interface in `extHost.protocol.ts` must be implemented. They are organized in `handlers/` by file. Implementation priority:

**Phase 3 MVP (ship first — ~80% of extensions use these):**
- `MTDocuments.swift` — `$tryCreateDocument`, `$tryOpenDocument`, `$trySaveDocument`
- `MTTextEditors.swift` — `$tryShowTextDocument`, `$trySetDecorations`, `$tryApplyEdits`, `$trySetSelections`, `$registerTextEditorDecorationType`
- `MTLanguageFeatures.swift` — all 40+ provider registrations (completions, hover, definitions, diagnostics, code actions, etc.)
- `MTDiagnostics.swift` — `$changeMany`, `$clear`
- `MTCommands.swift` — `$registerCommand`, `$unregisterCommand`, `$executeCommand`, `$getCommands`
- `MTMessages.swift` — `$showMessage` → NSAlert / notification
- `MTStatusBar.swift` — `$setEntry`, `$disposeEntry` → StatusBarView items
- `MTQuickOpen.swift` — `$show`, `$setItems`, `$createOrUpdate`, `$input` → command palette + input boxes
- `MTOutputService.swift` — `$register`, `$update`, `$reveal` → output panel
- `MTWorkspace.swift` — `$updateWorkspaceFolders`, `$requestWorkspaceTrust`, file search/text search
- `MTProgress.swift` — `$startProgress`, `$progressReport`, `$progressEnd` → progress indicators
- `MTStorage.swift` — `$setValue`, `$initializeExtensionStorage` → extension key-value storage
- `MTConfiguration.swift` — `$updateConfigurationOption` → settings store writes
- `MTClipboard.swift` → NSPasteboard
- `MTDialogs.swift` → NSOpenPanel / NSSavePanel
- `MTWindow.swift` — `$openUri` → NSWorkspace.open

**Phase 3 (important, needed by popular extensions):**
- `MTTerminal.swift` — create/show/sendText/hide terminal sessions
- `MTTreeViews.swift` — custom sidebar panels for extensions (explorer tree providers)
- `MTWebviews.swift` + `MTWebviewPanels.swift` — WKWebView panel hosting for extension webview UI
- `MTSCM.swift` — source control provider registration (needed for GitLens, etc.)
- `MTDebug.swift` — debug configuration providers, debug adapter factories, DAP sessions
- `MTAuthentication.swift` — OAuth flows (needed for GitHub Copilot, GitHub extensions)
- `MTSecretState.swift` → macOS Keychain via Security.framework
- `MTFileSystem.swift` — virtual filesystem providers
- `MTBulkEdits.swift` — workspace-wide edits (needed for refactoring tools)
- `MTDecorations.swift` — file decorations in explorer (needed for GitLens)
- `MTEditorTabs.swift` — tab management from extensions
- `MTExtensionService.swift` — extension activation lifecycle
- `MTUrls.swift` — URI handler registration

**Phase 4 (advanced, lower-priority):**
- `MTComments.swift` — code review comment threads (GitHub PR review)
- `MTTask.swift` — task runner integration
- `MTSearch.swift` — custom search providers
- `MTNotebook.swift` — Jupyter notebook support
- `MTTunnel.swift` — port forwarding (remote dev)
- `MTShare.swift` — share extension content
- `MTLanguageModelsShape` — **intentionally omitted** (AI features excluded by design)
- `MTChatAgentsShape2` — **intentionally omitted**
- `MTEmbeddingsShape` — **intentionally omitted**
- `MTChatContextShape` — **intentionally omitted**
- `MTChatDebugShape` — **intentionally omitted**
- `MTCodeMapperShape` — **intentionally omitted**
- `MTLanguageModelToolsShape` — **intentionally omitted**
- `MTChatOutputRendererShape` — **intentionally omitted**

> All AI/Copilot/chat interfaces are **intentionally not implemented**. The extension host will receive stub responses (empty/not-supported) for these. Extensions that are purely AI-focused will show as incompatible. This is by design — no AI bloat.

### Webviews

Extensions that create webview panels (`vscode.window.createWebviewPanel`) get a native `NSWindow` containing a `WKWebView`. The `vscode.Webview` message API (`postMessage`/`onDidReceiveMessage`) is bridged through `WKScriptMessageHandler`. CSP is enforced via the extension manifest's `localResourceRoots`. This is not Electron — it is macOS's built-in WebKit, sandboxed per panel.

### Node.js Bundle

- Bundle Node.js 22 LTS as a Universal Binary (ARM64 + x86_64) at `Alloy.app/Contents/Resources/bin/node`
- Extension host bundle at `Alloy.app/Contents/Resources/extensionHost/out/extensionHostMain.js`
- Extensions install to `~/Library/Application Support/Alloy/extensions/`
- At first launch: detect `~/.vscode/extensions/` and offer to import/link existing extensions

---

## Extensions Marketplace UI

### Overview

The Extensions panel in the sidebar (Cmd+Shift+X) is a full-featured marketplace browser, not just a VSIX file picker. It mirrors VS Code's extensions experience.

### Marketplace API

**Endpoint**: `POST https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery`

**Headers**:
```
Content-Type: application/json
Accept: application/json; charset=utf-8; api-version=7.2-preview.1
```

**Request payload structure**:
```json
{
  "filters": [{
    "criteria": [
      {"filterType": 8, "value": "Microsoft.VisualStudio.Code"},
      {"filterType": 10, "value": "<search query>"}
    ],
    "pageNumber": 1,
    "pageSize": 24,
    "sortBy": 4,
    "sortOrder": 0
  }],
  "flags": 16863
}
```

**Filter type codes**: 1=Tag, 4=Extension ID, 7=Extension name, 8=Target (always "Microsoft.VisualStudio.Code"), 10=Full-text search

**Sort by codes**: 0=Relevance, 4=Install count (Trending), 5=Rating, 10=Published date

`MarketplaceClient.swift` implements this API call. `MarketplaceModels.swift` contains `Codable` structs matching the response.

### VSIX Download + Install

```
GET https://marketplace.visualstudio.com/_apis/public/gallery/publishers/{publisher}/vsextensions/{name}/{version}/vspackage
```

`VSIXInstaller.swift`:
1. Downloads the `.vsix` (which is a ZIP file)
2. Unzips to a temp directory
3. Reads `extension/package.json` to validate the manifest
4. Moves to `~/Library/Application Support/Alloy/extensions/{publisher}.{name}-{version}/`
5. Notifies `ExtensionRegistry` to reload
6. Signals `ExtHostManager` to restart the extension host with the new extension

### Extensions Panel Sections (SwiftUI, embedded in sidebar)

**Search bar** — full-text search, debounced 300ms, calls marketplace API

**Browse views** (matching VS Code's sidebar tabs):
- **Installed** — list of installed extensions with enable/disable/uninstall
- **Recommended** — curated list based on workspace language (if `.py` files detected → suggest ms-python.python)
- **Trending** — top extensions by install count (sortBy=4)
- **Popular** — all-time most installed
- **Recently Published** — sortBy=10, newest first

**Extension detail page** (SwiftUI sheet or sidebar detail pane):
- Extension icon, name, publisher, version, rating, install count
- Long description (markdown rendered via AttributedString)
- Changelog tab
- Feature contributions tab (lists what commands/themes/grammars it contributes)
- Install / Uninstall / Enable / Disable button
- Extension settings (deep-links to Settings page filtered by extension)

**Compatibility warning**: Extensions that depend on AI/Copilot APIs show a banner: "Some features of this extension are not available in Alloy."

---

## Terminal

Pure Swift + PTY, no Rust involvement:

- `PTYProcess.swift` — `openpty()` + `fork()`/`execve()` via thin C shim
- `VTParser.swift` — VT100/VT220/xterm-256color/xterm-kitty state machine (~2500 lines)
- `TerminalGrid.swift` — 2D `Cell` array (UTF-32 char + fg/bg + attribute flags)
- `TerminalView.swift` — NSView, CALayer-backed CoreText rendering at 60fps
- Toggle: Cmd+\` matching VS Code
- Multiple terminal instances via tabs at bottom panel
- Shell selection, font, 17 built-in iTerm2-compatible color schemes

---

## Git Integration

Two layers:

**Rust** (`alloy-git` crate using `gix`): fast status scanning, per-line diff for gutter decorations. `GitStatusBridge.swift` calls the C ABI, feeds the Source Control sidebar and gutter.

**Swift** (`GitRepository.swift` using libgit2, already at `/opt/homebrew`): all user-initiated operations — stage, unstage, commit, amend, push, pull, fetch, branch create/delete/checkout, merge. `GitCredentials.swift` integrates with macOS Keychain for HTTPS tokens and SSH agent for SSH remotes.

---

## Keybindings

- `NSEvent.addLocalMonitorForEvents` interception at `NSApplication` level
- Chord sequences (e.g., `Ctrl+K Ctrl+C`)
- `WhenClause` evaluator: `editorFocus`, `terminalFocus`, `inSnippetMode`, `sidebarFocus`, `debuggerOpen`, `findWidgetVisible`, etc.
- `DefaultKeyBindings.json` — exact VS Code macOS defaults verbatim
- User overrides at `~/Library/Application Support/Alloy/keybindings.json` (same format as VS Code)
- Keybinding editor in Settings: SwiftUI table, inline editing, same UI as VS Code's keyboard shortcuts page

---

## Settings

- `~/Library/Application Support/Alloy/settings.json`
- Same key names as VS Code: `editor.fontSize`, `editor.tabSize`, `editor.wordWrap`, `files.autoSave`, `terminal.fontFamily`, `workbench.colorTheme`, `workbench.iconTheme`, etc.
- `SettingsStore` is `@MainActor @Observable`
- Workspace-level overrides in `.alloy/settings.json` at project root
- Settings window: SwiftUI two-panel layout (category sidebar + content), matching VS Code layout exactly
- Extension settings rendered inline in the same settings window, organized by extension

---

## Rust Engine FFI Boundary

Compiled to `libferrite_engine.dylib` (product name can stay as `ferrite` or rename to `alloy_engine`). `cbindgen` generates `AlloyEngine.h` during the Rust build.

**FFI rules**: no callbacks on hot path; strings as `*const u8` + length; opaque handle IDs (not pointers); large results as JSON strings; background work signaled via a polling channel Swift reads on a background DispatchQueue.

**Key exported functions:**
```c
// Text
AlloyBufferID ffe_buffer_create(const uint8_t* bytes, size_t len);
void          ffe_buffer_edit(AlloyBufferID id, size_t byte_offset, size_t old_len,
                               const uint8_t* new_bytes, size_t new_len);
AlloySlice    ffe_buffer_line(AlloyBufferID id, size_t line_index);
size_t        ffe_buffer_line_count(AlloyBufferID id);
void          ffe_buffer_destroy(AlloyBufferID id);

// Syntax
AlloySyntaxID  ffe_syntax_create(AlloyBufferID buf_id, AlloyLanguage lang);
void           ffe_syntax_notify_edit(AlloySyntaxID id, AlloyEdit edit);
AlloyTokens    ffe_syntax_tokens_for_lines(AlloySyntaxID id, size_t first, size_t last);

// Search  
void           ffe_search_project(const uint8_t* root, size_t root_len,
                                   const uint8_t* query, size_t query_len,
                                   bool is_regex, bool case_sensitive,
                                   AlloySearchCallback cb, void* ctx);

// Git
AlloyGitID     ffe_git_open(const uint8_t* path, size_t len);
const char*    ffe_git_status_json(AlloyGitID id);   // caller frees
AlloyDiffLines ffe_git_diff_lines(AlloyGitID id, const uint8_t* file, size_t len);
```

---

## Rust Crate Dependencies

| Crate | Key dependencies |
|---|---|
| `alloy-text` | `ropey 1.6`, `unicode-segmentation` |
| `alloy-syntax` | `tree-sitter 0.23`, `tree-sitter-swift`, `tree-sitter-rust`, `tree-sitter-python`, `tree-sitter-typescript`, `tree-sitter-javascript`, `tree-sitter-go`, `tree-sitter-c`, `tree-sitter-cpp`, `tree-sitter-java`, `tree-sitter-ruby`, `tree-sitter-html`, `tree-sitter-css`, `tree-sitter-json`, `tree-sitter-yaml`, `tree-sitter-toml`, `tree-sitter-bash`, `tree-sitter-markdown` |
| `alloy-search` | `grep-searcher`, `grep-regex`, `ignore` (BurntSushi's ripgrep workspace) |
| `alloy-watch` | `notify 6`, `crossbeam-channel` |
| `alloy-lsp` | `lsp-types`, `serde`, `serde_json` |
| `alloy-dap` | `serde`, `serde_json` |
| `alloy-git` | `gix`, `gix-diff` |
| `alloy-diagnostics` | `serde`, `serde_json` |
| `alloy-ffi` | `cbindgen` (build-dep only) |

---

## Phased Roadmap

### Phase 1 — Rust Engine + Core Editor (Months 1–3): "It Opens Files Fast"

**Rust:**
- `alloy-text`: ropey rope + C ABI
- `alloy-syntax`: tree-sitter + 5 grammars (Swift, Python, TypeScript, JSON, YAML) + C ABI
- `alloy-ffi`: cbindgen setup, Xcode build script integration

**Swift:**
- Xcode project scaffold
- `TextBuffer.swift` wrapping Rust rope FFI
- `Document.swift` actor
- `EditorView.swift` — NSView, CoreText rendering (visible lines only), `NSTextInputClient`
- `GutterView.swift` — line numbers only
- `TabBarView.swift` — drag reorder, Cmd+W
- Main window: Activity Bar, sidebar (collapsed), editor, status bar
- File open/new/save
- `KeyBindingManager.swift` + `DefaultKeyBindings.json`
- One Dark theme (dark) + one light theme
- Basic settings: font, tab size, theme

**Milestone**: Fast native text editor with tree-sitter syntax highlighting. Measurably faster than VS Code for all text operations.

---

### Phase 2 — Terminal + Git (Month 4): "Full Dev Environment"

**Rust:**
- `alloy-git`: gix status scanning + line diff + C ABI

**Swift:**
- Full PTY terminal module (PTYProcess + VTParser + TerminalGrid + TerminalView)
- Terminal panel, multiple tabs, color schemes
- libgit2 Swift wrapper: stage, commit, push, pull, branch operations
- Keychain credential integration
- Source Control sidebar with staged/unstaged lists
- Gutter git decorations driven by Rust diff data
- Branch switcher in status bar, git blame toggle

**Milestone**: Self-contained development environment.

---

### Phase 3 — Extension Host MVP (Months 5–7): "VSCode Extensions Work"

**Node.js work:**
- Adapt VS Code OSS extension host to accept a `--socket-path` argument
- Remove Electron-specific imports, replace with Node.js alternatives
- Build with esbuild to `out/extensionHostMain.js`
- Bundle Node.js 22 LTS into app Resources

**Swift work:**
- `ExtHostSocket.swift` + `ExtHostRPC.swift` — binary protocol framing
- `MainThreadRouter.swift` — dispatches to handlers
- All Phase 3 MVP handlers (MTDocuments, MTTextEditors, MTLanguageFeatures, MTDiagnostics, MTCommands, MTMessages, MTStatusBar, MTQuickOpen, MTOutputService, MTWorkspace, MTProgress, MTStorage, MTConfiguration, MTClipboard, MTDialogs, MTWindow)
- `ExtHostDocumentSync.swift` — sends `textDocument/didChange` on every rope edit
- `MarketplaceClient.swift` + `VSIXInstaller.swift`
- Extensions panel in sidebar: full search UI, Installed, Recommended, Trending, Popular tabs
- Extension detail page with install/uninstall
- Import from `~/.vscode/extensions/` at first launch

**Rust work:**
- `alloy-lsp`: LSP JSON-RPC framing + response routing
- `alloy-dap`: DAP message framing
- `alloy-diagnostics`: merge/sort diagnostic arrays

**Milestone**: Real .vsix extensions install and run. Pylance, ESLint, Prettier, Rust Analyzer, etc. all work.

---

### Phase 4 — Full Extension API + Advanced Features (Month 8): "Production Ready"

**Swift (remaining MainThread handlers):**
- MTTerminal, MTTreeViews, MTWebviews, MTWebviewPanels, MTSCM, MTDebug, MTAuthentication, MTSecretState, MTFileSystem, MTBulkEdits, MTDecorations, MTEditorTabs, MTExtensionService, MTUrls, MTComments, MTTask, MTSearch, MTNotebook

**Swift (features):**
- `alloy-search` C ABI wired to project search panel (Cmd+Shift+F)
- `alloy-watch` wired to file tree refresh
- DAP debugger UI: run/pause/stop/step, call stack, variables, watch, debug console, breakpoints
- Multi-root workspace support (`.alloy-workspace` file)
- More tree-sitter grammars: all remaining languages

**Milestone**: Full feature parity with VS Code's daily-driver use cases. Extensions marketplace works end-to-end.

---

### Phase 5 — Polish (Month 9+)

- Minimap (CoreText at 2pt scale)
- Code folding (tree-sitter fold queries)
- Multiple cursors (full VS Code parity)
- Vim mode (modal editing layer)
- Split editor
- Diff editor (two-pane for git show / merge conflict)
- Remote SSH editing
- VoiceOver accessibility
- Performance audit: rope rebalancing, CoreText glyph cache, tree-sitter memory reuse

---

## Critical Technical Risks

| Risk | Mitigation |
|---|---|
| VS Code extension host IPC protocol evolution | Pin to a specific VS Code tag (e.g., 1.92.0); update deliberately. The protocol is readable in VS Code OSS source. |
| IME input in custom NSView | Implement `NSTextInputClient` fully in Phase 1; test with Japanese/CJK before declaring done |
| VT parser completeness for modern shells | fish, oh-my-zsh, vim, tmux are acceptance tests. Target XTerm 366 compatibility. |
| Rust dylib code signing | `libferrite_engine.dylib` embedded in `Contents/Frameworks/`, signed with same Developer ID cert; install_name_tool sets @rpath |
| Large file performance (>100MB) | Disable syntax highlighting >5MB; strict viewport virtualization; Rust rope is O(log n) regardless |
| Extension authentication flows (GitHub Copilot OAuth etc.) | MTAuthentication maps to ASWebAuthenticationSession; tokens stored in Keychain |

---

## Distribution

- Build: Xcode 16+, Swift 5 compatibility mode
- Minimum target: macOS 14.0 (Sonoma)
- Code signing: Developer ID Application (not App Store — sandbox incompatible with spawning language servers)
- Distribution: `.dmg` with Sparkle auto-updates
- Node.js and extension host bundle add ~60MB; acceptable for a professional dev tool

---

## Verification Plan

- **Phase 1**: Open a 10,000-line Swift file; scroll at 60fps with no jank; type CJK characters; undo/redo 100 edits correctly; syntax highlighting correct
- **Phase 2**: Open a git repo with 1,000+ changes; verify status in <500ms; commit/push succeed; terminal runs vim, fish, tmux correctly
- **Phase 3**: Install `ms-python.python` from marketplace search UI; open Python file; verify IntelliSense completions appear from Pylance; install a theme; verify it applies
- **Phase 4**: Set a breakpoint in Python; start debugger; step through; inspect variables in the variables panel; install GitLens and verify inline blame works
- **Phase 5**: Open a 500k-line generated JSON file; verify smooth scrolling; no memory growth after 10 minutes
