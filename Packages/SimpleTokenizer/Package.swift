// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SimpleTokenizer",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "SimpleTokenizer", targets: ["SimpleTokenizer"])
    ],
    targets: [
        .target(
            name: "SimpleTokenizer",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ],
    cxxLanguageStandard: .cxx14
)
