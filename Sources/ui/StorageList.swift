/// A scrolling list view for storage inventory items.
@MainActor
final class StorageList {
  // MARK: - Configuration
  private let scrollView: ScrollView
  internal let rowHeight: Float = 60.0  // Adjusted for proper sizing
  // private let iconSize: Float = 48.0
  private let iconSize: Float = 56.0
  private let iconPadding: Float = 0.0
  private let textPadding: Float = 12.0
  private let rightSideTextPadding: Float = 28.0
  private let rowPaddingX: Float = 0.0
  internal let rowPaddingY: Float = 2.0

  // Spacing for wide slots (proportional to icon size)
  private let wideSlotSpacing: Float = 3.0
  private var wideSlotWidth: Float {
    // Wide slot = 2 * iconSize + spacing (proportional to list icon size)
    return 2.0 * iconSize + wideSlotSpacing
  }

  // MARK: - Slot Rendering
  private var slotEffect = GLScreenEffect("Common/Slot")
  private let slotCornerRadius: Float = 5.0
  private let slotBorderThickness: Float = 8.0
  private let slotNoiseScale: Float = 0.02
  private let slotNoiseStrength: Float = 0.3
  private let slotRadialGradientStrength: Float = 0.6

  // Row slot (outer slot around entire row)
  private let rowSlotCornerRadius: Float = 7.0
  private let rowSlotBorderThickness: Float = 6.0

  // MARK: - Colors
  private let slotColor = Color.slotBackground
  private let borderColor = Color.slotBorder
  private let borderHighlight = Color.slotBorderHighlight
  private let borderShadow = Color.slotBorderShadow
  private let selectedSlotColor = Color.slotSelected

  // MARK: - State
  private var inventory: Inventory?
  private var selectedIndex: Int = 0
  private var isFocused: Bool = false
  private var sortOrder: ItemSortOrder = .key

  // Display list: sorted items + one empty row at end
  // Maps display index to (inventoryIndex, slotData)
  private var displayList: [(inventoryIndex: Int, slotData: ItemSlotData?)] = []

  // Slot menu for list items
  private let slotMenu = SlotMenu()

  // MARK: - Configuration
  /// If false, don't draw the inner slot behind the item image
  public var decoratesImage: Bool = true
  /// If true, show quantity on top of image with callout. If false, show quantity label on right side without callout.
  public var showsQuantitiesOnImages: Bool = true

  // MARK: - Callbacks
  var onSelectionChanged: ((Int) -> Void)?
  var onItemSelected: ((Int) -> Void)?
  var onSortOrderChanged: ((ItemSortOrder) -> Void)?
  var onSlotAction: ((SlotAction, Int) -> Void)?  // displayIndex, action

  // MARK: - Init
  init(frame: Rect) {
    scrollView = ScrollView(frame: frame, contentSize: .zero)
    scrollView.allowsVerticalScroll = true
    scrollView.allowsHorizontalScroll = false
    scrollView.backgroundColor = nil  // Transparent background
    scrollView.showsScrollbar = true
    scrollView.scrollbarPosition = .outside

    scrollView.onDrawContent = { [weak self] origin in
      self?.drawContent(origin: origin)
    }

    slotMenu.onAction = { [weak self] action, slotIndex in
      self?.onSlotAction?(action, slotIndex)
    }
  }

  // MARK: - Public Methods

  func setInventory(_ inventory: Inventory) {
    self.inventory = inventory
    rebuildDisplayList()
    updateContentSize()
    // ScrollView now handles starting at top automatically
  }

  func setSortOrder(_ order: ItemSortOrder) {
    guard sortOrder != order else { return }
    sortOrder = order
    rebuildDisplayList()
    updateContentSize()
    // Try to maintain selection on same item
    if let currentSlotData = getSlotData(at: selectedIndex) {
      // Find the same item in new display list
      if let newIndex = displayList.firstIndex(where: { $0.slotData?.item?.id == currentSlotData.item?.id }) {
        selectedIndex = newIndex
      } else {
        selectedIndex = min(selectedIndex, displayList.count - 1)
      }
    }
    scrollToSelectedItem()
    onSortOrderChanged?(sortOrder)
  }

