/// A grid of slots with configurable spacing and layout
@MainActor
public final class ItemSlotGrid {
  // MARK: - Configuration
  public var columns: Int
  public var rows: Int
  public var slotSize: Float
  public var spacing: Float
  public var cornerRadius: Float
  public var radialGradientStrength: Float
  public var selectionWraps: Bool

  // MARK: - State
  public private(set) var gridPosition: Point = Point(0, 0)
  public private(set) var selectedIndex: Int
  public private(set) var hoveredIndex: Int? = nil

  // MARK: - Equipment State
  /// Slot index of the currently equipped weapon, if any
  /// When inventory is set, reads/writes from inventory.equippedWeaponIndex
  /// Otherwise uses local equippedWeaponIndexStorage
  public var equippedWeaponIndex: Int? {
    get {
      if let inventory = inventory {
        return inventory.equippedWeaponIndex
      }
      return equippedWeaponIndexStorage
    }
    set {
      if let inventory = inventory {
        inventory.equippedWeaponIndex = newValue
      } else {
        equippedWeaponIndexStorage = newValue
      }
    }
  }
  /// Local storage for equipped weapon index when inventory is nil
  private var equippedWeaponIndexStorage: Int? = nil

  // MARK: - Moving Support
  /// Enable interactive moving/swapping of slot contents
  public var allowsMoving: Bool = false
  /// True while the grid is in moving mode (e.g. while Alt is held)
  public private(set) var isMovingModeActive: Bool = false
  /// When in moving mode, the source slot currently selected for moving
  private var movingSourceIndex: Int? = nil

  // MARK: - Combine Support
  /// True while the grid is in combine mode
  public private(set) var isCombineModeActive: Bool = false
  /// When in combine mode, the source slot currently selected for combining
  private var _combineSourceIndex: Int? = nil
  /// Get the combine source index (public accessor)
  public var combineSourceIndex: Int? {
    return _combineSourceIndex
  }
  /// Animation time for dimming opacity (0.0 = fully dimmed, 1.0 = fully visible)
  private var combineDimmingProgress: Float = 1.0
  private let combineDimmingSpeed: Float = 1.0 / 0.15  // Speed of dimming animation (0.15 seconds to complete)

  // MARK: - Highlighting Support
  /// Slot index to highlight (for take out/retrieve modes, etc.)
  /// This provides visual highlighting similar to move mode but without activating move mode
  public var highlightedSlotIndex: Int? = nil

  // MARK: - Placement Support
  /// Item being placed (when in placement mode)
  public var placementItem: Item? = nil
  /// Quantity of item being placed
  public var placementQuantity: Int = 1
  /// Blink animation time for placement mode
  private var placementBlinkTime: Float = 0.0
  private let placementBlinkSpeed: Float = 2.0  // Blinks per second

  /// True while the grid is in placement mode
  public var isPlacementModeActive: Bool {
    return placementItem != nil
  }

  // MARK: - Rendering
  private var slotEffect = GLScreenEffect("Common/Slot")
  private let quantityAnchor: AnchorPoint = .bottomRight

  // MARK: - Colors
  public var slotColor = Color.slotBackground
  public var borderColor = Color.slotBorder
  public var borderHighlight = Color.slotBorderHighlight
  public var borderShadow = Color.slotBorderShadow

  // MARK: - Slot Properties
  public var borderThickness: Float = 8.0
  public var noiseScale: Float = 0.02
  public var noiseStrength: Float = 0.3

  // MARK: - Tinting
  public var tint: Color? = nil

  // MARK: - Selection Colors
  public var selectedSlotColor = Color.slotSelected
  public var hoveredSlotColor = Color.slotHovered

  // MARK: - Context Menu
  public var slotMenu: SlotMenu
  public var onSlotAction: ((SlotAction, Int) -> Void)?
  /// Custom actions provider - if set, this overrides the default actionsForSlot logic
  public var customActionsProvider: ((Int) -> [SlotAction])? = nil

  // MARK: - Selection Callback (alternative to menu)
  public var onSlotSelected: ((Int) -> Void)?
  public var showMenuOnSelection: Bool = true
  /// When false, selection/hover highlights are visually suppressed
  public var isFocused: Bool = true

  // MARK: - Placement Callbacks
  public var onPlacementConfirmed: ((Int, Item, Int) -> Void)?  // slotIndex, item, quantity
  public var onPlacementCancelled: (() -> Void)?

  // MARK: - Slot Data
  /// Inventory instance - when set, uses inventory.slots instead of slotData
  public var inventory: Inventory? = nil
  /// Direct slot data array (used when inventory is nil)
  public var slotData: [ItemSlotData?] = []

  /// Get the effective slot data array (from inventory if set, otherwise slotData)
  private var effectiveSlotData: [ItemSlotData?] {
    if let inventory = inventory {
      return inventory.slots
    }
    return slotData
  }

  public init(config: GridConfiguration) {
    self.columns = config.columns
    self.rows = config.rows
    self.slotSize = config.cellSize
    self.spacing = config.spacing
    self.cornerRadius = config.cornerRadius
    self.radialGradientStrength = config.radialGradientStrength
    self.selectionWraps = config.selectionWraps
    // Start selection in bottom-left corner (now index 0)
    self.selectedIndex = 0

    self.slotMenu = SlotMenu()
    self.slotMenu.offset = Point(2, 0)  // 2px right offset
    self.slotMenu.onAction = { [weak self] action, slotIndex in
      self?.onSlotAction?(action, slotIndex)
    }
  }

