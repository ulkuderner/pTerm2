// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LocalShell",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(name: "LocalShell", targets: ["LocalShell", "PadSystem"])
    ],
    dependencies: [
        .package(path: "../SSHClient")
    ],
    targets: [
        .target(
            name: "PadSystem",
            publicHeadersPath: "include"
        ),
        .target(
            name: "LocalShell",
            dependencies: [
                "PadSystem",
                .product(name: "SSHClient", package: "SSHClient")
            ]
        ),
        .testTarget(
            name: "LocalShellTests",
            dependencies: ["LocalShell"]
        )
    ]
)
