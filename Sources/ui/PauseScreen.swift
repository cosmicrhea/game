import Foundation

import func Foundation.NSLocalizedString

final class PauseScreen: Screen {
  private let listMenu = ListMenu()

  override init() {
    super.init()

    listMenu.setItems([
      ListMenu.MenuItem(id: "back", label: "Return to Game") {
        // Close pause screen by accessing MainLoop
        if let mainLoop = MainLoop.shared {
          mainLoop.hidePauseScreen()
          UISound.cancel()
        }
      },

      ListMenu.MenuItem(id: "options", label: "Options") {
        self.navigate(to: OptionsScreen(presentationContext: .inGamePause))
      },

      ListMenu.MenuItem(id: "give_up", label: "Give Up") {

      },
    ])
  }

  override func update(deltaTime: Float) {
    listMenu.update(deltaTime: deltaTime)
  }

  override func onKeyPressed(window: Window, key: Keyboard.Key, scancode: Int32, mods: Keyboard.Modifier) {
    listMenu.handleKeyPressed(key)
  }

  override func onMouseButtonPressed(window: Window, button: Mouse.Button, mods: Keyboard.Modifier) {
    if button == .left {
      let mousePosition = Point(
        Float(window.mouse.position.x), Float(Engine.viewportSize.height) - Float(window.mouse.position.y))
      listMenu.handleMouseClick(at: mousePosition)
    }
  }

  override func onMouseMove(window: Window, x: Double, y: Double) {
    let mousePosition = Point(Float(x), Float(Engine.viewportSize.height) - Float(y))
    listMenu.handleMouseMove(at: mousePosition)
  }

  override func draw() {
    // Draw the menu using ListMenu
    listMenu.draw()
  }
}

/// Full pause screen that renders a NavigationStack
final class PauseScreenStack: RenderLoop {
  private let navigationStack: NavigationStack
  private let promptList: PromptList
  private let vignetteEffect = GLScreenEffect("Effects/TitleScreenVignette")
  private var animatedVignetteStrength: Float = 0.0

  // Animation timing - easily tweakable
  private let overlayFadeInSpeed: Float = 4.0  // Fade-in speed (higher = faster)
  private let overlayFadeOutSpeed: Float = 12.0  // Fade-out speed (super quick!)
  private let targetOverlayOpacity: Float = 0.6  // Semi-transparent black opacity
  private let vignetteSpeed: Float = 3.0  // Vignette animation speed

  // Overlay fade animation state
  private var overlayOpacity: Float = 0.0
  var isFadingOut: Bool = false

  var isAtRoot: Bool {
    navigationStack.isAtRoot
  }

  var isFadeOutComplete: Bool {
    isFadingOut && overlayOpacity <= 0.001  // Use small threshold for floating point precision
  }

  init() {
    promptList = PromptList(.menuRoot)
    navigationStack = NavigationStack()
    navigationStack.setInitialScreen(PauseScreen())
  }

  func onAttach(window: Window) {
    // Start fade-in when pause screen is shown
    overlayOpacity = 0.0
    isFadingOut = false
  }

  func onDetach(window: Window) {
    // Start fade-out when pause screen is being hidden
    isFadingOut = true
  }

  func startFadeOut() {
    isFadingOut = true
  }

  func update(deltaTime: Float) {
    navigationStack.update(deltaTime: deltaTime)

    // Animate vignette strength based on navigation state
    let targetVignetteStrength: Float = navigationStack.isAtRoot ? 0.0 : 0.6
    let vignetteDelta = (targetVignetteStrength - animatedVignetteStrength) * vignetteSpeed * deltaTime
    animatedVignetteStrength += vignetteDelta

    // Animate overlay fade-in or fade-out
    if isFadingOut {
      // Fade out super quick
      let overlayDelta = (0.0 - overlayOpacity) * overlayFadeOutSpeed * deltaTime
      overlayOpacity += overlayDelta
      // Clamp to 0
      if overlayOpacity < 0.0 {
        overlayOpacity = 0.0
      }
    } else {
      // Fade in
      let overlayDelta = (targetOverlayOpacity - overlayOpacity) * overlayFadeInSpeed * deltaTime
      overlayOpacity += overlayDelta
    }
  }

  func onKeyPressed(window: Window, key: Keyboard.Key, scancode: Int32, mods: Keyboard.Modifier) {
    navigationStack.onKeyPressed(window: window, key: key, scancode: scancode, mods: mods)
  }

  func onMouseButtonPressed(window: Window, button: Mouse.Button, mods: Keyboard.Modifier) {
    navigationStack.onMouseButtonPressed(window: window, button: button, mods: mods)
  }

  func onMouseMove(window: Window, x: Double, y: Double) {
    navigationStack.onMouseMove(window: window, x: x, y: y)
  }

  func draw() {
    let screenSize = Engine.viewportSize

    // Draw semi-transparent black overlay that fades in
    if overlayOpacity > 0.0 {
      let overlayRect = Rect(origin: .zero, size: screenSize)
      overlayRect.fill(with: .black.withAlphaComponent(overlayOpacity))
    }

    // Calculate menu opacity based on overlay opacity
    // When overlay is at target (0.6), menu is at 1.0
    // When overlay fades to 0, menu also fades to 0
    let menuOpacity: Float
    if targetOverlayOpacity > 0.0 {
      menuOpacity = min(1.0, overlayOpacity / targetOverlayOpacity)
    } else {
      menuOpacity = overlayOpacity > 0.0 ? 1.0 : 0.0
    }

    // Draw vignette effect before framebuffer (captures screen content)
    // Only show when navigating to nested screens
    if animatedVignetteStrength > 0.0 && menuOpacity > 0.01 {
      // Apply vignette effect using the shader
      vignetteEffect.draw { program in
        program.setFloat("amount", value: animatedVignetteStrength)
      }
    }

    // Only draw menu content if it's visible
    if menuOpacity > 0.01 {
      // Render navigation stack and menu to framebuffer with alpha
      let menuFBO = Engine.shared.renderer.createFramebuffer(size: screenSize, scale: 1.0)

      // Render menu content to framebuffer
      Engine.shared.renderer.beginFramebuffer(menuFBO)

      navigationStack.draw()

      Engine.shared.renderer.endFramebuffer()

      // Draw framebuffer with alpha (fades menu content out)
      Engine.shared.renderer.drawFramebuffer(
        menuFBO,
        in: Rect(origin: .zero, size: screenSize),
        transform: nil,
        alpha: menuOpacity
      )

      // Clean up framebuffer
      Engine.shared.renderer.destroyFramebuffer(menuFBO)

      if !navigationStack.usesFullScreenContent {
        promptList.group = navigationStack.isAtRoot ? .menuRoot : .menu
        promptList.showCalloutBackground = false
        promptList.draw(opacity: menuOpacity)
      }
    }
  }
}
