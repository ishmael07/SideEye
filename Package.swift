// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SideEye",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SideEyeCore"),
        .executableTarget(name: "SideEye", dependencies: ["SideEyeCore"]),
        .testTarget(name: "SideEyeCoreTests", dependencies: ["SideEyeCore"]),
    ]
)
