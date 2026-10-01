// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RuniTransfer",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "RuniTransfer", targets: ["RuniTransfer"]),
    ],
    dependencies: [
        .package(path: "../CoreKit"),
        .package(path: "../CoreUI"),
        .package(path: "../RunKit"),
        .package(path: "../RunUI"),
        .package(path: "../VisualiserUI"),
    ],
    targets: [
        .target(
            name: "RuniTransfer",
            dependencies: [
                .product(name: "CoreUI", package: "CoreUI"),
                .product(name: "RunKit", package: "RunKit"),
                .product(name: "RunUI", package: "RunUI"),
                .product(name: "VisualiserUI", package: "VisualiserUI"),
            ]
        ),
        .testTarget(
            name: "RuniTransferTests",
            dependencies: [
                "RuniTransfer",
                .product(name: "CoreKit", package: "CoreKit"),
                .product(name: "RunKit", package: "RunKit"),
                .product(name: "VisualiserUI", package: "VisualiserUI"),
            ]
        ),
    ]
)
