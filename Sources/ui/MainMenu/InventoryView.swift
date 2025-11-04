final class InventoryView: RenderLoop {
  private let promptList = PromptList(.inventory)
  private var slotGrid: SlotGrid
  private let ambientBackground = GLScreenEffect("Effects/AmbientBackground")
  private let healthCallout = Callout(style: .healthDisplay)
  internal let healthDisplay = HealthDisplay()

  // Mouse tracking
  private var lastMouseX: Double = 0
  private var lastMouseY: Double = 0

  // Item description component
  private let itemDescriptionView = ItemDescriptionView()

  // Item inspection state
  private var currentItemView: ItemView? = nil
  private var isShowingItem: Bool = false

  // Public property to check if showing an item
  public var showingItem: Bool {
    return isShowingItem
  }

  // Public property to check if slot menu is visible
  public var isSlotMenuVisible: Bool {
    return slotGrid.slotMenu.isVisible
  }

  init() {
    slotGrid = SlotGrid(
      columns: 4,
      rows: 4,
      slotSize: 80.0,
      spacing: 3.0
    )
    // Enable interactive moving/swapping support for inventory
    slotGrid.allowsMoving = true
    slotGrid.onSlotAction = { [weak self] action, slotIndex in
      self?.handleSlotAction(action, slotIndex: slotIndex)
    }

    // Set up slot data with some sample items
    setupSlotData()

    // Center the grid on X axis, slightly above center on Y
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
        // Align to the right side with a comfortable margin
        let rightMargin: Float = 288
        return Float(Engine.viewportSize.width) - totalSize.width - rightMargin
      }
    }()
    let y: Float = (Float(Engine.viewportSize.height) - totalSize.height) * 0.5 + 128
    let gridPosition = Point(x, y)
    slotGrid.setPosition(gridPosition)
  }

  func update(window: Window, deltaTime: Float) {
    if isShowingItem {
      // Forward update to ItemView
      currentItemView?.update(window: window, deltaTime: deltaTime)
    } else {
      recenterGrid()

      // Update slot grid (includes menu animations)
      slotGrid.update(deltaTime: deltaTime)

      // Update item description based on current selection
      updateItemDescription()
    }

    //    // Update slot grid
    //    slotGrid.update(deltaTime: deltaTime)
  }

  func onKeyPressed(window: Window, key: Keyboard.Key, scancode: Int32, mods: Keyboard.Modifier) {
    if isShowingItem {
      // Handle escape to return to inventory view
      if key == .escape {
        UISound.cancel()
        hideItem()
        return
      }

      // Forward other input to ItemView
      currentItemView?.onKeyPressed(window: window, key: key, scancode: scancode, mods: mods)
      return
    }

    // Toggle move mode on Alt press
    if key == .leftAlt || key == .rightAlt {
      UISound.select()
      slotGrid.setMovingModeActive(!slotGrid.isMovingModeActive)
      return
    }

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

  func onMouseMove(window: Window, x: Double, y: Double) {
    lastMouseX = x
    lastMouseY = y

    if isShowingItem {
      // Forward mouse input to ItemView
      currentItemView?.onMouseMove(window: window, x: x, y: y)
      return
    }

    // Flip Y coordinate to match screen coordinates (top-left origin)
    let mousePosition = Point(Float(x), Float(Engine.viewportSize.height) - Float(y))
    slotGrid.handleMouseMove(at: mousePosition)
  }

  func onMouseButton(window: Window, button: Mouse.Button, state: ButtonState, mods: Keyboard.Modifier) {
    if isShowingItem {
      // Forward mouse input to ItemView
      currentItemView?.onMouseButton(window: window, button: button, state: state, mods: mods)
      return
    }
  }

  func onMouseButtonPressed(window: Window, button: Mouse.Button, mods: Keyboard.Modifier) {
    if isShowingItem {
      // Forward mouse input to ItemView
      currentItemView?.onMouseButtonPressed(window: window, button: button, mods: mods)
      return
    }

    let mousePosition = Point(Float(lastMouseX), Float(Engine.viewportSize.height) - Float(lastMouseY))

    if button == .left {
      _ = slotGrid.handleMouseClick(at: mousePosition)
    } else if button == .right {
      // Right click cancels move mode
      if slotGrid.isMovingModeActive {
        slotGrid.cancelPendingMove()
        slotGrid.setMovingModeActive(false)
      }
    }
  }

  func onScroll(window: Window, xOffset: Double, yOffset: Double) {
    if isShowingItem {
      // Forward scroll input to ItemView
      currentItemView?.onScroll(window: window, xOffset: xOffset, yOffset: yOffset)
      return
    }
  }

  func draw() {
    if isShowingItem {
      // Draw the ItemView
      currentItemView?.draw()
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

      // Draw the slot grid (includes menu)
      slotGrid.draw()

      // Draw the health callout
      healthCallout.draw()

      // Draw the shader-based health display above callout
      healthDisplay.draw()

      // Draw item description
      itemDescriptionView.draw()

      // Draw the prompt list
      promptList.group = slotGrid.isMovingModeActive ? .confirmCancel : .inventory
      promptList.draw()
    }
  }

  // MARK: - Private Methods

  private func updateItemDescription() {
    let selectedIndex = slotGrid.selectedIndex
    if let slotData = slotGrid.getSlotData(at: selectedIndex), let item = slotData.item {
      itemDescriptionView.title = item.name
      itemDescriptionView.descriptionText = item.description ?? ""
    } else {
      itemDescriptionView.title = ""
      itemDescriptionView.descriptionText = ""
    }
  }

  private func setupSlotData() {
    let totalSlots = slotGrid.columns * slotGrid.rows
    var slotData: [SlotData?] = Array(repeating: nil, count: totalSlots)

    // Place items with different quantities
    let itemsWithQuantities: [(Item, Int?)] = [
      //      (.knife, nil),
      //      (.glock17, 15),
      //      (.handgunAmmo, 69),
      //       (.sigp320, 0),
      //      (.morphine, nil),
      //       (.glock18, 17),
      //      (.metroKey, nil),
      // (.utilityKey, nil),

      (.morphine, nil),
      (.knife, nil),
      (.glock17, 15),
      (.glock18, 17),
      (.sigp320, 0),
      (.fnx45, 15),
      (.handgunAmmo, 69),
      (.utilityKey, nil),
      (.metroKey, nil),
      (.cryoGloves, nil),
      (.lighter, nil),
      (.beretta92, 17),
      (.remington870, 8),
      (.spas12, 10),
      (.mp5sd, 30),

      // (.morphine, nil),
      // (.knife, nil),
      // (.glock17, 15),
      // (.glock18, 17),
      // (.sigp320, 0),
      // //      (.beretta92, 17),
      // (.fnx45, 15),
      // (.handgunAmmo, 69),
      // (.utilityKey, nil),
      // (.metroKey, nil),
      // //      (.tagKey, nil),
      // (.cryoGloves, nil),
      // (.lighter, nil),
      // //      (.remington870, 8),
      // //      (.spas12, 10),
      // //      (.mp5sd, 30),
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
    case .equip:
      if let slotData = slotGrid.getSlotData(at: slotIndex), let item = slotData.item {
        print("Equipping item: \(item.name)")
        // Equip this weapon (single-weapon policy)
        slotGrid.setEquippedWeaponId(item.id)
      }
      break
    case .unequip:
      if let slotData = slotGrid.getSlotData(at: slotIndex), let item = slotData.item {
        print("Unequipping item: \(item.name)")
        // Only clear if this is currently equipped
        if slotGrid.equippedWeaponId == item.id { slotGrid.setEquippedWeaponId(nil) }
      }
      break
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
        showItem(item)
      }
      break
    case .combine:
      // Handle item combination
      if let slotData = slotGrid.getSlotData(at: slotIndex), let item = slotData.item {
        print("Combining item: \(item.name)")
      }
      break
    case .exchange:
      break
    case .discard:
      // Handle item discard
      if let slotData = slotGrid.getSlotData(at: slotIndex), let item = slotData.item {
        print("Discarding item: \(item.name)")
        if slotGrid.equippedWeaponId == item.id { slotGrid.setEquippedWeaponId(nil) }
        slotGrid.setSlotData(nil, at: slotIndex)
      }
      break
    }
  }

  private func showItem(_ item: Item) {
    // Create new ItemView
    currentItemView = ItemView(item: item)

    // Set up completion callback to return to inventory view
    currentItemView?.onItemFinished = { [weak self] in
      self?.hideItem()
    }

    // Switch to item view
    isShowingItem = true
  }

  private func hideItem() {
    currentItemView = nil
    isShowingItem = false
  }
}
