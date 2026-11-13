// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RisingKit",
    platforms: [.macOS(.v14)],
    targets: [
        // 순수 로직 (창 배치 계산, 계산기, 검색 점수) — 테스트 대상
        .target(name: "RisingKitCore", path: "Sources/RisingKitCore"),
        .executableTarget(
            name: "RisingKit",
            dependencies: ["RisingKitCore"],
            path: "Sources/RisingKit"
        ),
        .testTarget(
            name: "RisingKitTests",
            dependencies: ["RisingKitCore"],
            path: "Tests/RisingKitTests"
        ),
    ]
)
