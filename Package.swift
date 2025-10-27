// swift-tools-version: 6.1

import CompilerPluginSupport
import PackageDescription

import class Foundation.ProcessInfo

let env = ProcessInfo.processInfo.environment
let useLocal = (env["GAME_LOCAL_DEPS"] ?? "0") == "1"

let package = Package(
  name: "Game",

  defaultLocalization: "en",

  platforms: [
    // .macOS(.v13), // FIXME: build assimp for v13
    .macOS(.v15),
    .custom("Linux", versionString: "6"),
    .custom("Windows", versionString: "10"),
  ],

  products: [
    .executable(name: "Game", targets: ["Glass"])
  ],

  dependencies: [
    .package("assimp"),
    .package("gl"),
    .package("gl-math"),
    .package("glfw-swift"),
    .package("jolt"),
    .package("miniaudio"),
    .package("nanosvg"),
    .package("stb-perlin"),
    .package("stb-rect-pack"),
    .package("stb-text-edit"),
    .package("stb-truetype"),
    .package("swift-image-formats"),
    .package("tinyexr"),

    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    .package(url: "https://github.com/apple/swift-collections", from: "1.3.0"),
    .package(url: "https://github.com/apple/swift-log", from: "1.0.0"),
    .package(url: "https://github.com/swiftlang/swift-markdown", branch: "main"),
    //    .package(url: "https://github.com/stackotter/swift-image-formats", from: "0.3.3"),
    .package(url: "https://github.com/apple/swift-syntax", from: "509.0.0"),

    // .package(url: "https://github.com/krzysztofzablocki/Inject", from: "1.2.4"),

    // .package(url: "https://github.com/AdaEngine/msdf-atlas-gen", branch: "master"),
    // .package(url: "https://github.com/EvgenijLutz/HarfBuzz", branch: "main"),
  ],

  targets: [
    .executableTarget(
      name: "Glass",

      dependencies: [
        "GlassEditorMacros",

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
        //.product(name: "Tess", package: "libtess2"),
        .product(name: "Miniaudio", package: "miniaudio"),
        .product(name: "NanoSVG", package: "nanosvg"),
        .product(name: "STBPerlin", package: "stb-perlin"),
        .product(name: "STBRectPack", package: "stb-rect-pack"),
        .product(name: "STBTextEdit", package: "stb-text-edit"),
        .product(name: "STBTrueType", package: "stb-truetype"),
        .product(name: "TinyEXR", package: "tinyexr"),
      ],

      path: ".",

      exclude: [
        // "Documentation",
        "Sources/Assets",
        "Sources/Core/Build",
        "Sources/Core/EditorMacros",
        "NOTES.md",
        "TODO.md",
        "README.md",
      ],

      resources: [
        .copy("Assets/Actors"),
        .copy("Assets/Audio"),
        .copy("Assets/Common"),
        .copy("Assets/Effects"),
        .copy("Assets/Fonts"),
        .copy("Assets/Items"),
        .copy("Assets/Metal"),
        .copy("Assets/Scenes"),
        .copy("Assets/UI"),
        //.process("Assets/Localizable.xcstrings", localization: .default),
        .process("Assets/Localizable.xcstrings"),
      ],

      cSettings: [
        .define("GL_SILENCE_DEPRECATION", .when(platforms: [.macOS])),
        .define("GLES_SILENCE_DEPRECATION", .when(platforms: [.iOS, .tvOS])),
      ],

      swiftSettings: [
        .define("EDITOR", .when(platforms: [.macOS], configuration: .debug)),
        .define("EMIT_FRONTEND_COMMAND_LINES", .when(platforms: [.macOS], configuration: .debug)),
      ],

      linkerSettings: [
        .unsafeFlags(["-Xlinker", "-interposable"], .when(platforms: [.macOS], configuration: .debug))
      ],

      plugins: [
        "GlassBuildTools"
      ]
    ),

    .macro(
      name: "GlassEditorMacros",
      dependencies: [
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
        .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
        .product(name: "Collections", package: "swift-collections"),
      ],
      path: "Sources/Core/EditorMacros",
    ),

    .plugin(
      name: "GlassBuildTools",
      capability: .buildTool(),
      path: "Sources/Core/Build"
    ),
  ]
)

extension Package.Dependency {
  static func package(_ name: String, branch: String = "main") -> Package.Dependency {
    if useLocal {
      .package(path: "../glass-deps/\(name)")
    } else {
      .package(url: "https://github.com/cosmicrhea-game/\(name).git", branch: branch)
    }
  }
}
