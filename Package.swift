// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "CodexAccounts", platforms: [.macOS(.v14)],
    products: [.executable(name: "CodexAccounts", targets: ["CodexAccounts"])],
    targets: [.target(name: "SwitcherCore"),
              .executableTarget(name: "CodexAccounts", dependencies: ["SwitcherCore"]),
              .testTarget(name: "SwitcherCoreTests", dependencies: ["SwitcherCore"])])
