// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SSHClient",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(name: "SSHClient", targets: ["SSHClient", "PadSSH"])
    ],
    targets: [
        .target(
            name: "PadSSH",
            publicHeadersPath: "include"
        ),
        .target(
            name: "SSHClient",
            dependencies: ["PadSSH"]
        ),
        .testTarget(
            name: "SSHClientTests",
            dependencies: ["SSHClient"]
        )
    ]
)