  var currentSortOrder: ItemSortOrder {
    return sortOrder
  }

  func setFrame(_ frame: Rect) {
    scrollView.frame = frame
    updateContentSize()
  }

  func setFocused(_ focused: Bool) {
    isFocused = focused
  }

  func setSelectedIndex(_ index: Int) {
    let maxIndex = max(0, displayList.count - 1)
    let newIndex = max(0, min(index, maxIndex))

    if newIndex != selectedIndex {
      selectedIndex = newIndex
      onSelectionChanged?(selectedIndex)
      scrollToSelectedItem()
    }
  }

  var currentSelectedIndex: Int {
    return selectedIndex
  }

  /// Get the actual inventory index for a display index
  func getInventoryIndex(at displayIndex: Int) -> Int? {
    guard displayIndex >= 0, displayIndex < displayList.count else { return nil }
    let inventoryIndex = displayList[displayIndex].inventoryIndex
    return inventoryIndex >= 0 ? inventoryIndex : nil
  }

  func getSlotData(at displayIndex: Int) -> ItemSlotData? {
    guard displayIndex >= 0, displayIndex < displayList.count else { return nil }
    return displayList[displayIndex].slotData
  }

  func handleKey(_ key: Keyboard.Key) -> Bool {
    // Handle menu navigation if menu is visible (modal input lock)
    if slotMenu.isVisible {
      if slotMenu.handleKey(key) {
        return true
      }
      // If menu didn't handle it, check for escape to close menu
      if key == .escape {
        slotMenu.hide()
        return true
      }
      // Menu is visible but didn't handle key - don't process list navigation
      return false
    }

    guard !displayList.isEmpty else { return false }
    let itemCount = displayList.count

    switch key {
    case .down, .s:
      // Move down (increase index) - wrap to top if at bottom
      let newIndex = selectedIndex < itemCount - 1 ? selectedIndex + 1 : 0
      setSelectedIndex(newIndex)
      UISound.scroll()
      return true
    case .up, .w:
      // Move up (decrease index) - wrap to bottom if at top
      let newIndex = selectedIndex > 0 ? selectedIndex - 1 : itemCount - 1
      setSelectedIndex(newIndex)
      UISound.scroll()
      return true
    case .f, .space, .enter, .numpadEnter:
      // Show menu for selected item, or handle empty row
      if let slotData = getSlotData(at: selectedIndex), slotData.item != nil {
        showMenuForSelectedItem()
      } else {
        // Empty row - trigger special action
        onItemSelected?(selectedIndex)
        UISound.select()
      }
      return true
    case .escape:
      // Escape does nothing when menu is not visible (handled above)
      return false
    default:
      break
    }
    return false
  }

  func handleMouseMove(at position: Point) -> Bool {
    // Only handle scroll view dragging - don't change selection on hover
    scrollView.handleMouseMove(at: position)
    return false
  }

  func handleMouseClick(at position: Point) -> Bool {
    guard scrollView.contains(position) else { return false }

    // Convert mouse position to content coordinates
    let contentY = position.y - scrollView.frame.origin.y + scrollView.contentOffset.y

    // Y-axis is flipped: content is drawn from bottom to top
    // Calculate which row was clicked (from bottom)
    let contentHeight = Float(displayList.count) * rowHeight
    let yFromBottom = contentHeight - contentY
    let rowIndex = Int(yFromBottom / rowHeight)

    guard rowIndex >= 0,
      rowIndex < displayList.count
    else { return false }

    if rowIndex == selectedIndex {
      // Same item clicked - show menu if item, or trigger empty row action
      if let slotData = getSlotData(at: selectedIndex), slotData.item != nil {
        showMenuForSelectedItem()
      } else {
        onItemSelected?(selectedIndex)
        UISound.select()
      }
    } else {
      setSelectedIndex(rowIndex)
    }
    return true
  }

