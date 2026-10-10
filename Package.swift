// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "HoverPortal", platforms: [.macOS(.v14)],
    products: [.executable(name: "HoverPortal", targets: ["HoverPortal"])],
    targets: [.target(name: "FaceRuntime", publicHeadersPath: "include"),
              .executableTarget(name: "HoverPortal", dependencies: ["FaceRuntime"])])
