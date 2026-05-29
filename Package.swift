// swift-tools-version: 6.0
import PackageDescription

// Alloy — native macOS code editor.
//
// We use SwiftPM (not an .xcodeproj) so the whole app builds from the command
// line with only the Command Line Tools installed. The Rust engine is built
// separately by build.sh into a static library that we link here.
//
// NOTE: linker flags reference alloy-engine/target/release/liballoy_text.a — run
// `./build.sh` (or `cargo build --release` in alloy-engine/) BEFORE `swift build`.

let package = Package(
    name: "Alloy",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        // The C ABI bridge to the Rust engine (headers only; symbols come from Rust).
        .target(
            name: "CAlloyEngine",
            publicHeadersPath: "include"
        ),

        // PTY spawn helper (forkpty/execvp) for the integrated terminal.
        .target(
            name: "CPTY",
            publicHeadersPath: "include"
        ),

        // The native macOS application.
        .executableTarget(
            name: "Alloy",
            dependencies: ["CAlloyEngine", "CPTY"],
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                // Link the Rust engine static library.
                .unsafeFlags([
                    "-L", "alloy-engine/target/release",
                    "-lalloy_text",
                ]),
                .linkedFramework("AppKit"),
                .linkedFramework("CoreText"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("QuartzCore"),
            ]
        ),
    ],
    // Swift 5 language mode keeps the large AppKit codebase free of Swift 6
    // strict-concurrency churn for now; we still build against the macOS 26 SDK.
    swiftLanguageModes: [.v5]
)
