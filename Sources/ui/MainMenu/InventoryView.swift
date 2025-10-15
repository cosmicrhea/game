import GL
import GLFW
import GLMath

@MainActor
final class InventoryView: RenderLoop {
  private let promptList = PromptList(.inventory)
  private var slotGrid: SlotGrid
  private let ambientBackground = GLScreenEffect("Effects/AmbientBackground")

  // Mouse tracking
  private var lastMouseX: Double = 0
  private var lastMouseY: Double = 0

  // Sample items for testing
  private var sampleItems: [Item] = []

  // Item label properties
  private var currentItemName: String = ""
  private var currentItemDescription: String = ""

  init() {
    slotGrid = SlotGrid(
      columns: 4,
      rows: 2,
      slotSize: 80.0,
      spacing: 4.0
    )
    slotGrid.onSlotAction = { [weak self] action, slotIndex in
      self?.handleSlotAction(action, slotIndex: slotIndex)
    }

    // Load sample items
    loadSampleItems()

    // Set up slot data with some sample items
    setupSlotData()

    // Center the grid on X axis, slightly above center on Y
    recenterGrid()
  }

  /// Recalculate and set the grid position to keep it centered
  private func recenterGrid() {
    let totalSize = slotGrid.totalSize
    let gridPosition = Point(
      (Float(Engine.viewportSize.width) - totalSize.width) * 0.5,  // Center X
      (Float(Engine.viewportSize.height) - totalSize.height) * 0.5 + 80  // Slightly above center Y
    )
    slotGrid.setPosition(gridPosition)
  }

  func update(deltaTime: Float) {
    recenterGrid()

    // Update slot grid (includes menu animations)
    slotGrid.update(deltaTime: deltaTime)

    // Update item label based on current selection
    updateItemLabel()
  }

  func onKeyPressed(window: GLFWWindow, key: Keyboard.Key, scancode: Int32, mods: Keyboard.Modifier) {
    // Let SlotGrid handle all input (including menu)
    if slotGrid.handleKey(key) {
      return
    }

    switch key {
    case .escape:
      // Exit inventory
      break
    default:
      break
    }
  }

  func onMouseMove(window: GLFWWindow, x: Double, y: Double) {
    lastMouseX = x
    lastMouseY = y
    // Flip Y coordinate to match screen coordinates (top-left origin)
    let mousePosition = Point(Float(x), Float(Engine.viewportSize.height) - Float(y))
    slotGrid.handleMouseMove(at: mousePosition)
  }

  func onMouseButtonPressed(window: GLFWWindow, button: Mouse.Button, mods: Keyboard.Modifier) {
    let mousePosition = Point(Float(lastMouseX), Float(Engine.viewportSize.height) - Float(lastMouseY))

    if button == .left {
      _ = slotGrid.handleMouseClick(at: mousePosition)
    }
  }

  func draw() {
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

    // Draw the slot grid (includes menu)
    slotGrid.draw()

    // Draw the prompt list
    promptList.draw()

    // Draw item label
    drawItemLabel()
  }

  // MARK: - Private Methods

  private func updateItemLabel() {
    let selectedIndex = slotGrid.selectedIndex
    if let slotData = slotGrid.getSlotData(at: selectedIndex), let item = slotData.item {
      currentItemName = item.name
      currentItemDescription = item.description ?? ""
    } else {
      currentItemName = ""
      currentItemDescription = ""
    }
  }

  private func drawItemLabel() {
    // Position the label underneath the grid
    let gridPosition = slotGrid.gridPosition
    let labelX = gridPosition.x
    let labelY = gridPosition.y - 80  // 80 pixels below the grid

    // Get the slot grid width to use as wrap width
    let gridWidth = slotGrid.totalSize.width

    // Draw item name
    let nameStyle = TextStyle(
      fontName: "Creato Display Bold",
      fontSize: 28,
      color: .white,
      strokeWidth: 2,
      strokeColor: .gray700
    )
    currentItemName.draw(at: Point(labelX, labelY), style: nameStyle, wrapWidth: gridWidth)

    // Draw item description
    let descriptionStyle = TextStyle(
      fontName: "Creato Display Medium",
      fontSize: 20,
      color: .gray300,
      strokeWidth: 1,
      strokeColor: .gray900
    )
    let descriptionY = labelY - 40
    currentItemDescription.draw(at: Point(labelX, descriptionY), style: descriptionStyle, wrapWidth: gridWidth)
  }

  private func loadSampleItems() {
    // Load weapon images from Items/Weapons
    sampleItems = [
      Item(
        id: "glock18c",
        name: "Glock 18C",
        image: Image("Items/Weapons/glock18c.png"),
        description: "Compact 9mm pistol with selective fire capability."
          //        description: "A faded photograph showing a dark tunnel."
      ),
      Item(
        id: "sigp320",
        name: "SIG Sauer P320",
        image: Image("Items/Weapons/sigp320.png"),
        description: "Modern striker-fired pistol with modular design."
      ),
      Item(
        id: "handgun_ammo",
        name: "9mm Ammunition",
        image: Image("Items/Weapons/handgun_ammo.png"),
        description: "Standard 9 millimeter rounds for handguns."
      ),
      Item(
        id: "lighter",
        name: "Lighter",
        image: Image("Items/Weapons/lighter.png"),
        description: "Simple butane lighter for lighting fires."
      ),
      Item(
        id: "utility_key",
        name: "Utility Key",
        image: Image("Items/Weapons/utility_key.png"),
        description: "A key for utility cabinets."
      ),
    ]
  }

  private func setupSlotData() {
    let totalSlots = slotGrid.columns * slotGrid.rows
    var slotData: [SlotData?] = Array(repeating: nil, count: totalSlots)

    // Place items with different quantities
    let itemsWithQuantities: [(Item, Int?)] = [
      (sampleItems[0], 15),  // Glock 18C - 15 rounds loaded
      (sampleItems[1], 17),  // SIG P320 - 17 rounds loaded
      (sampleItems[2], 24),  // 9mm Ammunition - 24 rounds
      (sampleItems[3], nil),  // Lighter - no quantity shown
      (sampleItems[4], nil),  // Utility Key - no quantity shown
    ]

    for (index, (item, quantity)) in itemsWithQuantities.enumerated() {
      if index < totalSlots {
        slotData[index] = SlotData(item: item, quantity: quantity)
      }
    }

    slotGrid.setSlotData(slotData)
  }

  private func handleSlotAction(_ action: SlotAction, slotIndex: Int) {
    switch action {
    case .use:
      // Handle item use
      if let slotData = slotGrid.getSlotData(at: slotIndex), let item = slotData.item {
        print("Using item: \(item.name)")
      }
      break
    case .inspect:
      // Handle item inspection
      if let slotData = slotGrid.getSlotData(at: slotIndex), let item = slotData.item {
        print("Inspecting item: \(item.name) - \(item.description ?? "No description")")
      }
      break
    case .combine:
      // Handle item combination
      if let slotData = slotGrid.getSlotData(at: slotIndex), let item = slotData.item {
        print("Combining item: \(item.name)")
      }
      break
    case .discard:
      // Handle item discard
      if let slotData = slotGrid.getSlotData(at: slotIndex), let item = slotData.item {
        print("Discarding item: \(item.name)")
        slotGrid.setSlotData(nil, at: slotIndex)
      }
      break
    }
  }
}
