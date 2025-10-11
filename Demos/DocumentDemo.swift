import GL
import GLFW
import GLMath

@MainActor
final class DocumentDemo: RenderLoop {
  private let documents: [Document]
  private var documentView: DocumentView!

  @ConfigValue("DocumentDemo/currentIndex")
  private var currentDocumentIndex: Int = 0

  init() {
    documents = Document.all.compactMap { $0 }
    documentView = DocumentView(document: documents[currentDocumentIndex])
  }

  func onAttach(window: GLFWWindow) {
    documentView.onAttach(window: window)
  }

  func onDetach(window: GLFWWindow) {
    documentView.onDetach(window: window)
  }

  func update(deltaTime: Float) {
    documentView.update(deltaTime: deltaTime)
  }

  func onKeyPressed(window: GLFWWindow, key: Keyboard.Key, scancode: Int32, mods: Keyboard.Modifier) {
    switch key {
    case .up: cycleDocument(forward: false)
    case .down: cycleDocument(forward: true)
    default: documentView.onKeyPressed(window: window, key: key, scancode: scancode, mods: mods)
    }
  }

  func onMouseButtonPressed(window: GLFWWindow, button: Mouse.Button, mods: Keyboard.Modifier) {
    documentView.onMouseButtonPressed(window: window, button: button, mods: mods)
  }

  func onMouseMove(window: GLFWWindow, x: Double, y: Double) {
    documentView.onMouseMove(window: window, x: x, y: y)
  }

  func onScroll(window: GLFWWindow, xOffset: Double, yOffset: Double) {
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

    UISound.select()
  }

  func draw() {
    documentView.draw()
  }
}
