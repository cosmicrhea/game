import GL
import GLFW
import GLMath

struct Document: Sendable {
  var id: String?
  var displayName: String?
  var image: Image?
  var frontMatter: String?
  var pages: [String]
}

final class DocumentViewer: RenderLoop {
  let document: Document

  private let caretLeft = Caret(direction: .left)
  private let caretRight = Caret(direction: .right)
  //let ref = Image("UI/RE2Doc.jpg")

  private let textStyle = TextStyle(fontName: "Creato Display Medium", fontSize: 24, color: .white)

  private var deltaTime: Float = 0.0
  private var currentPage: Int = 0

  // Animation state
  private var animationTime: Float = 0.0
  private var isAnimating: Bool = false
  private var animationDuration: Float = 0.3
  private var previousPageIndex: Int = 0
  private var animationDirection: Int = 1  // 1 for forward (right), -1 for backward (left)
  private let pageAnimationEasing: Easing = .easeInOutCubic

  private let inputPrompts = InputPrompts()

  init(document: Document) {
    self.document = document
  }

  func update(deltaTime: Float) {
    self.deltaTime = deltaTime

    // Update animation
    if isAnimating {
      animationTime += deltaTime
      if animationTime >= animationDuration {
        isAnimating = false
        animationTime = 0.0
      }
    }
  }

  func onKeyPressed(window: GLFWWindow, key: Keyboard.Key, scancode: Int32, mods: Keyboard.Modifier) {
    switch key {
    case .left, .a: previousPage()
    case .right, .d: nextPage()
    default: break
    }
  }

  func onMouseButtonPressed(window: GLFWWindow, button: Mouse.Button, mods: Keyboard.Modifier) {
    switch button {
    case .left: nextPage()
    default: break
    }
  }

  private func nextPage() {
    let totalPages = getTotalPageCount()
    guard currentPage < totalPages - 1 else { return }
    guard !isAnimating else { return }

    previousPageIndex = currentPage
    currentPage += 1
    animationDirection = 1  // Forward (right)
    startPageAnimation()
    UISound.pageTurn()
  }

  private func previousPage() {
    guard currentPage > 0 else { return }
    guard !isAnimating else { return }

    previousPageIndex = currentPage
    currentPage -= 1
    animationDirection = -1  // Backward (left)
    startPageAnimation()
    UISound.pageTurn()
  }

  private func getTotalPageCount() -> Int {
    return document.pages.count + (hasFrontmatter() ? 1 : 0)
  }

  private func hasFrontmatter() -> Bool {
    return document.frontMatter != nil && !document.frontMatter!.isEmpty
  }

  private func startPageAnimation() {
    isAnimating = true
    animationTime = 0.0
  }

