// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FermataCore",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "FermataCore", targets: ["FermataCore"]),
    ],
    targets: [
        .target(name: "FermataCore"),
        .testTarget(name: "FermataCoreTests", dependencies: ["FermataCore"]),
    ],
    swiftLanguageModes: [.v6]
)
