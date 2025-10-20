final class DocumentDemo: RenderLoop {
  private let documents: [Document]
  private var documentView: DocumentView!

  // Fade state
  private var isFadedOut: Bool = false
  private var isFadingToBlack: Bool = false

  @ConfigValue("DocumentDemo/currentIndex")
  private var currentDocumentIndex: Int = 0

  init() {
    documents = Document.all.compactMap { $0 }
    documentView = DocumentView(document: documents[currentDocumentIndex])

    // Set up completion callback for document fade
    documentView.onDocumentFinished = { [weak self] in
      self?.handleDocumentFinished()
    }
  }

  func onAttach(window: Window) {
    documentView.onAttach(window: window)
  }

  func onDetach(window: Window) {
    documentView.onDetach(window: window)
  }

  func update(deltaTime: Float) {
    documentView.update(deltaTime: deltaTime)
  }

  func onKeyPressed(window: Window, key: Keyboard.Key, scancode: Int32, mods: Keyboard.Modifier) {
    switch key {
    case .up: cycleDocument(forward: false)
    case .down: cycleDocument(forward: true)
    case .left, .a:
      if isFadedOut && !isFadingToBlack {
        // Fade back in when faded out and not currently fading to black
        fadeBackIn()
      } else {
        documentView.onKeyPressed(window: window, key: key, scancode: scancode, mods: mods)
      }
    default:
      if !isFadedOut {
        documentView.onKeyPressed(window: window, key: key, scancode: scancode, mods: mods)
      }
    }
  }

  func onMouseButtonPressed(window: Window, button: Mouse.Button, mods: Keyboard.Modifier) {
    if isFadedOut && !isFadingToBlack {
      // Click to fade back in when faded out and not currently fading to black
      fadeBackIn()
    } else {
      documentView.onMouseButtonPressed(window: window, button: button, mods: mods)
    }
  }

  func onMouseMove(window: Window, x: Double, y: Double) {
    documentView.onMouseMove(window: window, x: x, y: y)
  }

  func onScroll(window: Window, xOffset: Double, yOffset: Double) {
    documentView.onScroll(window: window, xOffset: xOffset, yOffset: yOffset)
  }

  private func cycleDocument(forward: Bool) {
    let newIndex: Int
    if forward {
      newIndex = (currentDocumentIndex + 1) % documents.count
    } else {
      newIndex = (currentDocumentIndex - 1 + documents.count) % documents.count
    }

    guard newIndex != currentDocumentIndex else { return }

    currentDocumentIndex = newIndex
    documentView = DocumentView(document: documents[currentDocumentIndex])

    // Set up completion callback for the new document
    documentView.onDocumentFinished = { [weak self] in
      self?.handleDocumentFinished()
    }

    UISound.select()
  }

  func draw() {
    documentView.draw()
  }

  // MARK: - Fade Handling

  private func handleDocumentFinished() {
    // Fade to black when document is finished
    isFadingToBlack = true
    ScreenFadeFBO.shared.fadeToBlack(duration: 0.3) {
      self.isFadedOut = true
      self.isFadingToBlack = false
    }
  }

  private func fadeBackIn() {
    ScreenFadeFBO.shared.fadeFromBlack(duration: 0.3) {
      self.isFadedOut = false
    }
  }
}