  public init(
    columns: Int,
    rows: Int,
    slotSize: Float = 96.0,
    spacing: Float = 3.0,
    cornerRadius: Float = 5.0,
    radialGradientStrength: Float = 0.6,
    selectionWraps: Bool = false
  ) {
    self.columns = columns
    self.rows = rows
    self.slotSize = slotSize
    self.spacing = spacing
    self.cornerRadius = cornerRadius
    self.radialGradientStrength = radialGradientStrength
    self.selectionWraps = selectionWraps
    // Start selection in bottom-left corner (now index 0)
    self.selectedIndex = 0

    self.slotMenu = SlotMenu()
    self.slotMenu.offset = Point(3, 0)
    self.slotMenu.onAction = { [weak self] action, slotIndex in
      self?.onSlotAction?(action, slotIndex)
    }
  }

  // MARK: - Public Methods

  /// Set the grid position (top-left corner)
  public func setPosition(_ position: Point) {
    gridPosition = position
  }

  /// Set the slot data array (should match the grid size)
  /// Note: If inventory is set, this will update inventory.slots instead
  public func setSlotData(_ data: [ItemSlotData?]) {
    if let inventory = inventory {
      inventory.slots = data
    } else {
      slotData = data
    }
  }

  /// Set the currently equipped weapon by slot index (or none).
  public func setEquippedWeaponIndex(_ slotIndex: Int?) {
    if let inventory = inventory {
      inventory.equippedWeaponIndex = slotIndex
    } else {
      equippedWeaponIndexStorage = slotIndex
    }
  }

  /// Get the currently equipped weapon item, if any
  public func getEquippedWeapon() -> Item? {
    guard let index = equippedWeaponIndex,
      let slotData = getSlotData(at: index),
      let item = slotData.item,
      item.kind.isWeapon
    else { return nil }
    return item
  }

  /// Get equipped weapon slot data
  public func getEquippedWeaponSlotData() -> ItemSlotData? {
    guard let index = equippedWeaponIndex else { return nil }
    return getSlotData(at: index)
  }

  /// Enable/disable moving mode (no-op if `allowsMoving` is false).
  /// Disabling clears any pending moving source and hides the menu.
  public func setMovingModeActive(_ active: Bool) {
    guard allowsMoving else {
      // Ensure we fully reset when moving is not allowed
      isMovingModeActive = false
      movingSourceIndex = nil
      return
    }
    if isMovingModeActive == active { return }
    isMovingModeActive = active
    // Never show the context menu while moving
    slotMenu.hide()
    if active {
      // When entering move mode, the currently selected item becomes the source
      if let data = getSlotData(at: selectedIndex), data.item != nil {
        movingSourceIndex = selectedIndex
        logger.trace("SlotGrid: Entered move mode with item \(data.item!.name) at slot \(selectedIndex)")
      } else {
        logger.trace("SlotGrid: Entered move mode but no item in selected slot \(selectedIndex)")
      }
    } else {
      movingSourceIndex = nil
    }
  }

  /// Cancel any pending move selection without leaving move mode
  public func cancelPendingMove() {
    movingSourceIndex = nil
  }

  /// Enable/disable combine mode
  /// Disabling clears any pending combine source and hides the menu.
  public func setCombineModeActive(_ active: Bool) {
    if isCombineModeActive == active { return }
    isCombineModeActive = active
    // Never show the context menu while combining
    slotMenu.hide()
    if active {
      // Start dimming animation from fully visible when entering combine mode
      combineDimmingProgress = 1.0
      // When entering combine mode, the currently selected item becomes the source
      if let data = getSlotData(at: selectedIndex), let item = data.item {
        _combineSourceIndex = selectedIndex
        logger.trace("SlotGrid: Entered combine mode with item \(item.name) at slot \(selectedIndex)")
      } else {
        logger.trace("SlotGrid: Entered combine mode but no item in selected slot \(selectedIndex)")
      }
    } else {
      _combineSourceIndex = nil
      // Don't reset progress here - let it animate back to 1.0 naturally
    }
  }

  /// Cancel any pending combine selection without leaving combine mode
  public func cancelPendingCombine() {
    _combineSourceIndex = nil
  }

  /// Check if an item at the given slot index can combine with the combine source item
  private func canCombineSlot(at index: Int) -> Bool {
    guard let sourceIndex = _combineSourceIndex,
      let sourceData = getSlotData(at: sourceIndex),
      let sourceItem = sourceData.item,
      let targetData = getSlotData(at: index),
      let targetItem = targetData.item
    else { return false }
    return sourceItem.canCombine(with: targetItem) != nil
  }

  /// Set placement mode with an item to place
  public func setPlacementMode(item: Item, quantity: Int = 1) {
    placementItem = item
    placementQuantity = quantity
    placementBlinkTime = 0.0
    // Never show menu while placing
    slotMenu.hide()
  }

  /// Clear placement mode
  public func clearPlacementMode() {
    placementItem = nil
    placementQuantity = 1
    placementBlinkTime = 0.0
  }

  /// Get slot data at a specific index
  public func getSlotData(at index: Int) -> ItemSlotData? {
    let data = effectiveSlotData
    guard index >= 0 && index < data.count else { return nil }
    return data[index]
  }

  /// Set slot data at a specific index
  public func setSlotData(_ data: ItemSlotData?, at index: Int) {
    if let inventory = inventory {
      guard index >= 0 && index < inventory.slots.count else { return }
      inventory.slots[index] = data
    } else {
      guard index >= 0 && index < slotData.count else { return }
      slotData[index] = data
    }
  }

