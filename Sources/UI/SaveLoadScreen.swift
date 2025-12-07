import struct GLFW.Keyboard
import struct GLFW.Mouse

@MainActor
class SaveListScreen: Screen {
  enum Layout {
    case centered
    case rightPanel
  }

  private let layout: Layout
  private let titleText: String?
  private let saveList: SaveStateList
  private var states: [SaveState]
  private let promptList = PromptList(.confirmCancel)
  private let ambientBackground: GLScreenEffect?

  init(title: String?, layout: Layout, usesAmbientBackground: Bool = false) {
    self.layout = layout
    self.titleText = title
    self.saveList = SaveStateList(frame: .zero)
    self.states = SaveState.demoSamples()
    self.ambientBackground = usesAmbientBackground ? GLScreenEffect("Effects/AmbientBackground") : nil
    super.init()

    saveList.setSaveStates(states)
    setupCallbacks()
  }

  func setupCallbacks() {
    saveList.onSelectionChanged = { [weak self] state in
      self?.handleSelectionChanged(state)
    }
    saveList.onActivate = { [weak self] state in
      self?.handleActivate(state)
    }
  }

  func handleSelectionChanged(_ state: SaveState?) {
    UISound.scroll()
    if let state {
      logger.trace("Selected save slot \(state.slotIndex)")
    } else {
      logger.trace("Selected empty save slot")
    }
  }

  func handleActivate(_ state: SaveState?) {
    UISound.select()
    if let state {
      logger.trace("Activated save slot \(state.slotIndex) (\(state.sceneName))")
    } else {
      logger.trace("Activated empty save slot")
    }
  }

  override func update(deltaTime: Float) {
    saveList.update(deltaTime: deltaTime)
  }

  override func draw() {
    guard let context = GraphicsContext.current else { return }
    let viewport = Engine.viewportSize
    context.renderer.setClearColor(Color(0.02, 0.02, 0.05, 1.0))
    ambientBackground?.draw { _ in }

    let frame = listFrame(for: viewport)
    drawBackdrop(around: frame, viewport: viewport)

    saveList.setFrame(frame)
    saveList.draw()

    if let titleText {
      let titlePosition = Point(frame.midX, frame.maxY + 48)
      let titleStyle = TextStyle.largeTitle
      titleText.draw(at: titlePosition, style: titleStyle, anchor: .bottom)
    }

    promptList.draw()
  }

  override func onKeyPressed(window: Window, key: Keyboard.Key, scancode: Int32, mods: Keyboard.Modifier) {
    if saveList.handleKey(key) { return }
    if key == .escape {
      UISound.cancel()
      back()
    }
  }

  override func onMouseButtonPressed(window: Window, button: Mouse.Button, mods: Keyboard.Modifier) {
    guard button == .left else { return }
    let point = mousePoint(in: window)
    if saveList.handleMouseClick(at: point) { return }
    saveList.handleMouseDown(at: point)
  }

  override func onMouseButtonReleased(window: Window, button: Mouse.Button, mods: Keyboard.Modifier) {
    guard button == .left else { return }
    saveList.handleMouseUp()
  }

  override func onMouseMove(window: Window, x: Double, y: Double) {
    let point = mousePoint(in: window)
    saveList.handleMouseMove(at: point)
  }

  override func onScroll(window: Window, xOffset: Double, yOffset: Double) {
    let point = mousePoint(in: window)
    saveList.handleScroll(xOffset: xOffset, yOffset: yOffset, mouse: point)
  }

  private func mousePoint(in window: Window) -> Point {
    Point(Float(window.mouse.position.x), Float(Engine.viewportSize.height) - Float(window.mouse.position.y))
  }

  private func drawBackdrop(around frame: Rect, viewport: Size) {
    switch layout {
    case .centered:
      let overlay = Rect(x: 0, y: 0, width: viewport.width, height: viewport.height)
      overlay.fill(with: Color.black.withAlphaComponent(0.65))
    case .rightPanel:
      let panel = Rect(
        x: frame.origin.x - 24,
        y: frame.origin.y - 24,
        width: frame.size.width + 48,
        height: frame.size.height + 48
      )
      RoundedRect(panel, cornerRadius: 18).draw(color: Color.black.withAlphaComponent(0.55))
    }
  }

  private func listFrame(for viewport: Size) -> Rect {
    let width = min(560, viewport.width - 320)
    let height = min(480, viewport.height - 200)
    let originY = (viewport.height - height) * 0.5

    switch layout {
    case .centered:
      let originX = (viewport.width - width) * 0.5
      return Rect(x: originX, y: originY, width: width, height: height)
    case .rightPanel:
      let originX = viewport.width - width - 100
      return Rect(x: originX, y: originY, width: width, height: height)
    }
  }
}

@MainActor
final class SaveScreen: SaveListScreen {
  init() {
    super.init(title: "SAVE", layout: .centered, usesAmbientBackground: true)
  }
}

@MainActor
final class LoadScreen: SaveListScreen {
  init() {
    super.init(title: nil, layout: .rightPanel)
  }

  override func handleSelectionChanged(_ state: SaveState?) {
    UISound.scroll()
    if let state {
      logger.trace("Selected save slot \(state.slotIndex)")
    } else {
      logger.trace("Selected empty save slot on load screen")
    }
  }

  override func handleActivate(_ state: SaveState?) {
    if state == nil {
      UISound.error()
      logger.trace("Attempted to activate empty save slot on load screen")
    } else {
      UISound.select()
      logger.trace("Activated save slot \(state!.slotIndex) (\(state!.sceneName))")
    }
  }
}
