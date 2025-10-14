import Foundation
import GL
import GLFW
import GLMath
import ImageFormats
import OrderedCollections

//private protocol Credit: Sendable {}
//extension String: Credit {}
//extension Image: Credit {}

//private struct Credit: ExpressibleByStringLiteral {
//  var name: String?
//  var image: Image?
//
//  init(stringLiteral value: String) { self.name = value }
//  init(image: Image) { self.image = image }
//}

private let credits: OrderedDictionary<String, [String]> = [
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

private let logos = [
  Image("UI/Credits/Blender.png"),
  Image("UI/Credits/glTF.png"),
  Image("UI/Credits/Jolt.png"),
  Image("UI/Credits/OpenGL.png"),
  Image("UI/Credits/Recast.png"),
  Image("UI/Credits/Swift.png"),
  Image("UI/Credits/Xcode.png"),
]

final class CreditsScreen: RenderLoop {
  private let promptList = PromptList(.skip)

  private let sectionGap: Float = 0

  // Animation state
  private var scrollOffset: Float = Engine.viewportSize.height
  private var scrollSpeed: Float = 24.0  // pixels per second
  private var scrollTurbo: Bool = false
  private var totalContentHeight: Float = 0.0
  private var screenHeight: Float = 0.0

  // Offscreen rendering
  private var creditsImage: Image?

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

  func onKey(window: GLFWWindow, key: Keyboard.Key, scancode: Int32, state: ButtonState, mods: Keyboard.Modifier) {
    if key == .space { scrollTurbo = state == .pressed }
  }

  func onMouseButton(window: GLFWWindow, button: Mouse.Button, state: ButtonState, mods: Keyboard.Modifier) {
    if button == .left { scrollTurbo = state == .pressed }
  }

  func update(deltaTime: Float) {
    screenHeight = Engine.viewportSize.height

    // Calculate total content height
    calculateTotalContentHeight()

    // Create offscreen image if not exists
    if creditsImage == nil {
      createCreditsImage()
    }

    // Update scroll position
    scrollOffset -= scrollSpeed * (scrollTurbo ? 16 : 1) * deltaTime
    print("scrollOffset: \(scrollOffset); totalContentHeight: \(totalContentHeight); screenHeight: \(screenHeight)")

    // Loop back to start when the bottom of the credits image hits the top of the screen
    // The bottom of the image is at: scrollOffset + totalContentHeight
    // The top of the screen is at: screenHeight
    if scrollOffset < -totalContentHeight {
      scrollOffset = screenHeight
    }
  }

  private func calculateTotalContentHeight() {
    var height: Float = 0.0

    for (category, names) in credits {
      // Get actual height of category text
      let categoryBounds = category.boundingRect(with: categoryStyle)
      // Get actual height of names as multiline string
      let namesText = names.sorted().joined(separator: "\n")
      let namesBounds = namesText.boundingRect(with: nameStyle, wrapWidth: Float.greatestFiniteMagnitude)
      height += max(categoryBounds.size.height, namesBounds.size.height)
      height += sectionGap  // Space between sections
    }

    totalContentHeight = height
  }

  func draw() {
    // Set black background
    GraphicsContext.current?.renderer.setClearColor(.black)

    // Draw the offscreen credits image with scrolling
    if let creditsImage = creditsImage {
      let screenHeight = Engine.viewportSize.height
      let imageHeight = creditsImage.naturalSize.height
      let yPosition = screenHeight - scrollOffset
      let drawPoint = Point(0, yPosition)

      creditsImage.draw(at: drawPoint)
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

  private func createCreditsImage() {
    let currentScreenHeight = Engine.viewportSize.height
    let imageHeight = totalContentHeight  // Just the content height, no padding needed
    let imageSize = Size(Engine.viewportSize.width, imageHeight)

    creditsImage = Image(size: imageSize, pixelScale: 1.0) {
      // Render all credits content to the offscreen image
      self.renderCreditsContent()
    }
  }

  private func renderCreditsContent() {
    let screenWidth = Float(Engine.viewportSize.width)
    let imageHeight = totalContentHeight

    // Calculate column widths
    let (leftColumnWidth, rightColumnWidth) = calculateColumnWidths()
    let gap: Float = 24.0 * 1.5

    // Center the columns horizontally
    let totalWidth = leftColumnWidth + gap + rightColumnWidth
    let leftColumnX = (screenWidth - totalWidth) / 2
    let rightColumnX = leftColumnX + leftColumnWidth + gap

    print(
      "Column positions: left=\(leftColumnX), right=\(rightColumnX), widths: \(leftColumnWidth)x\(rightColumnWidth)")

    var currentY: Float = imageHeight  // Start from top of the image (OpenGL Y=0 is bottom)

    for (category, names) in credits {
      print("Drawing category: '\(category)' at Y: \(currentY)")

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
      print("Drawing names: '\(namesText.prefix(50))...' at Y: \(nameY)")
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
  }
}