  private func showMenuForSelectedItem() {
    guard let slotData = getSlotData(at: selectedIndex), slotData.item != nil else { return }

    // Get row position for menu
    // ScrollView uses origin.y = frame.origin.y - contentOffset.y for drawing
    // In Y-flipped coordinates: contentOffset.y = 0 means bottom, maxOffsetY means top
    // We draw from bottom to top: index 0 at bottom, highest index at top
    let contentHeight = Float(displayList.count) * rowHeight
    let rowY = contentHeight - Float(selectedIndex) * rowHeight - rowHeight * 0.5
    // Calculate actual screen position: origin.y - contentOffset.y + rowY
    let actualY = scrollView.frame.origin.y - scrollView.contentOffset.y + rowY
    let menuPosition = Point(
      scrollView.frame.origin.x + scrollView.frame.size.width * 0.5,
      actualY
    )

    let slotPosition = Point(scrollView.frame.origin.x, actualY)

    // Show menu with Retrieve and Inspect actions
    slotMenu.showWithCustomActions(
      at: menuPosition,
      slotIndex: selectedIndex,
      slotPosition: slotPosition,
      actions: [
        ("Retrieve", .retrieve),
        ("Inspect", .inspect),
      ]
    )
    UISound.select()
  }

  func update(deltaTime: Float) {
    scrollView.update(deltaTime: deltaTime)
    slotMenu.update(deltaTime: deltaTime)
  }

  func draw() {
    scrollView.draw()
    slotMenu.draw()
  }

  var isSlotMenuVisible: Bool {
    return slotMenu.isVisible
  }

  func hideSlotMenu() {
    slotMenu.hide()
  }

  func handleScroll(xOffset: Double, yOffset: Double, mouse: Point) {
    scrollView.handleScroll(xOffset: xOffset, yOffset: yOffset, mouse: mouse)
  }

  func handleMouseDown(at position: Point) -> Bool {
    return scrollView.handleMouseDown(at: position)
  }

  func handleMouseUp() {
    scrollView.handleMouseUp()
  }

  // MARK: - Private Methods

  func rebuildDisplayList() {
    guard let inventory = inventory else {
      displayList = []
      return
    }

    // Collect all non-empty slots with their indices
    var itemsWithIndices: [(index: Int, slotData: ItemSlotData)] = []
    for (index, slotData) in inventory.slots.enumerated() {
      if let slotData = slotData, slotData.item != nil {
        itemsWithIndices.append((index: index, slotData: slotData))
      }
    }

    // Sort by sort order priority, then by name
    itemsWithIndices.sort { first, second in
      guard let firstItem = first.slotData.item, let secondItem = second.slotData.item else { return false }

      let firstPriority = sortOrder.sortPriority(for: firstItem.kind)
      let secondPriority = sortOrder.sortPriority(for: secondItem.kind)

      if firstPriority != secondPriority {
        return firstPriority < secondPriority
      }

      // Same priority, sort by name
      return firstItem.name < secondItem.name
    }

    // Build display list: sorted items + one empty row
    displayList = itemsWithIndices.map { (inventoryIndex: $0.index, slotData: $0.slotData) }
    displayList.append((inventoryIndex: -1, slotData: nil))  // Empty row at end
  }

  private func updateContentSize() {
    let itemCount = displayList.count
    let totalHeight = Float(itemCount) * rowHeight
    scrollView.contentSize = Size(scrollView.frame.size.width, totalHeight)
  }

