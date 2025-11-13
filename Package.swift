// swift-tools-version: 6.1

import CompilerPluginSupport
import PackageDescription

import class Foundation.ProcessInfo

let env = ProcessInfo.processInfo.environment
let useLocalDependencies = env["USER"] == "fa"

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
    .executable(name: "Game", targets: ["Game"])
  ],

  dependencies: [
    .package("assimp", branch: "master"),
    .package("gl", branch: "master"),
    .package("gl-math", branch: "master"),
    .package("glfw-swift"),
    .package("jolt"),
    .package("miniaudio"),
    .package("nanosvg", branch: "master"),
    .package("stb-perlin"),
    .package("stb-rect-pack"),
    .package("stb-text-edit"),
    .package("stb-truetype"),
    .package("swift-image-formats"),
    .package("theora"),
    .package("tinyexr", branch: "release"),

    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    .package(url: "https://github.com/apple/swift-collections", from: "1.3.0"),
    .package(url: "https://github.com/apple/swift-log", from: "1.0.0"),
    .package(url: "https://github.com/swiftlang/swift-markdown", branch: "main"),
    //    .package(url: "https://github.com/stackotter/swift-image-formats", from: "0.3.3"),
    .package(url: "https://github.com/apple/swift-syntax", from: "509.0.0"),

    //.package(url: "https://github.com/krzysztofzablocki/Inject", branch: "main"),
    // .package(url: "https://github.com/AdaEngine/msdf-atlas-gen", branch: "master"),
    // .package(url: "https://github.com/EvgenijLutz/HarfBuzz", branch: "main"),
  ],

  targets: [
    .executableTarget(
      name: "Game",
      dependencies: [
        "GameMacros",

        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "Collections", package: "swift-collections"),
        .product(name: "Logging", package: "swift-log"),
        .product(name: "Markdown", package: "swift-markdown"),
        .product(name: "ImageFormats", package: "swift-image-formats"),

        // .product(name: "MSDFAtlasGen", package: "msdf-atlas-gen"),
        //"Inject",
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
        .product(name: "Theora", package: "theora"),
        .product(name: "TinyEXR", package: "tinyexr"),
      ],

      path: ".",

      exclude: [
        "Sources/Assets",
        "Sources/Core/Build",
        "Sources/Core/Macros",
        //"Sources/Core/Shell",
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
        .define("GLES_SILENCE_DEPRECATION", .when(platforms: [.iOS, .tvOS, .visionOS])),
      ],

      swiftSettings: [
        //.define("EDITOR"),
      ],

      linkerSettings: [
        .unsafeFlags(["-Xlinker", "-interposable"], .when(platforms: [.macOS]))
      ],

      plugins: [
        "GameBuildTools"
      ]
    ),

    .macro(
      name: "GameMacros",
      dependencies: [
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
        .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
        .product(name: "Collections", package: "swift-collections"),
      ],
      path: "Sources/Core/Macros",
    ),

    .plugin(
      name: "GameBuildTools",
      capability: .buildTool,
      path: "Sources/Core/Build"
    ),
  ]
)

extension Package.Dependency {
  static func package(_ name: String, branch: String = "main") -> Package.Dependency {
    if useLocalDependencies {
      .package(path: "../glass-deps/\(name)")
    } else {
      .package(url: "https://github.com/cosmicrhea-game/\(name)", branch: branch)
    }
  }
}