  /// Get the total size of the grid
  public var totalSize: Size {
    let totalWidth = Float(columns) * slotSize + Float(columns - 1) * spacing
    let totalHeight = Float(rows) * slotSize + Float(rows - 1) * spacing
    return Size(totalWidth, totalHeight)
  }

  /// Get the position of a specific slot by index
  public func slotPosition(at index: Int) -> Point {
    let col = index % columns
    let row = index / columns

    let x = gridPosition.x + Float(col) * (slotSize + spacing)
    // Flip Y coordinate so bottom row is row 0
    let y = gridPosition.y + Float(rows - 1 - row) * (slotSize + spacing)

    return Point(x, y)
  }

  /// Get the slot index at a given screen position
  public func slotIndex(at position: Point) -> Int? {
    let relativeX = position.x - gridPosition.x
    let relativeY = position.y - gridPosition.y

    // Check if position is within grid bounds
    if relativeX < 0 || relativeY < 0 {
      return nil
    }

    let col = Int(relativeX / (slotSize + spacing))
    let visualRow = Int(relativeY / (slotSize + spacing))

    // Convert visual row (bottom=0) to logical row (top=0)
    let row = rows - 1 - visualRow

    // Check if within valid grid
    if col < 0 || col >= columns || row < 0 || row >= rows {
      return nil
    }

    // Check if position is within the actual slot (not in spacing)
    let slotStartX = Float(col) * (slotSize + spacing)
    let slotStartY = Float(visualRow) * (slotSize + spacing)
    let slotEndX = slotStartX + slotSize
    let slotEndY = slotStartY + slotSize

    if relativeX < slotStartX || relativeX > slotEndX || relativeY < slotStartY || relativeY > slotEndY {
      return nil
    }

    return row * columns + col
  }

  /// Update hover state based on mouse position
  public func updateHover(at mousePosition: Point) {
    hoveredIndex = slotIndex(at: mousePosition)
  }

  /// Clear hover state
  public func clearHover() {
    hoveredIndex = nil
  }

  /// Set the selected slot index
  public func setSelected(_ index: Int) {
    if index >= 0 && index < columns * rows {
      selectedIndex = index
    }
  }

  /// Move selection in a direction
  /// Returns true if the selection actually moved, false if it hit an edge and wrapping is disabled
  @discardableResult
  public func moveSelection(direction: Direction) -> Bool {
    let currentCol = selectedIndex % columns
    let currentRow = selectedIndex / columns

    var newCol = currentCol
    var newRow = currentRow

    switch direction {
    case .up:
      if currentRow < rows - 1 {
        newRow = currentRow + 1
      } else if selectionWraps {
        newRow = 0  // Wrap to bottom row
      } else {
        return false  // Hit top edge, no wrapping
      }
    case .right:
      if currentCol < columns - 1 {
        newCol = currentCol + 1
      } else if selectionWraps {
        newCol = 0  // Wrap to leftmost column
      } else {
        return false  // Hit right edge, no wrapping
      }
    case .down:
      if currentRow > 0 {
        newRow = currentRow - 1
      } else if selectionWraps {
        newRow = rows - 1  // Wrap to top row
      } else {
        return false  // Hit bottom edge, no wrapping
      }
    case .left:
      if currentCol > 0 {
        newCol = currentCol - 1
      } else if selectionWraps {
        newCol = columns - 1  // Wrap to rightmost column
      } else {
        return false  // Hit left edge, no wrapping
      }
    }

    let newIndex = newRow * columns + newCol
    if newIndex != selectedIndex {
      selectedIndex = newIndex
      UISound.navigate()
      return true
    }
    return false
  }

  // MARK: - Input Handling

