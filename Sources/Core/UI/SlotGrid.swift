/// A grid of slots with configurable spacing and layout
@MainActor
public final class SlotGrid {
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
  /// Item id of the currently equipped weapon, if any
  public private(set) var equippedWeaponId: String? = nil

  // MARK: - Moving Support
  /// Enable interactive moving/swapping of slot contents
  public var allowsMoving: Bool = false
  /// True while the grid is in moving mode (e.g. while Alt is held)
  public private(set) var isMovingModeActive: Bool = false
  /// When in moving mode, the source slot currently selected for moving
  private var movingSourceIndex: Int? = nil

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
  public var slotData: [SlotData?] = []

  /// Get the effective slot data array (from inventory if set, otherwise slotData)
  private var effectiveSlotData: [SlotData?] {
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
  public func setSlotData(_ data: [SlotData?]) {
    if let inventory = inventory {
      inventory.slots = data
    } else {
      slotData = data
    }
  }

  /// Set the currently equipped weapon by item id (or none).
  public func setEquippedWeaponId(_ itemId: String?) {
    equippedWeaponId = itemId
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
        print("SlotGrid: Entered move mode with item \(data.item!.name) at slot \(selectedIndex)")
      } else {
        print("SlotGrid: Entered move mode but no item in selected slot \(selectedIndex)")
      }
    } else {
      movingSourceIndex = nil
    }
  }

  /// Cancel any pending move selection without leaving move mode
  public func cancelPendingMove() {
    movingSourceIndex = nil
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
  public func getSlotData(at index: Int) -> SlotData? {
    let data = effectiveSlotData
    guard index >= 0 && index < data.count else { return nil }
    return data[index]
  }

  /// Set slot data at a specific index
  public func setSlotData(_ data: SlotData?, at index: Int) {
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
          print("SlotGrid: Confirming move from \(sourceIndex) to \(selectedIndex)")
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
    // Moving mode takes precedence over context menu behavior
    if isMovingModeActive {
      print("SlotGrid: In moving mode, clicked at position \(position)")
      guard let clickedIndex = slotIndex(at: position) else {
        print("SlotGrid: No slot at clicked position")
        return false
      }
      print("SlotGrid: Clicked slot index: \(clickedIndex)")

      if let sourceIndex = movingSourceIndex {
        print("SlotGrid: Moving from source \(sourceIndex) to target \(clickedIndex)")
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
          print("SlotGrid: Picking up item \(data.item!.name) from slot \(clickedIndex)")
          movingSourceIndex = clickedIndex
          setSelected(clickedIndex)
          UISound.select()
          return true
        }
        print("SlotGrid: No item in slot \(clickedIndex) to pick up")
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
    // Check if slot is empty - if so, play error sound and don't show menu
    guard let slotData = getSlotData(at: slotIndex), !slotData.isEmpty else {
      UISound.error()
      return
    }

    let slotPosition = slotPosition(at: slotIndex)
    let slotCenter = Point(
      slotPosition.x + slotSize * 0.5,
      slotPosition.y + slotSize * 0.5
    )
    let availableActions = actionsForSlot(at: slotIndex)
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
    switch item.kind {
    case .weapon:
      if equippedWeaponId == item.id {
        return [.unequip, .inspect, .exchange]
      } else {
        return [.equip, .inspect, .exchange]
      }
    case .recovery:
      return [.use, .inspect, .exchange, .discard]
    case .key:
      return [.inspect, .combine, .exchange]
    case .ammo:
      return [.inspect, .exchange, .discard]
    }
  }

  /// Update menu animations
  public func update(deltaTime: Float) {
    slotMenu.update(deltaTime: deltaTime)
    // Update placement blink animation
    if isPlacementModeActive {
      placementBlinkTime += deltaTime * placementBlinkSpeed
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
      if isMovingModeActive, let sourceIndex = movingSourceIndex, i == sourceIndex {
        // Apply amber tint to the picked-up source slot
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
        let data = effectiveSlotData
        guard let equippedId = equippedWeaponId,
          i < data.count,
          let slotData = data[i],
          let item = slotData.item,
          item.kind == .weapon
        else { return false }
        return item.id == equippedId
      }()
      let isSource = isMovingModeActive && ((movingSourceIndex ?? -1) == i)
      let applyEquippedBorderTint = isEquippedSlot && !isSource

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
        // Drive subtle pulse only for selected (when focused) or moving source (equipped border does not pulse)
        let pulses: Float = {
          let isSelected = isFocused && (i == selectedIndex)
          let isMoving = isSource
          return (isSelected || isMoving) ? 1.0 : 0.0
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
        shader.setFloat("uRadialGradientStrength", value: radialGradientStrength)

        // Set colors
        shader.setVec3(
          "uPanelColor", value: (x: currentSlotColor.red, y: currentSlotColor.green, z: currentSlotColor.blue))
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
        image.draw(in: imageRect)

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

  // MARK: - Moving helpers

  private func performMove(from sourceIndex: Int, to targetIndex: Int) {
    guard sourceIndex != targetIndex else {
      print("SlotGrid: Cannot move to same slot")
      return
    }

    if let inventory = inventory {
      guard sourceIndex >= 0 && sourceIndex < inventory.slots.count else {
        print("SlotGrid: Invalid source index \(sourceIndex)")
        return
      }
      guard targetIndex >= 0 && targetIndex < inventory.slots.count else {
        print("SlotGrid: Invalid target index \(targetIndex)")
        return
      }

      let sourceData = inventory.slots[sourceIndex]
      let targetData = inventory.slots[targetIndex]

      print("SlotGrid: Moving from \(sourceIndex) to \(targetIndex)")
      print("SlotGrid: Source has item: \(sourceData?.item?.name ?? "nil")")
      print("SlotGrid: Target has item: \(targetData?.item?.name ?? "nil")")

      // Swap even if one side is nil (acts as move into empty)
      inventory.slots[targetIndex] = sourceData
      inventory.slots[sourceIndex] = targetData

      print("SlotGrid: After move - Source now has: \(inventory.slots[sourceIndex]?.item?.name ?? "nil")")
      print("SlotGrid: After move - Target now has: \(inventory.slots[targetIndex]?.item?.name ?? "nil")")
    } else {
      guard sourceIndex >= 0 && sourceIndex < slotData.count else {
        print("SlotGrid: Invalid source index \(sourceIndex)")
        return
      }
      guard targetIndex >= 0 && targetIndex < slotData.count else {
        print("SlotGrid: Invalid target index \(targetIndex)")
        return
      }

      let sourceData = slotData[sourceIndex]
      let targetData = slotData[targetIndex]

      print("SlotGrid: Moving from \(sourceIndex) to \(targetIndex)")
      print("SlotGrid: Source has item: \(sourceData?.item?.name ?? "nil")")
      print("SlotGrid: Target has item: \(targetData?.item?.name ?? "nil")")

      // Swap even if one side is nil (acts as move into empty)
      slotData[targetIndex] = sourceData
      slotData[sourceIndex] = targetData

      print("SlotGrid: After move - Source now has: \(slotData[sourceIndex]?.item?.name ?? "nil")")
      print("SlotGrid: After move - Target now has: \(slotData[targetIndex]?.item?.name ?? "nil")")
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
