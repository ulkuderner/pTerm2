// swift-tools-version: 5.9
import PackageDescription

let sshHeaders = Context.packageDirectory + "/Frameworks/libssh2.xcframework/ios-arm64/Headers"

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
        .binaryTarget(
            name: "CLibSSH2",
            path: "Frameworks/libssh2.xcframework"
        ),
        .target(
            name: "PadSSH",
            dependencies: [
                .target(name: "CLibSSH2", condition: .when(platforms: [.iOS]))
            ],
            publicHeadersPath: "include",
            cSettings: [
                .define("IT2PAD_HAS_LIBSSH2", to: "1", .when(platforms: [.iOS])),
                .unsafeFlags(["-I", sshHeaders], .when(platforms: [.iOS]))
            ]
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