  /// Handle keyboard input for grid navigation and menu
  public func handleKey(_ key: Keyboard.Key) -> Bool {
    // While in placement mode, handle navigation and placement confirmation
    if isPlacementModeActive {
      switch key {
      case .w, .up:
        return moveSelection(direction: .down)
      case .s, .down:
        return moveSelection(direction: .up)
      case .a, .left:
        return moveSelection(direction: .left)
      case .d, .right:
        return moveSelection(direction: .right)
      case .f, .space, .enter, .numpadEnter:
        // Try to place item at selected slot
        if let slotData = getSlotData(at: selectedIndex), slotData.isEmpty {
          // Slot is empty, place the item
          if let item = placementItem {
            UISound.select()
            onPlacementConfirmed?(selectedIndex, item, placementQuantity)
          }
          return true
        } else {
          // Slot is occupied, play error sound
          UISound.error()
          return true
        }
      case .escape:
        // Cancel placement
        UISound.cancel()
        onPlacementCancelled?()
        return true
      default:
        return false
      }
    }
    // While in combine mode, handle navigation and combine confirmation
    if isCombineModeActive {
      switch key {
      case .w, .up:
        return moveSelection(direction: .down)
      case .s, .down:
        return moveSelection(direction: .up)
      case .a, .left:
        return moveSelection(direction: .left)
      case .d, .right:
        return moveSelection(direction: .right)
      case .f, .space, .enter, .numpadEnter:
        // Confirm combine with current selection
        if let sourceIndex = _combineSourceIndex {
          logger.trace("SlotGrid: Confirming combine from \(sourceIndex) to \(selectedIndex)")
          if performCombine(from: sourceIndex, to: selectedIndex) {
            setCombineModeActive(false)  // Exit combine mode after successful combine
            return true
          } else {
            // Failed to combine (incompatible items)
            UISound.error()
            return true
          }
        }
        return false
      case .escape:
        // Cancel combine and exit combine mode
        cancelPendingCombine()
        setCombineModeActive(false)
        UISound.cancel()
        return true
      default:
        return false
      }
    }
    // While in moving mode, handle navigation and move confirmation
    if isMovingModeActive {
      switch key {
      case .w, .up:
        return moveSelection(direction: .down)
      case .s, .down:
        return moveSelection(direction: .up)
      case .a, .left:
        return moveSelection(direction: .left)
      case .d, .right:
        return moveSelection(direction: .right)
      case .f, .space, .enter, .numpadEnter:
        // Confirm move to current selection
        if let sourceIndex = movingSourceIndex {
          logger.trace("SlotGrid: Confirming move from \(sourceIndex) to \(selectedIndex)")
          performMove(from: sourceIndex, to: selectedIndex)
          cancelPendingMove()
          setMovingModeActive(false)  // Exit move mode after successful move
          UISound.select()
          return true
        }
        return false
      case .escape:
        // Cancel move and exit move mode
        cancelPendingMove()
        setMovingModeActive(false)
        return true
      default:
        return false
      }
    }
    // Handle menu navigation if menu is visible
    if slotMenu.isVisible {
      if slotMenu.handleKey(key) {
        return true
      }
    }

    switch key {
    case .w, .up:
      return moveSelection(direction: .down)  // W/Up moves down
    case .s, .down:
      return moveSelection(direction: .up)  // S/Down moves up
    case .a, .left:
      return moveSelection(direction: .left)
    case .d, .right:
      return moveSelection(direction: .right)
    case .f, .space, .enter, .numpadEnter:
      if showMenuOnSelection {
        // Show menu for selected slot
        showMenuForSelectedSlot()
      } else {
        // Call selection callback
        onSlotSelected?(selectedIndex)
      }
      return true
    case .escape:
      if slotMenu.isVisible {
        slotMenu.hide()
        return true
      }
    default:
      return false
    }
    return false
  }

  /// Handle mouse movement for hover effects and menu
  public func handleMouseMove(at position: Point) {
    if slotMenu.isVisible {
      slotMenu.updateMouse(at: position)
    } else {
      updateHover(at: position)
    }
  }

  /// Handle mouse click for selection and menu
  public func handleMouseClick(at position: Point) -> Bool {
    // Combine mode takes precedence over moving mode
    if isCombineModeActive {
      logger.trace("SlotGrid: In combine mode, clicked at position \(position)")
      guard let clickedIndex = slotIndex(at: position) else {
        logger.trace("SlotGrid: No slot at clicked position")
        return false
      }
      logger.trace("SlotGrid: Clicked slot index: \(clickedIndex)")

      if let sourceIndex = _combineSourceIndex {
        logger.trace("SlotGrid: Combining from source \(sourceIndex) to target \(clickedIndex)")
        // Perform combine to the target index
        if performCombine(from: sourceIndex, to: clickedIndex) {
          setSelected(clickedIndex)
          setCombineModeActive(false)  // Exit combine mode after successful combine
          return true
        } else {
          // Failed to combine (incompatible items)
          UISound.error()
          return true
        }
      } else {
        // Pick up from clicked slot only if it contains an item
        if let data = getSlotData(at: clickedIndex), data.item != nil {
          logger.trace("SlotGrid: Picking up item \(data.item!.name) from slot \(clickedIndex) for combining")
          _combineSourceIndex = clickedIndex
          setSelected(clickedIndex)
          UISound.select()
          return true
        }
        logger.trace("SlotGrid: No item in slot \(clickedIndex) to pick up for combining")
        return false
      }
    }
    // Moving mode takes precedence over context menu behavior
    if isMovingModeActive {
      logger.trace("SlotGrid: In moving mode, clicked at position \(position)")
      guard let clickedIndex = slotIndex(at: position) else {
        logger.trace("SlotGrid: No slot at clicked position")
        return false
      }
      logger.trace("SlotGrid: Clicked slot index: \(clickedIndex)")

      if let sourceIndex = movingSourceIndex {
        logger.trace("SlotGrid: Moving from source \(sourceIndex) to target \(clickedIndex)")
        // Perform move/swap to the target index
        performMove(from: sourceIndex, to: clickedIndex)
        setSelected(clickedIndex)
        cancelPendingMove()
        setMovingModeActive(false)  // Exit move mode after successful move
        UISound.select()
        return true
      } else {
        // Pick up from clicked slot only if it contains an item
        if let data = getSlotData(at: clickedIndex), data.item != nil {
          logger.trace("SlotGrid: Picking up item \(data.item!.name) from slot \(clickedIndex)")
          movingSourceIndex = clickedIndex
          setSelected(clickedIndex)
          UISound.select()
          return true
        }
        logger.trace("SlotGrid: No item in slot \(clickedIndex) to pick up")
        return false
      }
    } else if slotMenu.isVisible {
      // Handle menu click
      if slotMenu.handleClick(at: position) {
        // Menu item was clicked, menu is now hidden
        return true
      } else {
        // Clicked outside menu, hide it
        slotMenu.hide()
        return false
      }
    } else {
      // Select slot and either show menu or call callback
      if let slotIndex = slotIndex(at: position) {
        setSelected(slotIndex)
        if showMenuOnSelection {
          showMenuForSlot(slotIndex, at: position)
        } else {
          onSlotSelected?(slotIndex)
        }
        return true
      }
    }
    return false
  }

  // MARK: - Menu Management

