// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DisplayPadController",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "CLibUSB",
            path: "Sources/CLibUSB",
            linkerSettings: [
                .unsafeFlags(["-L/opt/homebrew/lib"]),
                .linkedLibrary("usb-1.0"),
            ]
        ),
        .executableTarget(
            name: "DisplayPadController",
            dependencies: ["CLibUSB"],
            path: "Sources/DisplayPadController",
            linkerSettings: [
                .linkedFramework("IOKit"),
            ]
        ),
    ]
)
