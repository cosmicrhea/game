// swift-tools-version: 6.1

import PackageDescription

let package = Package(
  name: "Glass",

  platforms: [
    .macOS(.v12),
    .custom("Linux", versionString: "6"),
    .custom("Windows", versionString: "10"),
  ],

  products: [
    .executable(name: "Glass", targets: ["Glass"])
  ],

  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    .package(url: "https://github.com/apple/swift-collections", from: "1.3.0"),
    .package(url: "https://github.com/apple/swift-log", from: "1.0.0"),
    .package(url: "https://github.com/swiftlang/swift-markdown.git", branch: "main"),
    .package(url: "https://github.com/stackotter/swift-image-formats", from: "0.3.3"),

    // .package(url: "https://github.com/krzysztofzablocki/Inject", from: "1.2.4"),

    // .package(url: "https://github.com/AdaEngine/msdf-atlas-gen", branch: "master"),
    // .package(url: "https://github.com/EvgenijLutz/HarfBuzz", branch: "main"),

    .package(path: "../glass-deps/assimp"),
    .package(path: "../glass-deps/gl"),
    .package(path: "../glass-deps/gl-math"),
    .package(path: "../glass-deps/glfw-swift"),
    .package(path: "../glass-deps/jolt"),
    .package(path: "../glass-deps/stb-rect-pack"),
    .package(path: "../glass-deps/stb-truetype"),
    // .package(path: "../glass-deps/swift-cross-ui"),
  ],

  targets: [
    .executableTarget(
      name: "Glass",

      dependencies: [
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "Collections", package: "swift-collections"),
        .product(name: "Logging", package: "swift-log"),
        .product(name: "Markdown", package: "swift-markdown"),
        .product(name: "ImageFormats", package: "swift-image-formats"),

        // .product(name: "Inject", package: "Inject"),

        // .product(name: "MSDFAtlasGen", package: "msdf-atlas-gen"),
        // .product(name: "HarfBuzz", package: "HarfBuzz"),

        .product(name: "Assimp", package: "assimp"),
        .product(name: "GL", package: "gl"),
        .product(name: "GLMath", package: "gl-math"),
        .product(name: "GLFW", package: "glfw-swift"),
        .product(name: "Jolt", package: "jolt"),
        .product(name: "STBRectPack", package: "stb-rect-pack"),
        .product(name: "STBTrueType", package: "stb-truetype"),

        // .product(name: "SwiftCrossUI", package: "swift-cross-ui"),
        // .product(name: "DefaultBackend", package: "swift-cross-ui"),
      ],

      path: "./",

      exclude: [
        // "Documentation",
        "Sources/Assets",
        "NOTES.md",
      ],

      resources: [
        .copy("Assets/Actors"),
        .copy("Assets/Common"),
        .copy("Assets/Effects"),
        .copy("Assets/Fonts"),
        .copy("Assets/Items"),
        .copy("Assets/Metal"),
        .copy("Assets/Scenes"),
        .copy("Assets/UI"),
      ],

      cSettings: [
        .define("GL_SILENCE_DEPRECATION", .when(platforms: [.macOS])),
        .define("GLES_SILENCE_DEPRECATION", .when(platforms: [.iOS, .tvOS])),
      ],

      swiftSettings: [
        .define("EMIT_FRONTEND_COMMAND_LINES", .when(platforms: [.macOS], configuration: .debug))
      ],

      linkerSettings: [
        .unsafeFlags(["-Xlinker", "-interposable"], .when(platforms: [.macOS], configuration: .debug))
      ]
    )
  ]
)
