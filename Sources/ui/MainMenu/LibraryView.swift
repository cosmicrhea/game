final class LibraryView: RenderLoop {
  private let promptList = PromptList(.library)
  private var slotGrid: DocumentSlotGrid
  private let ambientBackground = GLScreenEffect("Effects/AmbientBackground")
  private let itemDescriptionView = ItemDescriptionView()

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
    slotGrid = DocumentSlotGrid(
      columns: 4,
      rows: 4,
      slotSize: 80.0,
      spacing: 3.0,
      selectionWraps: true
    )

    slotGrid.onDocumentSelected = { [weak self] document in
      self?.handleDocumentSelection(document)
    }

    // Set up slot data with documents
    setupSlotData()

    // Center the grid on screen
    recenterGrid()
  }

  /// Recalculate and set the grid position based on layout preference
  private func recenterGrid() {
    let totalSize = slotGrid.totalSize
    let isCentered = Config.current.centeredLayout
    let x: Float = {
      if isCentered {
        return (Float(Engine.viewportSize.width) - totalSize.width) * 0.5
      } else {
        let rightMargin: Float = 152
        return Float(Engine.viewportSize.width) - totalSize.width - rightMargin
      }
    }()
    let y: Float = (Float(Engine.viewportSize.height) - totalSize.height) * 0.5 + 64
    let gridPosition = Point(x, y)
    slotGrid.setPosition(gridPosition)
  }

  func update(deltaTime: Float) {
    if isShowingDocument {
      currentDocumentView?.update(deltaTime: deltaTime)
    } else {
      recenterGrid()
      // Update document label based on current selection
      updateDocumentLabel()
      // Keep the shared description view in sync
      itemDescriptionView.title = currentDocumentName
      itemDescriptionView.descriptionText = ""
    }
  }

  func onKeyPressed(window: Window, key: Keyboard.Key, scancode: Int32, mods: Keyboard.Modifier) {
    if isShowingDocument {
      // Handle escape to return to library view
      if key == .escape {
        UISound.cancel()
        hideDocument()
        return
      }

      // Forward other input to DocumentView
      currentDocumentView?.onKeyPressed(window: window, key: key, scancode: scancode, mods: mods)
      return
    }

    // Let DocumentSlotGrid handle all input
    if slotGrid.handleKey(key) {
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

  func onMouseMove(window: Window, x: Double, y: Double) {
    lastMouseX = x
    lastMouseY = y

    if isShowingDocument {
      // Forward mouse input to DocumentView if needed
      return
    }

    // Flip Y coordinate to match screen coordinates (top-left origin)
    let mousePosition = Point(Float(x), Float(Engine.viewportSize.height) - Float(y))
    slotGrid.handleMouseMove(at: mousePosition)
  }

  func onMouseButtonPressed(window: Window, button: Mouse.Button, mods: Keyboard.Modifier) {
    if isShowingDocument {
      // Forward mouse input to DocumentView
      currentDocumentView?.onMouseButtonPressed(window: window, button: button, mods: mods)
      return
    }

    let mousePosition = Point(Float(lastMouseX), Float(Engine.viewportSize.height) - Float(lastMouseY))

    if button == .left {
      _ = slotGrid.handleMouseClick(at: mousePosition)
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
      slotGrid.draw()

      // Draw the prompt list
      promptList.draw()

      // Draw document label via shared ItemDescriptionView
      itemDescriptionView.draw()
    }
  }

  // MARK: - Private Methods

  private func setupSlotData() {
    let totalSlots = slotGrid.columns * slotGrid.rows
    var slotData: [DocumentSlotData?] = Array(repeating: nil, count: totalSlots)

    // Place documents with discovery status
    for (index, document) in documents.enumerated() {
      if index < totalSlots {
        let isDiscovered = document?.id != nil && discoveredDocumentIDs.contains(document!.id!)
        slotData[index] = DocumentSlotData(document: document, isDiscovered: isDiscovered)
      }
    }

    slotGrid.setSlotData(slotData)
  }

  private func handleDocumentSelection(_ document: Document?) {
    if let document = document {
      print("Selected document: \(document.displayName ?? "Unknown")")
      showDocument(document)
    } else {
      print("Selected empty slot")
      UISound.error()
    }
  }

  private func showDocument(_ document: Document) {
    // Create new DocumentView
    UISound.select()
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
    let selectedIndex = slotGrid.selectedIndex
    if let slotData = slotGrid.getSlotData(at: selectedIndex), let document = slotData.document {
      currentDocumentName = document.displayName ?? "Unknown Document"
    } else {
      currentDocumentName = ""
    }
  }

  // No separate drawDocumentLabel: handled by ItemDescriptionView
}
