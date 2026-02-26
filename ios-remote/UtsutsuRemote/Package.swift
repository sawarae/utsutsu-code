// swift-tools-version: 5.9
// This is provided for reference. Build with Xcode by opening the .xcodeproj.
import PackageDescription

let package = Package(
    name: "UtsutsuRemote",
    platforms: [.iOS(.v17)],
    targets: [
        .executableTarget(
            name: "UtsutsuRemote",
            path: "UtsutsuRemote"
        ),
    ]
)
