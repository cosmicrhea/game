import GLFW
import GLMath
import OrderedCollections

final class CreditsScreen: RenderLoop {
  let credits: OrderedDictionary<String, [String]> = [
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
    ],

    "Sound Designers": [
      // https://freesound.org/people/carlerichudon10/
      // https://freesound.org/people/carlerichudon10/sounds/466375/
      "carlerichudon10",

      // https://cyrex-studios.itch.io/
      // https://cyrex-studios.itch.io/universal-ui-soundpack
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

  private let promptList = PromptList(.skip)

  private let sectionGap: Float = 0

  // Animation state
  private var scrollOffset: Float = 0.0
  private var scrollSpeed: Float = 24.0  // pixels per second
  private var totalContentHeight: Float = 0.0
  private var screenHeight: Float = 0.0

  // Text styles
  private let categoryStyle = TextStyle(
    fontName: "Creato Display Bold",
    fontSize: 24,
    color: .gray500,
    alignment: .right,
    lineHeight: 1.3
  )

  private let nameStyle = TextStyle(
    fontName: "Creato Display Medium",
    fontSize: 24,
    color: .white,
    lineHeight: 1.3
  )

  func update(deltaTime: Float) {
    screenHeight = Float(Engine.viewportSize.height)

    // Calculate total content height
    calculateTotalContentHeight()

    // Update scroll position
    scrollOffset += scrollSpeed * deltaTime

    // Loop back to start when content has scrolled past
    let loopPoint = totalContentHeight + screenHeight
    if scrollOffset > loopPoint {
      scrollOffset = 0.0
    }
  }

  private func calculateTotalContentHeight() {
    let sectionSpacing: Float = 40.0
    var height: Float = 0.0

    for (category, names) in credits {
      // Get actual height of category text
      let categoryBounds = category.boundingRect(with: categoryStyle)
      height += categoryBounds.size.height

      // Get actual height of names as multiline string
      let namesText = names.sorted().joined(separator: "\n")
      let namesBounds = namesText.boundingRect(with: nameStyle, wrapWidth: Float.greatestFiniteMagnitude)
      height += namesBounds.size.height
      height += sectionSpacing  // Space between sections
    }

    totalContentHeight = height
  }

  func draw() {
    // Set black background
    GraphicsContext.current?.renderer.setClearColor(.black)

    let screenWidth = Float(Engine.viewportSize.width)
    let screenHeight = Float(Engine.viewportSize.height)

    // Calculate column widths
    let (leftColumnWidth, rightColumnWidth) = calculateColumnWidths()
    let gap: Float = 40.0

    // Center the columns horizontally
    let totalWidth = leftColumnWidth + gap + rightColumnWidth
    let leftColumnX = (screenWidth - totalWidth) / 2
    let rightColumnX = leftColumnX + leftColumnWidth + gap

    // Create column rectangles for debugging
    let leftColumnRect = Rect(x: leftColumnX, y: 0, width: leftColumnWidth, height: screenHeight)
    let rightColumnRect = Rect(x: rightColumnX, y: 0, width: rightColumnWidth, height: screenHeight)

    // Draw debug frames
    leftColumnRect.frame(with: .magenta)
    rightColumnRect.frame(with: .indigo)

    var currentY: Float = scrollOffset

    for (category, names) in credits {
      // Draw category (gray text, right-aligned in left column)
      category.draw(
        at: Point(leftColumnX, currentY),
        style: categoryStyle,
        wrapWidth: leftColumnWidth,
        anchor: .topLeft
      )

      // Get actual height of category for positioning names
      let categoryBounds = category.boundingRect(with: categoryStyle)
      var nameY = currentY

      // Draw names as a single multiline string (white text, left-aligned in right column) - sorted alphabetically
      let namesText = names.sorted().joined(separator: "\n")
      namesText.draw(
        at: Point(rightColumnX, nameY),
        style: nameStyle,
        wrapWidth: Float.greatestFiniteMagnitude,
        anchor: .topLeft
      )
      let namesBounds = namesText.boundingRect(with: nameStyle, wrapWidth: Float.greatestFiniteMagnitude)
      nameY -= namesBounds.size.height

      // Move to next section - go down (subtract Y in OpenGL)
      let totalNamesHeight = currentY - nameY
      currentY -= categoryBounds.size.height + totalNamesHeight + sectionGap
    }

    promptList.draw()
  }

  private func calculateColumnWidths() -> (left: Float, right: Float) {
    var maxCategoryWidth: Float = 0.0
    var maxNameWidth: Float = 0.0

    for (category, names) in credits {
      // Find widest category
      let categoryBounds = category.boundingRect(with: categoryStyle)
      maxCategoryWidth = max(maxCategoryWidth, categoryBounds.size.width)

      // Find widest name (check individual names for width)
      for name in names {
        let nameBounds = name.boundingRect(with: nameStyle)
        maxNameWidth = max(maxNameWidth, nameBounds.size.width)
      }
    }

    return (left: maxCategoryWidth, right: maxNameWidth)
  }
}