  private func scrollToSelectedItem() {
    let itemCount = displayList.count
    let contentHeight = Float(itemCount) * rowHeight
    let viewportHeight = scrollView.frame.size.height
    guard viewportHeight > 0 else { return }  // Don't scroll if frame not set yet

    // ScrollView uses Y-flipped coordinates: contentOffset.y = 0 means bottom, maxOffsetY means top
    // We draw from bottom to top: index 0 at bottom, highest index at top
    // To show index i, we need contentOffset.y such that the item is visible
    //
    // In drawContent: origin.y = frame.origin.y - contentOffset.y
    // Item at index i is drawn at: origin.y + contentHeight - rowHeight - i * rowHeight
    //                              = frame.origin.y - contentOffset.y + contentHeight - rowHeight - i * rowHeight
    //
    // To center item i in viewport, we want its top edge at:
    //   frame.origin.y + (viewportHeight - rowHeight) * 0.5
    //
    // So: frame.origin.y - contentOffset.y + contentHeight - rowHeight - i * rowHeight = frame.origin.y + (viewportHeight - rowHeight) * 0.5
    //     - contentOffset.y + contentHeight - rowHeight - i * rowHeight = (viewportHeight - rowHeight) * 0.5
    //     contentOffset.y = contentHeight - rowHeight - i * rowHeight - (viewportHeight - rowHeight) * 0.5
    //     contentOffset.y = contentHeight - rowHeight * (i + 1) - (viewportHeight - rowHeight) * 0.5

    let selectedYFromTop = Float(selectedIndex) * rowHeight
    let idealOffset = contentHeight - selectedYFromTop - rowHeight - (viewportHeight - rowHeight) * 0.5

    // Clamp to valid range (0 = bottom of content, maxOffset = top of content in Y-flipped coords)
    let maxOffset = max(0, contentHeight - viewportHeight)

    let clampedOffset: Float
    if idealOffset < 0 {
      // Can't center - item is past the bottom, scroll to bottom (0)
      clampedOffset = 0
    } else if idealOffset > maxOffset {
      // Can't center - item is past the top, scroll to top (maxOffset)
      clampedOffset = maxOffset
    } else {
      // Can center - use ideal
      clampedOffset = idealOffset
    }

    scrollView.scroll(to: Point(scrollView.contentOffset.x, clampedOffset), animated: false)
  }

  private func drawContent(origin: Point) {
    let itemCount = displayList.count
    // Y-axis is flipped: draw from bottom to top
    // Index 0 at bottom, highest index at top
    let contentHeight = Float(itemCount) * rowHeight
    let startY = origin.y + contentHeight - rowHeight

    for i in 0..<itemCount {
      // Draw items from bottom to top (index 0 at bottom, highest index at top)
      let rowY = startY - Float(i) * rowHeight
      let isSelected = (i == selectedIndex) && isFocused
      let displayItem = displayList[i]

      drawItemRow(
        at: Point(origin.x, rowY),
        slotData: displayItem.slotData,
        index: i,
        isSelected: isSelected
      )
    }
  }

