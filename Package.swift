// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "TestAsync",
    platforms: [.macOS("12")],
    products: [
        .executable(
            name: "Scratchpad",
            targets: [
                "AsyncCombineAdapters",
                "Scratchpad"]),
    ],
    
    dependencies: [
    ],
    
    targets: [
        .target(
            name: "AsyncCombineAdapters",
            dependencies: []),
            
        .testTarget(
            name: "AsyncCombineAdaptersTests",
            dependencies: [
                "AsyncCombineAdapters"]),
            
        .executableTarget(
            name: "Scratchpad",
            dependencies: [
                "AsyncCombineAdapters"]),
    ]
)
