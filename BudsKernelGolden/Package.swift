// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "BudsKernelGolden",
  platforms: [
    .iOS(.v15),
    .macOS(.v13)
  ],
  products: [
    .library(
      name: "BudsKernelGolden",
      targets: ["BudsKernelGolden"]
    ),
  ],
  targets: [
    .target(
      name: "BudsKernelGolden"
    ),
    .testTarget(
      name: "BudsKernelGoldenTests",
      dependencies: ["BudsKernelGolden"],
      resources: [
        .process("Fixtures")
      ]
    )
  ]
)
