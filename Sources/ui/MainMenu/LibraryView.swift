import GL
import GLFW
import GLMath

final class LibraryView: RenderLoop {
  private let promptList = PromptList(.library)
  private var documentSlotGrid: DocumentSlotGrid
  private let ambientBackground = GLScreenEffect("Effects/AmbientBackground")

  // Mouse tracking
  private var lastMouseX: Double = 0
  private var lastMouseY: Double = 0

  // Document display state
  private var currentDocumentView: DocumentView? = nil
  private var isShowingDocument: Bool = false

  // Public property to check if showing a document
  public var showingDocument: Bool {
    return isShowingDocument
  }

  // Document label properties
  private var currentDocumentName: String = ""

  // All documents in order (including nil slots) - 5x3 grid (15 total)
  private let documents: [Document?] = {
    let allDocs = Document.all
    let emptySlots = Array(repeating: Document?.none, count: 15 - allDocs.count)
    return allDocs.map { $0 as Document? } + emptySlots
  }()

  // Discovered document IDs
  private var discoveredDocumentIDs: [String] = [
    "JARITS_JOURNAL",
    "METRO_NOTE",
    "PHOTO_A",
    "SIEZED_CARGO",
    "PHOTO_B",
    "EXECS_RECORDING",
    "PHOTO_C",
    "GLASPORT_REPORT",
    "PHOTO_D",
  ]

  init() {
    documentSlotGrid = DocumentSlotGrid(
      columns: 5,
      rows: 3,
      slotSize: 96.0,
      spacing: 3.0,
      selectionWraps: true
    )

    documentSlotGrid.onDocumentSelected = { [weak self] document in
      self?.handleDocumentSelection(document)
    }

    // Set up slot data with documents
    setupSlotData()

    // Center the grid on screen
    recenterGrid()
  }

  /// Recalculate and set the grid position to keep it centered
  private func recenterGrid() {
    let totalSize = documentSlotGrid.totalSize
    let gridPosition = Point(
      (Float(Engine.viewportSize.width) - totalSize.width) * 0.5,  // Center X
      (Float(Engine.viewportSize.height) - totalSize.height) * 0.5  // Center Y
    )
    documentSlotGrid.setPosition(gridPosition)
  }

  func update(deltaTime: Float) {
    if isShowingDocument {
      currentDocumentView?.update(deltaTime: deltaTime)
    } else {
      recenterGrid()
      // Update document label based on current selection
      updateDocumentLabel()
    }
  }

  func onKeyPressed(window: GLFWWindow, key: Keyboard.Key, scancode: Int32, mods: Keyboard.Modifier) {
    if isShowingDocument {
      // Handle escape to return to library view
      if key == .escape {
        hideDocument()
        return
      }

      // Forward other input to DocumentView
      currentDocumentView?.onKeyPressed(window: window, key: key, scancode: scancode, mods: mods)
      return
    }

    // Let DocumentSlotGrid handle all input
    if documentSlotGrid.handleKey(key) {
      return
    }

    switch key {
    case .escape:
      // Exit library
      break
    default:
      break
    }
  }

  func onMouseMove(window: GLFWWindow, x: Double, y: Double) {
    lastMouseX = x
    lastMouseY = y

    if isShowingDocument {
      // Forward mouse input to DocumentView if needed
      return
    }

    // Flip Y coordinate to match screen coordinates (top-left origin)
    let mousePosition = Point(Float(x), Float(Engine.viewportSize.height) - Float(y))
    documentSlotGrid.handleMouseMove(at: mousePosition)
  }

  func onMouseButtonPressed(window: GLFWWindow, button: Mouse.Button, mods: Keyboard.Modifier) {
    if isShowingDocument {
      // Forward mouse input to DocumentView
      currentDocumentView?.onMouseButtonPressed(window: window, button: button, mods: mods)
      return
    }

    let mousePosition = Point(Float(lastMouseX), Float(Engine.viewportSize.height) - Float(lastMouseY))

    if button == .left {
      _ = documentSlotGrid.handleMouseClick(at: mousePosition)
    }
  }

  func draw() {
    if isShowingDocument {
      // Draw the DocumentView
      currentDocumentView?.draw()
    } else {
      // Draw ambient background
      ambientBackground.draw { shader in
        // Set ambient background parameters
        shader.setVec3("uTintDark", value: (0.035, 0.045, 0.055))
        shader.setVec3("uTintLight", value: (0.085, 0.10, 0.11))
        shader.setFloat("uMottle", value: 0.35)
        shader.setFloat("uGrain", value: 0.08)
        shader.setFloat("uVignette", value: 0.35)
        shader.setFloat("uDust", value: 0.06)
      }

      // Draw the document slot grid
      documentSlotGrid.draw()

      // Draw the prompt list
      promptList.draw()

      // Draw document label
      drawDocumentLabel()
    }
  }

  // MARK: - Private Methods

  private func setupSlotData() {
    let totalSlots = documentSlotGrid.columns * documentSlotGrid.rows
    var slotData: [DocumentSlotData?] = Array(repeating: nil, count: totalSlots)

    // Place documents with discovery status
    for (index, document) in documents.enumerated() {
      if index < totalSlots {
        let isDiscovered = document?.id != nil && discoveredDocumentIDs.contains(document!.id!)
        slotData[index] = DocumentSlotData(document: document, isDiscovered: isDiscovered)
      }
    }

    documentSlotGrid.setSlotData(slotData)
  }

  private func handleDocumentSelection(_ document: Document?) {
    if let document = document {
      print("Selected document: \(document.displayName ?? "Unknown")")
      showDocument(document)
    } else {
      print("Selected empty slot")
    }
  }

  private func showDocument(_ document: Document) {
    // Create new DocumentView
    currentDocumentView = DocumentView(document: document)

    // Set up completion callback to return to library view
    currentDocumentView?.onDocumentFinished = { [weak self] in
      self?.hideDocument()
    }

    // Switch to document view
    isShowingDocument = true
  }

  private func hideDocument() {
    currentDocumentView = nil
    isShowingDocument = false
  }

  private func updateDocumentLabel() {
    let selectedIndex = documentSlotGrid.selectedIndex
    if let slotData = documentSlotGrid.getSlotData(at: selectedIndex), let document = slotData.document {
      currentDocumentName = document.displayName ?? "Unknown Document"
    } else {
      currentDocumentName = ""
    }
  }

  private func drawDocumentLabel() {
    // Position the label underneath the grid, centered
    let gridPosition = documentSlotGrid.gridPosition
    let gridWidth = documentSlotGrid.totalSize.width
    let labelX = gridPosition.x + gridWidth * 0.5  // Center horizontally
    let labelY = gridPosition.y - 80  // 80 pixels below the grid

    // Draw document name centered
    let nameStyle = TextStyle(
      fontName: "CreatoDisplay-Bold",
      fontSize: 28,
      color: .white,
      strokeWidth: 2,
      strokeColor: .gray700
    )
    currentDocumentName.draw(at: Point(labelX, labelY), style: nameStyle, wrapWidth: gridWidth, anchor: .center)
  }
}