  /// Show menu for the currently selected slot
  private func showMenuForSelectedSlot() {
    let slotPosition = slotPosition(at: selectedIndex)
    let slotCenter = Point(
      slotPosition.x + slotSize * 0.5,
      slotPosition.y + slotSize * 0.5
    )
    showMenuForSlot(selectedIndex, at: slotCenter, openedWithKeyboard: true)
  }

  /// Show menu for a specific slot
  private func showMenuForSlot(_ slotIndex: Int, at position: Point, openedWithKeyboard: Bool = false) {
    // Get available actions (custom provider or default)
    let availableActions = customActionsProvider?(slotIndex) ?? actionsForSlot(at: slotIndex)

    // If no actions available (e.g., empty slot with no custom provider), don't show menu
    guard !availableActions.isEmpty else {
      UISound.error()
      return
    }

    // Check if slot is empty - if so, play error sound and don't show menu (unless custom provider handles it)
    if customActionsProvider == nil {
      guard let slotData = getSlotData(at: slotIndex), !slotData.isEmpty else {
        UISound.error()
        return
      }
    }

    let slotPosition = slotPosition(at: slotIndex)
    let slotCenter = Point(
      slotPosition.x + slotSize * 0.5,
      slotPosition.y + slotSize * 0.5
    )
    slotMenu.showForSlot(
      at: slotCenter,
      slotIndex: slotIndex,
      slotPosition: slotPosition,
      availableActions: availableActions,
      openedWithKeyboard: openedWithKeyboard,
      slotSize: Size(slotSize, slotSize)
    )
    UISound.select()
  }

  /// Compute available actions for a given slot based on its item kind
  private func actionsForSlot(at index: Int) -> [SlotAction] {
    let data = effectiveSlotData
    guard index >= 0 && index < data.count, let slotData = data[index], let item = slotData.item else {
      return []
    }
    let exchangeAction: [SlotAction] = TWO_PLAYER_MODE ? [.exchange] : []
    switch item.kind {
    case .weapon:
      if equippedWeaponIndex == index {
        return [.unequip, .inspect] + exchangeAction
      } else {
        return [.equip, .inspect] + exchangeAction
      }
    case .recovery:
      return [.use, .inspect] + exchangeAction + [.discard]
    case .key:
      return [.inspect, .combine] + exchangeAction
    case .ammo:
      return [.inspect] + exchangeAction + [.discard]
    }
  }

  /// Update menu animations
  public func update(deltaTime: Float) {
    slotMenu.update(deltaTime: deltaTime)
    // Update placement blink animation
    if isPlacementModeActive {
      placementBlinkTime += deltaTime * placementBlinkSpeed
    }
    // Update combine dimming animation
    if isCombineModeActive {
      // Fade in dimming: animate from 1.0 (fully visible) to 0.0 (fully dimmed)
      combineDimmingProgress = max(0.0, combineDimmingProgress - deltaTime * combineDimmingSpeed)
    } else {
      // Fade out dimming: animate back to fully visible when not in combine mode
      // Always animate when not in combine mode (will stop at 1.0 due to min())
      combineDimmingProgress = min(1.0, combineDimmingProgress + deltaTime * combineDimmingSpeed)
    }
  }

  // MARK: - Rendering