  private func drawItemRow(at position: Point, slotData: ItemSlotData?, index: Int, isSelected: Bool) {
    let rowRect = Rect(
      x: position.x + rowPaddingX,
      y: position.y + rowPaddingY,
      width: scrollView.frame.size.width - rowPaddingX * 2,
      height: rowHeight - rowPaddingY * 2
    )
    let rowCenter = Point(
      rowRect.origin.x + rowRect.size.width * 0.5,
      rowRect.origin.y + rowRect.size.height * 0.5
    )

    // Draw outer row slot (slot-within-a-slot effect)
    // Super translucent unless focused - reduces visual weight for non-selected items
    var rowSlotColor: Color
    if isSelected && isFocused {
      // Focused rows are more visible
      rowSlotColor = Color(
        selectedSlotColor.red * 0.7,
        selectedSlotColor.green * 0.7,
        selectedSlotColor.blue * 0.7,
        selectedSlotColor.alpha * 1

      )
    } else {
      // Non-focused rows are super translucent
      rowSlotColor = Color(
        selectedSlotColor.red * 0.7,
        selectedSlotColor.green * 0.7,
        selectedSlotColor.blue * 0.7,
        selectedSlotColor.alpha * 0.5
      )
    }

    slotEffect.draw { shader in
      let pulses: Float = (isSelected && isFocused) ? 0.5 : 0.0  // Subtle pulse for row
      shader.setFloat("uPulse", value: pulses)

      shader.setVec3("uBorderTint", value: (0.0, 0.0, 0.0))
      shader.setFloat("uBorderTintStrength", value: 0.0)
      shader.setFloat("uEquippedStroke", value: 0.0)
      shader.setVec3("uEquippedStrokeColor", value: (0.0, 0.0, 0.0))
      shader.setFloat("uEquippedStrokeWidth", value: 0.0)
      shader.setFloat("uEquippedGlow", value: 0.0)
      shader.setVec3("uEquippedGlowColor", value: (0.0, 0.0, 0.0))
      shader.setFloat("uEquippedGlowStrength", value: 0.0)

      shader.setVec2("uPanelSize", value: (rowRect.size.width, rowRect.size.height))
      shader.setVec2("uPanelCenter", value: (rowCenter.x, rowCenter.y))
      shader.setFloat("uBorderThickness", value: rowSlotBorderThickness)
      shader.setFloat("uCornerRadius", value: rowSlotCornerRadius)
      shader.setFloat("uNoiseScale", value: slotNoiseScale)
      shader.setFloat("uNoiseStrength", value: slotNoiseStrength * 0.5)  // Subtle for outer slot
      // Disable radial gradient for outer slot (looks bad when stretched)
      shader.setFloat("uRadialGradientStrength", value: 0.0)

      shader.setVec3(
        "uPanelColor", value: (x: rowSlotColor.red, y: rowSlotColor.green, z: rowSlotColor.blue))
      shader.setFloat("uPanelAlpha", value: rowSlotColor.alpha)
      shader.setVec3("uBorderColor", value: (x: borderColor.red, y: borderColor.green, z: borderColor.blue))
      shader.setVec3(
        "uBorderHighlight", value: (x: borderHighlight.red, y: borderHighlight.green, z: borderHighlight.blue))
      shader.setVec3("uBorderShadow", value: (x: borderShadow.red, y: borderShadow.green, z: borderShadow.blue))
    }

    // Draw item icon slot using the same shader as ItemSlotGrid (inner slot)
    if let slotData = slotData, let item = slotData.item {
      // Check if item requires wide slot
      let isWide = item.requiresWideSlot
      let slotWidth = isWide ? wideSlotWidth : iconSize

      // Right-align non-wide icons (leave empty space on left)
      let iconX: Float
      if isWide {
        iconX = position.x + iconPadding + rowPaddingX
      } else {
        // Right-align: position icon at right edge of wide slot area
        iconX = position.x + iconPadding + rowPaddingX + (wideSlotWidth - iconSize)
      }
      let iconY = position.y + (rowHeight - iconSize) * 0.5
      let slotRect = Rect(x: iconX, y: iconY, width: slotWidth, height: iconSize)
      let centerPosition = Point(
        slotRect.origin.x + slotWidth * 0.5,
        slotRect.origin.y + iconSize * 0.5
      )

      // Draw the inner slot using the same shader as ItemSlotGrid (if enabled)
      if decoratesImage {
        // Determine slot color based on selection state
        var currentSlotColor = slotColor
        if isSelected && isFocused {
          currentSlotColor = selectedSlotColor
        }

        slotEffect.draw { shader in
          // Pulse for selected items
          let pulses: Float = (isSelected && isFocused) ? 1.0 : 0.0
          shader.setFloat("uPulse", value: pulses)

          // No equipped border tint for storage items
          shader.setVec3("uBorderTint", value: (0.0, 0.0, 0.0))
          shader.setFloat("uBorderTintStrength", value: 0.0)
          shader.setFloat("uEquippedStroke", value: 0.0)
          shader.setVec3("uEquippedStrokeColor", value: (0.0, 0.0, 0.0))
          shader.setFloat("uEquippedStrokeWidth", value: 0.0)
          shader.setFloat("uEquippedGlow", value: 0.0)
          shader.setVec3("uEquippedGlowColor", value: (0.0, 0.0, 0.0))
          shader.setFloat("uEquippedGlowStrength", value: 0.0)

          shader.setVec2("uPanelSize", value: (slotWidth, iconSize))
          shader.setVec2("uPanelCenter", value: (centerPosition.x, centerPosition.y))
          shader.setFloat("uBorderThickness", value: slotBorderThickness)
          shader.setFloat("uCornerRadius", value: slotCornerRadius)
          shader.setFloat("uNoiseScale", value: slotNoiseScale)
          shader.setFloat("uNoiseStrength", value: slotNoiseStrength)
          shader.setFloat("uRadialGradientStrength", value: slotRadialGradientStrength)

          // Set colors
          shader.setVec3(
            "uPanelColor", value: (x: currentSlotColor.red, y: currentSlotColor.green, z: currentSlotColor.blue))
          shader.setFloat("uPanelAlpha", value: currentSlotColor.alpha)
          shader.setVec3("uBorderColor", value: (x: borderColor.red, y: borderColor.green, z: borderColor.blue))
          shader.setVec3(
            "uBorderHighlight", value: (x: borderHighlight.red, y: borderHighlight.green, z: borderHighlight.blue))
          shader.setVec3("uBorderShadow", value: (x: borderShadow.red, y: borderShadow.green, z: borderShadow.blue))
        }
      }

      // Draw item image - use wideImage for wide items, preserve aspect ratio and fit within slot
      let image = isWide ? (item.wideImage ?? item.image) : item.image
      if let image = image {
        let maxWidth = slotWidth * 0.8
        let maxHeight = iconSize * 0.8
        let imageAspect = image.naturalSize.width / image.naturalSize.height
        let slotAspect = maxWidth / maxHeight

        let imageWidth: Float
        let imageHeight: Float
        if imageAspect > slotAspect {
          // Image is wider - constrain by width
          imageWidth = maxWidth
          imageHeight = maxWidth / imageAspect
        } else {
          // Image is taller - constrain by height
          imageHeight = maxHeight
          imageWidth = maxHeight * imageAspect
        }

        let imageRect = Rect(
          x: iconX + (slotWidth - imageWidth) * 0.5,
          y: iconY + (iconSize - imageHeight) * 0.5,
          width: imageWidth,
          height: imageHeight
        )
        image.draw(in: imageRect)
      }

      // Layout order: [Space if non-wide] [Image] [Name] [Flexible space] [Quantity]

      // Draw item name - centered vertically, positioned after the slot
      let nameX = iconX + slotWidth + textPadding
      let textY = position.y + rowHeight * 0.5
      let nameStyle = isSelected ? TextStyle.itemName.withColor(.white) : TextStyle.itemName.withColor(.gray300)
      // Use .left anchor which aligns left and centers vertically
      item.name.draw(at: Point(nameX, textY), style: nameStyle, anchor: .left)

      // Draw quantity number
      if slotData.shouldShowQuantity {
        let quantityText = "\(slotData.quantity!)"

        if showsQuantitiesOnImages {
          // Draw on top of image with callout/gradient fade (current behavior)
          let fadeWidth: Float = 8 + quantityText.size(with: .slotQuantity).width * 2
          let fadeOrigin = Point(iconX + slotWidth - fadeWidth - 3, iconY + 5)
          let fadeRect = Rect(origin: fadeOrigin, size: Size(fadeWidth, 19))
          let gradient = Gradient(startingColor: .clear, endingColor: .black.withAlphaComponent(0.8))
          GraphicsContext.current?.drawLinearGradient(gradient, in: fadeRect, angle: 0)

          let quantityX = iconX + slotWidth - 9
          let quantityY = iconY + 6
          quantityText.draw(at: Point(quantityX, quantityY), style: .slotQuantity, anchor: .bottomRight)
        } else {
          // Draw on right side of row without callout, using slotListQuantity style
          let quantityX = rowRect.maxX - rightSideTextPadding
          let quantityY = position.y + rowHeight * 0.5
          quantityText.draw(at: Point(quantityX, quantityY), style: .slotListQuantity, anchor: .center)
        }
      }
    } else {
      // Draw empty slot indicator - align with item names (as if wide slot is there)
      let emptyText = "Empty"
      // Position as if there's a wide slot (to align with item names)
      let textX = position.x + iconPadding + rowPaddingX + wideSlotWidth + textPadding
      let textY = position.y + rowHeight * 0.5
      emptyText.draw(
        at: Point(textX, textY),
        style: TextStyle.itemDescription.withColor(.gray500),
        anchor: .left
      )
    }
  }
}
