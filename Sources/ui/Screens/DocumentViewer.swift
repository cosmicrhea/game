import GL
import GLFW
import GLMath

final class DocumentViewer: RenderLoop {
  let document = keepersDiary

  let caretLeft = Caret(direction: .left)
  let caretRight = Caret(direction: .right)
  //  let ref = Image("UI/RE2Doc.jpg")
  let background = Image("Items/cassette_player.png")

  let textStyle = TextStyle(fontName: "Creato Display Medium", fontSize: 24, color: .white)

  private var deltaTime: Float = 0.0
  private var currentPage: Int = 0

  private let inputPrompts = InputPrompts()

  func update(deltaTime: Float) {
    self.deltaTime = deltaTime
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
    guard currentPage < document.count - 1 else { return }
    currentPage += 1
    UISound.pageTurn()
  }

  private func previousPage() {
    guard currentPage > 0 else { return }
    currentPage -= 1
    UISound.pageTurn()
  }

  func draw() {
    // Draw reference image
    // ref.draw(in: Rect(x: 0, y: 0, width: Float(WIDTH), height: Float(HEIGHT)), tint: .white.withAlphaComponent(0.5))

    glClearColor(0, 0, 0, 1)

    // Draw background at 720x720 in the center of the screen
    let backgroundSize: Float = 360
    let backgroundX: Float = (Float(WIDTH) - backgroundSize) / 2
    let backgroundY: Float = (Float(HEIGHT) - backgroundSize) / 2
    let backgroundRect = Rect(x: backgroundX, y: backgroundY, width: backgroundSize, height: backgroundSize)
    background.draw(in: backgroundRect, tint: .white.withAlphaComponent(0.5))

    // 1. Create 640px wide section in the middle of the screen
    let sectionWidth: Float = 640
    let sectionX: Float = (Float(WIDTH) - sectionWidth) / 2
    let sectionY: Float = 0
    let sectionHeight: Float = Float(HEIGHT)
    let mainSection = Rect(x: sectionX, y: sectionY, width: sectionWidth, height: sectionHeight)

    // Debug draw the main section
    mainSection.frame(with: Color(red: 1.0, green: 0.0, blue: 0.0), lineWidth: 2.0)

    // 2. Position chevrons on left and right sides, centered vertically
    let arrowY: Float = Float(HEIGHT) / 2
    let leftArrowX: Float = sectionX
    let rightArrowX: Float = sectionX + sectionWidth - caretRight.image.naturalSize.width

    caretLeft.draw(at: Point(leftArrowX, arrowY), deltaTime: deltaTime)
    caretRight.draw(at: Point(rightArrowX, arrowY), deltaTime: deltaTime)

    // 3. Create 400px wide text area within the 640px section
    let textWidth: Float = 400
    let textAreaX: Float = sectionX + (sectionWidth - textWidth) / 2
    let textArea = Rect(x: textAreaX, y: 0, width: textWidth, height: Float(HEIGHT))

    // Debug draw the text area
    textArea.frame(with: Color(red: 0.0, green: 0.0, blue: 1.0), lineWidth: 2.0)

    // 4. Center text vertically using text measurement
    let currentText = document[currentPage]
    let textBounds = currentText.boundingRect(with: textStyle, wrapWidth: textWidth)
    let textY: Float = Float(HEIGHT) - textBounds.size.height

    // Draw the text
    currentText.draw(
      at: Point(textAreaX, textY),
      style: textStyle,
      wrapWidth: textWidth,
      anchor: .topLeft
    )

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

    // Animate with slow back-and-forth movement
    let animationOffset: Float = GLMath.sin(animationTime * 0.8) * 8  // 8px amplitude, slow speed
    let animatedX: Float = direction == .left ? point.x - animationOffset : point.x + animationOffset

    // Use the new Image API with custom tinting
    let animatedPoint = Point(animatedX, point.y)
    let rect = Rect(origin: animatedPoint, size: image.naturalSize)

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

private let recording = [
  """
  — This is Officer Mills! HQ, please respond!

  — This is HQ. What’s the situation?

  — A new monster. They’ve got these glowing eyes, look like real creepy bastards!
  """,
  """
  — My partner took one of them out at point-blank range. The thing died, but when it did it released some sort of purple smoke... Shit!

  — Officer, remain calm.

  — The smoke hit my partner head on. Now he can't stop coughing. Seems like he's having trouble breathing.
  """,
  """
  — What the fuck's going on!? Weren't we going to take care of these things with P-Z gas?

  — Calm down. We are currently confirming with Umbrella R&D...

  — Shut up! That gas...something's not right. Instead of killing them, it made them mutate—
  """,
]

private let keepersDiary = [
  """
  May 9, 1998

  At night, we played poker with Scott the guard, Alias and Steve the researcher.

  Steve was very lucky, but I think he was cheating. What a scumbag.
  """,
  """
  May 10th 1998

  Today, a high ranking researcher asked me to take care of a new monster. It looks like a gorilla without any skin. They told me to feed them live food. When I threw in a pig, they were playing with it... tearing off the pig's legs and pulling out the guts before they actually ate it.
  """,
  """
  May 11th 1998

  Around 5 o'clock this morning, Scott came in and woke me up suddenly. He was wearing a protective suit that looks like a space suit. He told me to put one on as well. I heard there was an accident in the basement lab. It's no wonder, those researchers never rest, even at night.
  """,
  """
  May 12th 1998

  I've been wearing this annoying space suit since yesterday, my skin grows musty and feels very itchy. By way of revenge, I didn't feed those dogs today. Now I feel better.
  """,
  """
  May 13th 1998

  I went to the medical room because my back is all swollen and feels itchy. They put a big bandage on my back and the doctor told me I did not need to wear the space suit any more. I guess I can sleep well tonight.
  """,
  """
  May 14th 1998

  When I woke up this morning, I found another blister on my foot. It was annoying and I ended up dragging my foot as I went to the dog's pen. They have been quiet since morning, which is very unusual. I found that some of them had escaped. I'll be in real trouble if the higher-ups find out.
  """,
  """
  May 15th 1998

  Even though I didn't feel well, I decided to go see Nancy. It's my first day off in a long time but I was stopped by the guard on the way out. They say the company has ordered that no one leave the grounds. I can't even make a phone call. What kind of joke is this?!
  """,
  """
  May 16th 1998

  I heard a researcher who tried to escape from this mansion was shot last night. My entire body feels burning and itchy at night. When I was scratching the swelling on my arms, a lump of rotten flesh dropped off. What the hell is happening to me?
  """,
  """
  May 19, 1998

  Fever gone but itchy. Hungry and eat doggy food. Itchy itchy Scott came. Ugly face so killed him. Tasty.
  """,
  """
  4

  Itchy.
  Tasty.
  """,
]