  /// Draw the slot grid and menu
  public func draw() {
    for i in 0..<(columns * rows) {
      let slotPosition = slotPosition(at: i)
      let centerPosition = Point(
        slotPosition.x + slotSize * 0.5,
        slotPosition.y + slotSize * 0.5
      )

      // Determine slot color based on state
      var currentSlotColor = slotColor
      var slotDimmed = false

      // In combine mode (or fading out), dim slots that are not combinable
      if isCombineModeActive || combineDimmingProgress < 1.0 {
        if isCombineModeActive, let sourceIndex = _combineSourceIndex, i == sourceIndex {
          // Source slot gets amber tint (similar to move mode) - only when actively in combine mode
          let amberTintStrength: Float = 0.6
          currentSlotColor = Color(
            slotColor.red + amberTintStrength * 0.3,
            slotColor.green + amberTintStrength * 0.24,
            slotColor.blue + amberTintStrength * 0.15,
            slotColor.alpha
          )
        } else if isCombineModeActive && i == selectedIndex {
          // Selected slot in combine mode gets rose/red tint - only when actively in combine mode
          let roseTintStrength: Float = 0.6
          currentSlotColor = Color(
            slotColor.red + roseTintStrength * 0.4,
            slotColor.green + roseTintStrength * 0.15,
            slotColor.blue + roseTintStrength * 0.2,
            slotColor.alpha
          )
        } else {
          // Dim slots that are not combinable (or all slots during fade-out)
          let shouldDim: Bool
          if isCombineModeActive {
            // In active combine mode, check if slot can combine
            let slotData = getSlotData(at: i)
            if let data = slotData, let _ = data.item {
              shouldDim = !canCombineSlot(at: i)
            } else {
              shouldDim = true  // Empty slots are always dimmed
            }
          } else {
            // During fade-out, dim all slots that aren't source or selected
            // (This maintains the dimmed state during fade-out)
            shouldDim = true
          }

          if shouldDim {
            slotDimmed = true
            // Interpolate between full brightness and dimmed based on animation progress
            // Dimmed values: 0.6 multiplier, 0.7 alpha (less intense than before)
            let dimmedMultiplier: Float = 0.6
            let dimmedAlpha: Float = 0.7
            let brightness = 1.0 - (1.0 - combineDimmingProgress) * (1.0 - dimmedMultiplier)
            let alpha = 1.0 - (1.0 - combineDimmingProgress) * (1.0 - dimmedAlpha)
            currentSlotColor = Color(
              slotColor.red * brightness,
              slotColor.green * brightness,
              slotColor.blue * brightness,
              slotColor.alpha * alpha
            )
          }
        }
      } else if isMovingModeActive, let sourceIndex = movingSourceIndex, i == sourceIndex {
        // Apply amber tint to the picked-up source slot
        let amberTintStrength: Float = 0.6
        currentSlotColor = Color(
          slotColor.red + amberTintStrength * 0.3,
          slotColor.green + amberTintStrength * 0.24,
          slotColor.blue + amberTintStrength * 0.15,
          slotColor.alpha
        )
      } else if let highlightedIndex = highlightedSlotIndex, i == highlightedIndex {
        // Apply amber tint to highlighted slot (for take out/retrieve modes)
        let amberTintStrength: Float = 0.6
        currentSlotColor = Color(
          slotColor.red + amberTintStrength * 0.3,
          slotColor.green + amberTintStrength * 0.24,
          slotColor.blue + amberTintStrength * 0.15,
          slotColor.alpha
        )
      } else if isFocused && i == selectedIndex {
        // Use active color when menu is open, selected color otherwise
        currentSlotColor = slotMenu.isVisible ? Color.slotActive : selectedSlotColor
      } else if isFocused && i == hoveredIndex {
        currentSlotColor = hoveredSlotColor
      }

      // Mark equipped slot (weapon) for border tinting (unless it's the moving source)
      let isEquippedSlot: Bool = {
        guard let equippedIndex = equippedWeaponIndex,
          equippedIndex == i,
          let slotData = getSlotData(at: i),
          let item = slotData.item,
          item.kind.isWeapon
        else { return false }
        return true
      }()
      let isSource = isMovingModeActive && ((movingSourceIndex ?? -1) == i)
      let isCombineSource = isCombineModeActive && ((_combineSourceIndex ?? -1) == i)
      let isHighlighted = highlightedSlotIndex == i
      let applyEquippedBorderTint = isEquippedSlot && !isSource && !isCombineSource && !isHighlighted

      // Apply tint if specified
      if let tint = tint {
        currentSlotColor = Color(
          currentSlotColor.red * tint.red,
          currentSlotColor.green * tint.green,
          currentSlotColor.blue * tint.blue,
          currentSlotColor.alpha
        )
      }

      // Draw the slot
      slotEffect.draw { shader in
        // Drive subtle pulse only for selected (when focused), moving source, or combine source (equipped border does not pulse)
        let pulses: Float = {
          let isSelected = isFocused && (i == selectedIndex)
          let isMoving = isSource
          let isCombining = isCombineSource
          let isHighlighted = highlightedSlotIndex == i
          return (isSelected || isMoving || isCombining || isHighlighted) ? 1.0 : 0.0
        }()
        shader.setFloat("uPulse", value: pulses)
        if applyEquippedBorderTint {
          let accentColor = Color.accent
          shader.setVec3("uBorderTint", value: (accentColor.red, accentColor.green, accentColor.blue))
          shader.setFloat("uBorderTintStrength", value: 0.33)
          shader.setFloat("uEquippedStroke", value: 1.0)
          shader.setVec3("uEquippedStrokeColor", value: (accentColor.red, accentColor.green, accentColor.blue))
          shader.setFloat("uEquippedStrokeWidth", value: 5.0)
          shader.setFloat("uEquippedGlow", value: 1.0)
          shader.setVec3("uEquippedGlowColor", value: (accentColor.red, accentColor.green, accentColor.blue))
          shader.setFloat("uEquippedGlowStrength", value: 0.15)
        } else {
          shader.setVec3("uBorderTint", value: (0.0, 0.0, 0.0))
          shader.setFloat("uBorderTintStrength", value: 0.0)
          shader.setFloat("uEquippedStroke", value: 0.0)
          shader.setVec3("uEquippedStrokeColor", value: (0.0, 0.0, 0.0))
          shader.setFloat("uEquippedStrokeWidth", value: 0.0)
          shader.setFloat("uEquippedGlow", value: 0.0)
          shader.setVec3("uEquippedGlowColor", value: (0.0, 0.0, 0.0))
          shader.setFloat("uEquippedGlowStrength", value: 0.0)
        }
        shader.setVec2("uPanelSize", value: (slotSize, slotSize))
        shader.setVec2("uPanelCenter", value: (centerPosition.x, centerPosition.y))
        shader.setFloat("uBorderThickness", value: borderThickness)
        shader.setFloat("uCornerRadius", value: cornerRadius)
        shader.setFloat("uNoiseScale", value: noiseScale)
        shader.setFloat("uNoiseStrength", value: noiseStrength)
        // Show radial gradient on slots with items, or on blank slots that are selected/hovered
        let data = effectiveSlotData
        let hasItem = (i < data.count) && (data[i]?.item != nil)
        let isSelectedOrHovered = (isFocused && i == selectedIndex) || (isFocused && i == hoveredIndex)
        shader.setFloat(
          "uRadialGradientStrength", value: (hasItem || isSelectedOrHovered) ? radialGradientStrength : 0.0)

        // Set colors
        shader.setVec3(
          "uPanelColor", value: (x: currentSlotColor.red, y: currentSlotColor.green, z: currentSlotColor.blue))
        shader.setFloat("uPanelAlpha", value: currentSlotColor.alpha)
        shader.setVec3("uBorderColor", value: (x: borderColor.red, y: borderColor.green, z: borderColor.blue))
        shader.setVec3(
          "uBorderHighlight", value: (x: borderHighlight.red, y: borderHighlight.green, z: borderHighlight.blue))
        shader.setVec3("uBorderShadow", value: (x: borderShadow.red, y: borderShadow.green, z: borderShadow.blue))
      }

      // Draw item image if slot has data
      let data = effectiveSlotData
      if i < data.count, let slotData = data[i], let item = slotData.item, let image = item.image {
        let imageSize = min(slotSize * 0.8, min(image.naturalSize.width, image.naturalSize.height))
        let imageRect = Rect(
          x: slotPosition.x + (slotSize - imageSize) * 0.5,
          y: slotPosition.y + (slotSize - imageSize) * 0.5,
          width: imageSize,
          height: imageSize
        )
        // Dim image if slot is dimmed (non-combinable in combine mode)
        if slotDimmed {
          // Animate image dimming to match slot dimming
          let dimmedAlpha: Float = 0.6
          let imageAlpha = 1.0 - (1.0 - combineDimmingProgress) * (1.0 - dimmedAlpha)
          image.draw(in: imageRect, tint: Color.white.withAlphaComponent(imageAlpha))
        } else {
          image.draw(in: imageRect)
        }

        // Draw quantity number with configurable bottom anchor if should show quantity
        if slotData.shouldShowQuantity {
          let quantityText = "\(slotData.quantity!)"

          let fadeWidth: Float = 8 + quantityText.size(with: .slotQuantity).width * 2
          let fadeOrigin: Point = {
            switch quantityAnchor {
            case .bottomRight:
              return Point(slotPosition.x + slotSize - fadeWidth - 3, slotPosition.y + 5)
            default:
              return Point(slotPosition.x + 3, slotPosition.y + 5)
            }
          }()
          let fadeRect = Rect(origin: fadeOrigin, size: Size(fadeWidth, 19))
          let gradient: Gradient = {
            switch quantityAnchor {
            case .bottomRight:
              return Gradient(startingColor: .clear, endingColor: .black.withAlphaComponent(0.8))
            default:
              return Gradient(startingColor: .black.withAlphaComponent(0.8), endingColor: .clear)
            }
          }()
          GraphicsContext.current?.drawLinearGradient(gradient, in: fadeRect, angle: 0)

          // Position with proper padding based on anchor
          let quantityX: Float = {
            switch quantityAnchor {
            case .bottomRight:
              return slotPosition.x + slotSize - 9
            default:
              return slotPosition.x + 9
            }
          }()
          let quantityY = slotPosition.y + 6
          let textAnchor: AnchorPoint = (quantityAnchor == .bottomRight) ? .bottomRight : .bottomLeft
          quantityText.draw(at: Point(quantityX, quantityY), style: .slotQuantity, anchor: textAnchor)
        }
      }
    }

    // Draw the context menu
    slotMenu.draw()

    // Draw placement item on top of all slots (if in placement mode)
    if isPlacementModeActive {
      drawPlacementItem()
    }
  }

