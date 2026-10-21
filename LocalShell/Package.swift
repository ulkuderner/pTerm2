// swift-tools-version: 5.9
import PackageDescription

let pythonHeaders = Context.packageDirectory + "/Frameworks/Python.xcframework/ios-arm64/Python.framework/Headers"

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
        .binaryTarget(
            name: "CPython",
            path: "Frameworks/Python.xcframework"
        ),
        .target(
            name: "PadSystem",
            dependencies: [
                .target(name: "CPython", condition: .when(platforms: [.iOS]))
            ],
            publicHeadersPath: "include",
            cSettings: [
                .define("IT2PAD_HAS_PYTHON", to: "1", .when(platforms: [.iOS])),
                .unsafeFlags(["-I", pythonHeaders], .when(platforms: [.iOS]))
            ]
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
