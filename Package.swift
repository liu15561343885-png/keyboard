// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PrivateKeyboard",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "PrivateKeyboardCore", targets: ["PrivateKeyboardCore"]),
        .library(name: "PrivateKeyboardUpdater", targets: ["PrivateKeyboardUpdater"]),
        .executable(name: "dictionary-builder", targets: ["DictionaryBuilder"]),
        .executable(name: "manifest-tool", targets: ["ManifestTool"]),
        .executable(name: "core-check", targets: ["CoreCheck"]),
        .executable(name: "ngram-builder", targets: ["NgramBuilder"]),
        .executable(name: "holdout-builder", targets: ["HoldoutBuilder"])
    ],
    targets: [
        .target(
            name: "PrivateKeyboardCore",
            path: "SharedCore/Sources/PrivateKeyboardCore"
        ),
        .target(
            name: "PrivateKeyboardUpdater",
            dependencies: ["PrivateKeyboardCore"],
            path: "SharedCore/Sources/PrivateKeyboardUpdater"
        ),
        .executableTarget(
            name: "DictionaryBuilder",
            dependencies: ["PrivateKeyboardCore"],
            path: "DictionaryBuilder/Sources/DictionaryBuilder"
        ),
        .executableTarget(
            name: "ManifestTool",
            dependencies: ["PrivateKeyboardCore", "PrivateKeyboardUpdater"],
            path: "Tools/ManifestTool"
        ),
        .executableTarget(
            name: "HoldoutBuilder",
            dependencies: ["PrivateKeyboardCore"],
            path: "Tools/HoldoutBuilder"
        ),
        .executableTarget(
            name: "NgramBuilder",
            dependencies: ["PrivateKeyboardCore"],
            path: "Tools/NgramBuilder"
        ),
        .executableTarget(
            name: "CoreCheck",
            dependencies: ["PrivateKeyboardCore", "PrivateKeyboardUpdater"],
            path: "Tests/CoreCheck"
        ),
        .testTarget(
            name: "PrivateKeyboardCoreTests",
            dependencies: ["PrivateKeyboardCore", "PrivateKeyboardUpdater"],
            path: "Tests/PrivateKeyboardCoreTests"
        )
    ]
)
