// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "FireFuse",
  platforms: [.iOS("13.0"), .macOS("10.15")],
  products: [
    // Products define the executables and libraries a package produces, and make them visible to other packages.
    .library(
      name: "FireFuse",
      targets: ["FireFuse"]),
  ],
  dependencies: [
    // Dependencies declare other packages that this package depends on.
    .package(url: "https://github.com/nidegen/Fuse", from: "0.5.0"),
    .package(name: "Firebase", url: "https://github.com/firebase/firebase-ios-sdk", from: "7.7.0"),
  ],
  targets: [
    // Targets are the basic building blocks of a package. A target can define a module or a test suite.
    // Targets can depend on other targets in this package, and on products in packages this package depends on.
    .target(
      name: "FireFuse",
      dependencies: [
        "Fuse",
        .product(name: "FirebaseFirestore", package: "Firebase"),
        .product(name: "FirebaseFirestoreSwift-Beta", package: "Firebase"),
      ]
    ),
    .testTarget(
      name: "FireFuseTests",
      dependencies: ["FireFuse"]),
  ]
)
