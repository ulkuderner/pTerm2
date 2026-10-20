// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TmuxControl",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(name: "TmuxControl", targets: ["TmuxControl"])
    ],
    targets: [
        .target(name: "TmuxControl"),
        .testTarget(
            name: "TmuxControlTests",
            dependencies: ["TmuxControl"]
        )
    ]
)
