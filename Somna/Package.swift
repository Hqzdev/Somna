// swift-tools-version: 6.1
//
// SomnaCore — the pure calculation layer of Somna (Swift + Foundation only).
// The same sources in Somna/Core are compiled into the iPhone app through the
// Xcode project; this package lets them be tested on their own
// (`swift test` in this folder) and reused later by an Apple Watch app.
//

import PackageDescription

let package = Package(
    name: "SomnaCore",
    platforms: [.iOS(.v18), .macOS(.v15), .watchOS(.v11)],
    products: [
        .library(name: "SomnaCore", targets: ["SomnaCore"])
    ],
    targets: [
        .target(name: "SomnaCore", path: "Somna/Core"),
        .testTarget(name: "SomnaCoreTests", dependencies: ["SomnaCore"], path: "SomnaCoreTests")
    ],
    swiftLanguageModes: [.v5]
)
