// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HadithKit",
    // The engine deliberately targets iOS 18 even though the app requires 26.
    // Nothing here depends on Liquid Glass, so an eventual iOS 18 backport of
    // the UI needs no changes below this line.
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "HadithKit", targets: ["HadithKit"])
    ],
    // One dependency, on purpose. swift-transformers would give us the BERT
    // tokenizer for free but drags in swift-nio, swift-crypto and eight more
    // packages — a lot of network machinery for an app that never opens a
    // socket. BertTokenizer.swift implements the ~150 lines we actually need,
    // and TokenizerParityTests proves it matches the reference by embedding the
    // golden queries and comparing against the vectors Transformers.js produced.
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.9.0")
    ],
    targets: [
        .target(
            name: "HadithKit",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")],
            swiftSettings: [
                // Optimize even in Debug. The vector scan is 47k × 384 int8 dot
                // products; measured on this machine it runs in 0.5ms at -O and
                // 412ms at -Onone — an 800× difference that decides whether
                // search feels instant or broken. Without this, anyone running
                // the app from Xcode sees the broken version and has no way to
                // know it isn't the real one.
                .unsafeFlags(["-O"], .when(configuration: .debug))
            ]
        )
    ]
)
