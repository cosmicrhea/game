import OrderedCollections

enum CreditsData {
  static let credits: OrderedDictionary<String, [String]> = [
    "Producer & Designer": ["Freya from the Discord"],

    "Environment Artists": [
      // https://sketchfab.com/jintrim3
      // https://sketchfab.com/3d-models/work-gloves-991e775b6b5b4fdab682af56d08bb119
      "Aleksandr Sagidullin",

      // https://sketchfab.com/binh6675
      // https://sketchfab.com/3d-models/glock18c-remake-3e321ef99c854f888ab32d4729b84965
      // https://sketchfab.com/3d-models/sigp320-pistol-1616f762a2c7467eadb78e3e006b3324
      "binh6675",

      // https://sketchfab.com/duanesmind
      // https://sketchfab.com/3d-models/cctv-and-keypad-access-panel-dfbf3ebd9b774babbec99989f34df691
      "Duane's Mind",

      // https://sketchfab.com/tonken
      // https://sketchfab.com/3d-models/utility-key-af35a59d5ea94b00b9ee37d4eda10b1f
      "tonken",

      // https://sketchfab.com/unknown.fbx
      // https://sketchfab.com/3d-models/zippo-lighter-1c8ef92481544dd6a49adedbf85da0ea
      "Ibrahim Taha",
      // "unknown.fbx",

      // https://sketchfab.com/AxonDesigns
      // https://sketchfab.com/3d-models/key-with-tag-16ea3fbecc6346df9859f0e18406951b
      "AxonDesigns",
    ],

    "Sound Designers": [
      // https://freesound.org/people/carlerichudon10/
      // https://freesound.org/people/carlerichudon10/sounds/466375/
      // page_*.wav
      "carlerichudon10",

      // https://cyrex-studios.itch.io/
      // https://cyrex-studios.itch.io/universal-ui-soundpack
      // Minimalist*.wav
      "Cyrex Studios",

      // https://ad-sounds.itch.io/
      // https://ad-sounds.itch.io/dialog-text-sound-effects
      // SFX_BlackBoardSingle*.wav
      "AD Sounds",

      // https://freesound.org/people/spy15/
      // https://freesound.org/people/spy15/sounds/270873/
      // shutter.wav
      "spy15",
    ],

    "Asset Pipeline Programming": [
      // Assimp
      "Christian Treffs"
    ],

    "Physics Programming": [
      // Jolt
      "Amer Koleci and Contributors",

      // SwiftGL
      "David Turnbull",
    ],

    "Graphics Programming": [
      // NanoSVG
      "Mikko Mononen"
    ],

    "Frameworks Programming": [
      // swift-image-formats
      "stackotter",

      // glfw-swift
      "ThePotatoKing55",
    ],

    "Compression Programming": [
      // zlib
      "Jean-loup Gailly",
      "Mark Adler",
    ],
  ]

  static let logos = [
    [
      Image("UI/Credits/OpenGL.png"),
      Image("UI/Credits/glTF.png"),
    ],
    [
      Image("UI/Credits/Blender.png")
    ],
    [
      Image("UI/Credits/Recast.png"),
      Image("UI/Credits/Jolt.png"),
      Image("UI/Credits/Swift.png"),
      // Image("UI/Credits/Xcode.png"),
    ],
  ]
}
