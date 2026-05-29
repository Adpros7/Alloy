// swift-tools-version: 6.0
import PackageDescription

// Alloy — native macOS code editor.
//
// Build sequence:
//   1. cd alloy-engine && cargo build -p alloy-text   (or --release)
//   2. swift build   (from repo root)
//
// The Rust static library (liballoy_text.a) is linked via unsafeFlags below.
// Debug builds link alloy-engine/target/debug/; swap to /release for production.

let package = Package(
    name: "Alloy",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        // C ABI bridge: the header that cbindgen generates from the Rust crate.
        // Symbols come from the Rust static lib at link time; this target just
        // provides the Swift-importable header declarations.
        .target(
            name: "CAlloyEngine",
            path: "Sources/CAlloyEngine",
            publicHeadersPath: "include"
        ),

        // PTY helper: a thin C shim around openpty/forkpty (not available directly
        // in Swift). Lives alongside its header so the Swift target can import it.
        .target(
            name: "CPTY",
            path: "Sources/CPTY",
            publicHeadersPath: "include"
        ),

        // The native macOS application.
        //
        // The canonical implementation lives in Sources/Alloy (the SPM-idiomatic
        // location): the Workbench, Liquid-Glass chrome, terminal, sidebar and git
        // integration. (An older parallel scaffold previously lived in ./Alloy and
        // was what `swift run` mistakenly built — that is why the window came up
        // blank/grey.)
        .executableTarget(
            name: "Alloy",
            dependencies: ["CAlloyEngine", "CPTY"],
            path: "Sources/Alloy",
            resources: [
                .copy("Resources/DefaultKeyBindings.json"),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-L", "alloy-engine/target/debug",
                    "-lalloy_text",
                    "-liconv",
                    "-lresolv",
                ]),
                .linkedFramework("AppKit"),
                .linkedFramework("CoreText"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("QuartzCore"),
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)
