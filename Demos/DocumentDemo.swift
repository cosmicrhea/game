import GL
import GLFW
import GLMath

@MainActor
final class DocumentDemo: RenderLoop {
  private let documents: [Document]
  private var documentViewer: DocumentViewer!

  @ConfigValue("DocumentDemo/currentIndex")
  private var currentDocumentIndex: Int = 0

  init() {
    documents = [
      .photoA,
      .photoB,
      .photoC,

      .glasportReport,
      .siezedCargo,
      .execsRecording,
      .metroNote,
      .jaritsJournal,
      .testResults,

      //      .keepersDiary,
      //      .policeRadioRecording,
    ]

    documentViewer = DocumentViewer(document: documents[currentDocumentIndex])
  }

  func onAttach(window: GLFWWindow) {
    documentViewer.onAttach(window: window)
  }

  func onDetach(window: GLFWWindow) {
    documentViewer.onDetach(window: window)
  }

  func update(deltaTime: Float) {
    documentViewer.update(deltaTime: deltaTime)
  }

  func onKeyPressed(window: GLFWWindow, key: Keyboard.Key, scancode: Int32, mods: Keyboard.Modifier) {
    switch key {
    case .semicolon: cycleDocument(forward: true)
    case .apostrophe: cycleDocument(forward: false)
    default: documentViewer.onKeyPressed(window: window, key: key, scancode: scancode, mods: mods)
    }
  }

  func onMouseButtonPressed(window: GLFWWindow, button: Mouse.Button, mods: Keyboard.Modifier) {
    documentViewer.onMouseButtonPressed(window: window, button: button, mods: mods)
  }

  func onMouseMove(window: GLFWWindow, x: Double, y: Double) {
    documentViewer.onMouseMove(window: window, x: x, y: y)
  }

  func onScroll(window: GLFWWindow, xOffset: Double, yOffset: Double) {
    documentViewer.onScroll(window: window, xOffset: xOffset, yOffset: yOffset)
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
    documentViewer = DocumentViewer(document: documents[currentDocumentIndex])

    UISound.select()
  }

  func draw() {
    documentViewer.draw()
  }
}
