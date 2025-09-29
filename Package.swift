// swift-tools-version: 6.1

import PackageDescription

let package = Package(
  name: "Red Glass",
  platforms: [
    .macOS(.v10_15),
    .custom("Windows", versionString: "10"),
  ],
  products: [
    .executable(name: "RedGlass", targets: ["RedGlass"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
    .package(url: "https://github.com/chrisaljoudi/swift-log-oslog.git", from: "0.2.1"),
    .package(url: "https://github.com/stackotter/swift-cross-ui", branch: "main"),
    .package(url: "https://github.com/SwiftGL/OpenGL.git", from: "3.0.0"),
    .package(url: "https://github.com/SwiftGL/Math.git", from: "2.0.0"),
    .package(url: "https://github.com/SwiftGL/Image.git", from: "2.0.0"),
    .package(url: "https://github.com/thepotatoking55/SwiftGLFW.git", branch: "main"),
    .package(path: "Packages/Assimp"),
  ],
  targets: [
    .executableTarget(
      name: "RedGlass",
      dependencies: [
        .product(name: "Logging", package: "swift-log"),
        .product(name: "LoggingOSLog", package: "swift-log-oslog"),
        .product(name: "SwiftCrossUI", package: "swift-cross-ui"),
        .product(name: "DefaultBackend", package: "swift-cross-ui"),
        .product(name: "SGLOpenGL", package: "OpenGL"),
        .product(name: "SGLMath", package: "Math"),
        .product(name: "SGLImage", package: "Image"),
        .product(name: "SwiftGLFW", package: "SwiftGLFW"),
        .product(name: "Assimp", package: "Assimp"),

      ],
      resources: [
        .copy("../Assets/actors"),
        .copy("../Assets/inventory"),
        .copy("../Assets/ui"),
      ],
      cSettings: [
        .define("GL_SILENCE_DEPRECATION", .when(platforms: [.macOS])),
        .define("GLES_SILENCE_DEPRECATION", .when(platforms: [.iOS, .tvOS])),
      ]
    ),
  ]
)
