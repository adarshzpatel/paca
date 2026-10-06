// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Paca",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HerdrKit", targets: ["HerdrKit"]),
        .executable(name: "paca-probe", targets: ["paca-probe"]),
        .executable(name: "Paca", targets: ["Paca"]),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.2.0"),
    ],
    targets: [
        .target(name: "HerdrKit"),
        .target(name: "PacaTheme"),
        .executableTarget(name: "paca-probe", dependencies: ["HerdrKit", "PacaTheme"]),
        .executableTarget(
            name: "Paca",
            dependencies: ["HerdrKit", "PacaTheme", .product(name: "SwiftTerm", package: "SwiftTerm")],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "HerdrKitTests", dependencies: ["HerdrKit"]),
        .testTarget(name: "PacaThemeTests", dependencies: ["PacaTheme"]),
    ],
    swiftLanguageModes: [.v5]
)