  // MARK: - Combine helpers

  /// Perform a combine operation from source to target slot
  /// Returns true if the combine was successful, false otherwise
  private func performCombine(from sourceIndex: Int, to targetIndex: Int) -> Bool {
    guard sourceIndex != targetIndex else {
      logger.trace("SlotGrid: Cannot combine item with itself")
      return false
    }

    let sourceData = getSlotData(at: sourceIndex)
    let targetData = getSlotData(at: targetIndex)

    guard let sourceSlotData = sourceData,
      let sourceItem = sourceSlotData.item,
      let targetSlotData = targetData,
      let targetItem = targetSlotData.item
    else {
      logger.trace("SlotGrid: Cannot combine - one or both slots are empty")
      return false
    }

    // Check if items can combine
    guard let resultItem = sourceItem.canCombine(with: targetItem) else {
      logger.trace("SlotGrid: Items \(sourceItem.name) and \(targetItem.name) cannot combine")
      return false
    }

    logger.trace("SlotGrid: Combining \(sourceItem.name) with \(targetItem.name) -> \(resultItem.name)")

    // Place result item in target slot, remove source item
    // For now, we'll use the target slot's quantity if it has one, otherwise nil
    let resultQuantity: Int? = {
      // If result is a weapon with capacity, use that
      if case .weapon(_, _, let capacity, _) = resultItem.kind, let capacity = capacity {
        return capacity
      }
      // Otherwise, preserve target quantity if it exists and result supports quantities
      return targetSlotData.quantity
    }()

    if let inventory = inventory {
      inventory.slots[targetIndex] = ItemSlotData(item: resultItem, quantity: resultQuantity)
      inventory.slots[sourceIndex] = nil
    } else {
      slotData[targetIndex] = ItemSlotData(item: resultItem, quantity: resultQuantity)
      slotData[sourceIndex] = nil
    }

    // Update equipped weapon index if source was equipped
    if equippedWeaponIndex == sourceIndex {
      // If result is a weapon, equip it at target slot, otherwise unequip
      if resultItem.kind.isWeapon {
        equippedWeaponIndex = targetIndex
      } else {
        equippedWeaponIndex = nil
      }
    } else if equippedWeaponIndex == targetIndex {
      // If result is a weapon, keep it equipped, otherwise unequip
      if !resultItem.kind.isWeapon {
        equippedWeaponIndex = nil
      }
    }

    // Play success sound
    UISound.combine()
    return true
  }

  // MARK: - Moving helpers

