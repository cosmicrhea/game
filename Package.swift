// swift-tools-version: 6.1

import PackageDescription

let package = Package(
  name: "Glass",

  platforms: [
    .macOS(.v10_15),
    .custom("Linux", versionString: "6"),
    .custom("Windows", versionString: "10"),
  ],

  products: [
    .executable(name: "Glass", targets: ["Glass"])
  ],

  dependencies: [
    .package(url: "https://github.com/apple/swift-log", from: "1.0.0"),
    .package(url: "https://github.com/chrisaljoudi/swift-log-oslog", from: "0.2.1"),
    .package(url: "https://github.com/stackotter/swift-image-formats", from: "0.3.3"),
    // .package(url: "https://github.com/stackotter/swift-cross-ui", branch: "main"),
    // .package(url: "https://github.com/SwiftGL/OpenGL.git", from: "3.0.0"),
    // .package(url: "https://github.com/thepotatoking55/SwiftGLFW.git", branch: "main"),
    .package(path: "../glass-deps/assimp"),
    .package(path: "../glass-deps/gl"),
    .package(path: "../glass-deps/gl-math"),
    .package(path: "../glass-deps/glfw-swift"),
    .package(path: "../glass-deps/stb-truetype"),
    .package(path: "../glass-deps/swift-cross-ui"),
//    .package(path: "../glass-deps/pango"),
  ],

  targets: [
    .executableTarget(
      name: "Glass",

      dependencies: [
        .product(name: "Logging", package: "swift-log"),
        .product(name: "LoggingOSLog", package: "swift-log-oslog"),
        .product(name: "ImageFormats", package: "swift-image-formats"),
        .product(name: "SwiftCrossUI", package: "swift-cross-ui"),
        .product(name: "DefaultBackend", package: "swift-cross-ui"),
        .product(name: "GL", package: "gl"),
        .product(name: "GLMath", package: "gl-math"),
        .product(name: "GLFW", package: "glfw-swift"),
        .product(name: "Assimp", package: "assimp"),
        .product(name: "STBTrueType", package: "stb-truetype"),

//        .product(name: "Pango", package: "pango"),
      ],

      resources: [
        .copy("../Assets/actors"),
        .copy("../Assets/common"),
        .copy("../Assets/fonts"),
        .copy("../Assets/inventory"),
        .copy("../Assets/ui"),
        .copy("../Assets/icon.png"),
        .copy("../Assets/icon~squircle.png"),
        .copy("../Assets/icon.webp"),
        .copy("../Assets/icon~squircle.webp"),
      ],

      cSettings: [
        .define("GL_SILENCE_DEPRECATION", .when(platforms: [.macOS])),
        .define("GLES_SILENCE_DEPRECATION", .when(platforms: [.iOS, .tvOS])),
      ]
    )
  ]
)
