// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "TKVisualForge",
    platforms: [
        // 我们需要较高的 iOS 版本来支持高级的 Metal 视频渲染管线
        .iOS(.v14)
    ],
    products: [
        .library(
            name: "TKVisualForge",
            targets: ["TKVisualForge"]),
    ],
    targets: [
        .target(
            name: "TKVisualForge",
            dependencies: [],
            // 明确指定源代码存放的路径
            path: "Sources/TKVisualForge"
        )
    ]
)