  private func performMove(from sourceIndex: Int, to targetIndex: Int) {
    guard sourceIndex != targetIndex else {
      logger.trace("SlotGrid: Cannot move to same slot")
      return
    }

    if let inventory = inventory {
      guard sourceIndex >= 0 && sourceIndex < inventory.slots.count else {
        logger.warning("SlotGrid: Invalid source index \(sourceIndex)")
        return
      }
      guard targetIndex >= 0 && targetIndex < inventory.slots.count else {
        logger.warning("SlotGrid: Invalid target index \(targetIndex)")
        return
      }

      let sourceData = inventory.slots[sourceIndex]
      let targetData = inventory.slots[targetIndex]

      logger.trace("SlotGrid: Moving from \(sourceIndex) to \(targetIndex)")
      logger.trace("SlotGrid: Source has item: \(sourceData?.item?.name ?? "nil")")
      logger.trace("SlotGrid: Target has item: \(targetData?.item?.name ?? "nil")")

      // Swap even if one side is nil (acts as move into empty)
      inventory.slots[targetIndex] = sourceData
      inventory.slots[sourceIndex] = targetData

      logger.trace("SlotGrid: After move - Source now has: \(inventory.slots[sourceIndex]?.item?.name ?? "nil")")
      logger.trace("SlotGrid: After move - Target now has: \(inventory.slots[targetIndex]?.item?.name ?? "nil")")

      // Update equipped weapon index if it was moved
      if equippedWeaponIndex == sourceIndex {
        equippedWeaponIndex = targetIndex
      } else if equippedWeaponIndex == targetIndex {
        equippedWeaponIndex = sourceIndex
      }
    } else {
      guard sourceIndex >= 0 && sourceIndex < slotData.count else {
        logger.warning("SlotGrid: Invalid source index \(sourceIndex)")
        return
      }
      guard targetIndex >= 0 && targetIndex < slotData.count else {
        logger.warning("SlotGrid: Invalid target index \(targetIndex)")
        return
      }

      let sourceData = slotData[sourceIndex]
      let targetData = slotData[targetIndex]

      logger.trace("SlotGrid: Moving from \(sourceIndex) to \(targetIndex)")
      logger.trace("SlotGrid: Source has item: \(sourceData?.item?.name ?? "nil")")
      logger.trace("SlotGrid: Target has item: \(targetData?.item?.name ?? "nil")")

      // Swap even if one side is nil (acts as move into empty)
      slotData[targetIndex] = sourceData
      slotData[sourceIndex] = targetData

      logger.trace("SlotGrid: After move - Source now has: \(slotData[sourceIndex]?.item?.name ?? "nil")")
      logger.trace("SlotGrid: After move - Target now has: \(slotData[targetIndex]?.item?.name ?? "nil")")

      // Update equipped weapon index if it was moved
      if equippedWeaponIndex == sourceIndex {
        equippedWeaponIndex = targetIndex
      } else if equippedWeaponIndex == targetIndex {
        equippedWeaponIndex = sourceIndex
      }
    }
  }

  /// Draw the blinking placement item at the selected slot
  private func drawPlacementItem() {
    guard let item = placementItem else { return }
    let selectedIndex = selectedIndex
    let slotPosition = slotPosition(at: selectedIndex)

    // Calculate blink alpha (oscillates between 0.3 and 1.0)
    let blinkAlpha = 0.3 + (sin(placementBlinkTime * Float.pi * 2.0) * 0.5 + 0.5) * 0.7

    // Draw item image - try to load if nil
    var image = item.image
    if image == nil {
      // Try to load image from alternative path if default path failed
      image = Image("Items/\(item.id).png")
    }

    if let image = image {
      let imageSize = min(slotSize * 0.8, min(image.naturalSize.width, image.naturalSize.height))
      let imageRect = Rect(
        x: slotPosition.x + (slotSize - imageSize) * 0.5,
        y: slotPosition.y + (slotSize - imageSize) * 0.5,
        width: imageSize,
        height: imageSize
      )
      image.draw(in: imageRect, tint: Color.white.withAlphaComponent(blinkAlpha))
    } else {
      // Draw a placeholder rectangle if image is still nil
      let placeholderSize = slotSize * 0.6
      let placeholderRect = Rect(
        x: slotPosition.x + (slotSize - placeholderSize) * 0.5,
        y: slotPosition.y + (slotSize - placeholderSize) * 0.5,
        width: placeholderSize,
        height: placeholderSize
      )
      placeholderRect.fill(with: Color.white.withAlphaComponent(blinkAlpha * 0.5))
    }

    // Draw quantity if applicable
    if placementQuantity > 1 {
      let quantityText = "\(placementQuantity)"
      let fadeWidth: Float = 8 + quantityText.size(with: .slotQuantity).width * 2
      let fadeOrigin = Point(slotPosition.x + slotSize - fadeWidth - 3, slotPosition.y + 5)
      let fadeRect = Rect(origin: fadeOrigin, size: Size(fadeWidth, 19))
      let gradient = Gradient(startingColor: .clear, endingColor: .black.withAlphaComponent(0.8 * blinkAlpha))
      GraphicsContext.current?.drawLinearGradient(gradient, in: fadeRect, angle: 0)

      let quantityX = slotPosition.x + slotSize - 9
      let quantityY = slotPosition.y + 6
      let fadedStyle = TextStyle.slotQuantity.withColor(
        TextStyle.slotQuantity.color.withAlphaComponent(blinkAlpha)
      )
      quantityText.draw(at: Point(quantityX, quantityY), style: fadedStyle, anchor: .bottomRight)
    }
  }
}

// MARK: - Direction Enum
public enum Direction {
  case up, down, left, right
}