  func draw() {
    // Draw reference image
    // ref.draw(in: Rect(x: 0, y: 0, width: Float(WIDTH), height: Float(HEIGHT)), tint: .white.withAlphaComponent(0.5))

    GraphicsContext.current?.renderer.setClearColor(.black)

    // glClearColor(0, 0, 0, 1)

    // Draw background in the center of the screen
    let backgroundSize: Float = 360
    let backgroundX: Float = (Float(WIDTH) - backgroundSize) / 2
    let backgroundY: Float = (Float(HEIGHT) - backgroundSize) / 2
    let backgroundRect = Rect(x: backgroundX, y: backgroundY, width: backgroundSize, height: backgroundSize)
    document.image?.draw(in: backgroundRect, tint: .white.withAlphaComponent(0.25))

    // 1. Create 640px wide section in the middle of the screen
    let sectionWidth: Float = 640
    let sectionX: Float = (Float(WIDTH) - sectionWidth) / 2
    let _: Float = 0  // sectionY
    let _: Float = Float(HEIGHT)  // sectionHeight
    //let mainSection = Rect(x: sectionX, y: sectionY, width: sectionWidth, height: sectionHeight)

    // Debug draw the main section
    // mainSection.frame(with: .rose)

    // 2. Position chevrons on left and right sides, centered vertically
    let arrowY: Float = Float(HEIGHT) / 2
    let leftArrowX: Float = sectionX
    let rightArrowX: Float = sectionX + sectionWidth - (caretRight.image.naturalSize.width * 0.5 * 1.5)

    // Update caret visibility based on current page
    let totalPages = getTotalPageCount()
    caretLeft.visible = currentPage > 0
    caretRight.visible = currentPage < totalPages - 1

    caretLeft.draw(at: Point(leftArrowX, arrowY), deltaTime: deltaTime)
    caretRight.draw(at: Point(rightArrowX, arrowY), deltaTime: deltaTime)

    // 3. Create 400px wide text area within the 640px section
    let textWidth: Float = 400
    let textAreaX: Float = sectionX + (sectionWidth - textWidth) / 2
    let textArea = Rect(x: textAreaX, y: 0, width: textWidth, height: Float(HEIGHT))

    // Debug draw the text area
    // textArea.frame(with: .indigo)

    // 4. Center text vertically using text measurement
    let currentText: String
    let currentTextStyle: TextStyle

    // Check if we're showing frontmatter (first page and frontmatter exists)
    if currentPage == 0, let frontmatter = document.frontMatter, !frontmatter.isEmpty {
      currentText = frontmatter
      // Use centered alignment for frontmatter
      currentTextStyle = TextStyle(
        fontName: textStyle.fontName,
        fontSize: textStyle.fontSize,
        color: textStyle.color,
        alignment: .center
      )
    } else {
      // Calculate which page index to use (accounting for frontmatter)
      let pageIndex = hasFrontmatter() ? currentPage - 1 : currentPage
      currentText = document.pages[pageIndex]
      currentTextStyle = textStyle
    }

    let textBounds = currentText.boundingRect(with: currentTextStyle, wrapWidth: textWidth)
    let baseTextY: Float = textArea.origin.y + (textArea.size.height - textBounds.size.height) / 2

    if isAnimating {
      // Draw both old and new text during animation
      let rawProgress: Float = animationTime / animationDuration
      let animationProgress: Float = pageAnimationEasing.apply(rawProgress)

      // Old text (fading out, moving in opposite direction of animation)
      let oldText: String
      let oldTextStyle: TextStyle

      // Check if old page was frontmatter
      if previousPageIndex == 0, hasFrontmatter() {
        oldText = document.frontMatter!
        oldTextStyle = TextStyle(
          fontName: textStyle.fontName,
          fontSize: textStyle.fontSize,
          color: textStyle.color.withAlphaComponent(1.0 - animationProgress),
          alignment: .center
        )
      } else {
        // Calculate which page index to use (accounting for frontmatter)
        let oldPageIndex = hasFrontmatter() ? previousPageIndex - 1 : previousPageIndex
        oldText = document.pages[oldPageIndex]
        oldTextStyle = TextStyle(
          fontName: textStyle.fontName,
          fontSize: textStyle.fontSize,
          color: textStyle.color.withAlphaComponent(1.0 - animationProgress)
        )
      }

      let oldTextBounds = oldText.boundingRect(with: oldTextStyle, wrapWidth: textWidth)
      let oldTextY: Float = textArea.origin.y + (textArea.size.height - oldTextBounds.size.height) / 2
      let oldTextX: Float = textAreaX - animationProgress * 50.0 * Float(animationDirection)

      oldText.draw(
        at: Point(oldTextX, oldTextY),
        style: oldTextStyle,
        wrapWidth: textWidth,
        anchor: .bottomLeft
      )

      // New text (fading in, moving in from direction of animation)
      let newTextX: Float = textAreaX + (1.0 - animationProgress) * 50.0 * Float(animationDirection)
      let newFadeAlpha: Float = animationProgress

      let newStyle = TextStyle(
        fontName: currentTextStyle.fontName,
        fontSize: currentTextStyle.fontSize,
        color: currentTextStyle.color.withAlphaComponent(newFadeAlpha),
        alignment: currentTextStyle.alignment
      )

      currentText.draw(
        at: Point(newTextX, baseTextY),
        style: newStyle,
        wrapWidth: textWidth,
        anchor: .bottomLeft
      )
    } else {
      // Draw current text normally
      currentText.draw(
        at: Point(textAreaX, baseTextY),
        style: currentTextStyle,
        wrapWidth: textWidth,
        anchor: .bottomLeft
      )
    }

    // Draw the input prompts
    if let prompts = InputPromptGroups.groups["Document Viewer"] {
      inputPrompts.drawHorizontal(
        prompts: prompts,
        inputSource: .keyboardMouse,
        windowSize: (Int32(WIDTH), Int32(HEIGHT)),
        origin: (Float(WIDTH) - 56, 12),
        anchor: .bottomRight
      )
    }
  }
}

public final class Caret {
  private let direction: Direction
  public let image: Image
  public var visible: Bool = true

  private var animationTime: Float = 0

  public enum Direction {
    case left
    case right
  }

  public init(direction: Direction) {
    self.direction = direction

    switch direction {
    case .left: image = Image("UI/Icons/Carets/caret-left.png")
    case .right: image = Image("UI/Icons/Carets/caret-right.png")
    }
  }

  public func draw(at point: Point, tint: Color = .emerald, deltaTime: Float) {
    // Update animation time with proper delta time
    animationTime += deltaTime

    guard visible else { return }

    // Animate with slow back-and-forth movement
    let animationOffset: Float = GLMath.sin(animationTime * 0.8) * 8  // 8px amplitude, slow speed
    let animatedX: Float = direction == .left ? point.x - animationOffset : point.x + animationOffset

    // Use the new Image API with custom tinting
    let animatedPoint = Point(animatedX, point.y)
    let originalSize = image.naturalSize
    let scale: Float = 0.5  // Half size
    let elongatedWidth = originalSize.width * scale * 1.5  // Make wider
    let elongatedHeight = originalSize.height * scale  // Keep height at half
    let rect = Rect(origin: animatedPoint, size: Size(elongatedWidth, elongatedHeight))

    // Draw with tint by directly calling the renderer
    if let context = GraphicsContext.current {
      context.renderer.drawImage(
        textureID: image.textureID,
        in: rect,
        tint: tint
      )
    }
  }
}
