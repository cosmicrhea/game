@MainActor
final class ItemStorageView: RenderLoop {
  // MARK: - Storage View Style
  enum StorageViewStyle {
    case grid
    case list
  }

  // MARK: - UI
  private let promptList = PromptList(.itemStorage)
  private let ambientBackground = GLScreenEffect("Effects/AmbientBackground")
  private let itemDescriptionView = ItemDescriptionView()

  // Item inspection state
  private var currentItemView: ItemView? = nil
  private var isShowingItem: Bool = false
  public var showingItem: Bool { isShowingItem }

  // MARK: - Storage View Style
  private var storageViewStyle: StorageViewStyle = .list  // Default to list

  // MARK: - Grids
  private let playerGrid: ItemSlotGrid
  private var storageGrid: ItemSlotGrid?
  private var storageListView: ItemStorageListView?

  // MARK: - State
  private enum GridId { case player, storage }
  private enum FocusedGrid { case player, storage }

  private var activePlayerIndex: Int = 1  // 1 or 2
  private var focusedGrid: FocusedGrid = .player

  // Take out mode: blank grid slot selected → focus list → place item
  private var takeOutModeDestinationSlot: Int? = nil

  // Retrieve mode: list item selected → select grid slot → place item
  private var retrieveModeSourceIndex: Int? = nil  // display index in list

  // Saved row position when navigating from grid to list
  private var savedPlayerGridRow: Int? = nil

  // Mouse tracking
  private var lastMouseX: Double = 0
  private var lastMouseY: Double = 0

  // Layout
  private let interGridSpacing: Float = 96

  init() {
    // Player inventory grid: same size as InventoryView (4x4)
    playerGrid = ItemSlotGrid(
      columns: 4,
      rows: 4,
      slotSize: 80.0,
      spacing: 3.0
    )
    playerGrid.allowsMoving = false  // Disable move mode - use menus instead
    playerGrid.showMenuOnSelection = true  // Show menu on selection
    // Wire up to Inventory.player1
    playerGrid.inventory = Inventory.player1
    // Wire up slot menu actions
    playerGrid.onSlotAction = { [weak self] action, slotIndex in
      self?.handlePlayerGridSlotAction(action, slotIndex: slotIndex)
    }
    // Set custom actions provider for storage view menu
    playerGrid.customActionsProvider = { [weak self] slotIndex in
      guard let self = self else { return [] }
      guard let slotData = self.playerGrid.getSlotData(at: slotIndex) else {
        // Empty slot - in take out mode, allow selecting it
        if self.takeOutModeDestinationSlot != nil {
          return []  // No menu for empty slots, but selection works
        }
        return []
      }

      guard let item = slotData.item else { return [] }

      var actions: [SlotAction] = [.store, .inspect]

      // Add Combine if applicable (keys can be combined)
      if case .key = item.kind {
        actions.insert(.combine, at: 1)
      }

      return actions
    }

    // Storage view: create based on style
    switch storageViewStyle {
    case .grid:
      // Storage grid: larger than inventory view
      let grid = ItemSlotGrid(
        columns: 6,
        rows: 4,
        slotSize: 80.0,
        spacing: 3.0
      )
      grid.allowsMoving = false
      grid.showMenuOnSelection = true
      grid.inventory = Inventory.storage
      storageGrid = grid
      storageListView = nil
    case .list:
      // Storage list view
      let listFrame = Rect(x: 0, y: 0, width: 440, height: 400)  // Will be positioned in recenterGrids
      let list = ItemStorageListView(frame: listFrame)
      list.setInventory(Inventory.storage)
      list.onSelectionChanged = { [weak self] index in
        self?.updateItemDescription()
      }
      list.onSlotAction = { [weak self] action, displayIndex in
        self?.handleStorageListSlotAction(action, displayIndex: displayIndex)
      }
      list.onItemSelected = { [weak self] displayIndex in
        self?.handleStorageListEmptyRowSelected(displayIndex: displayIndex)
      }
      storageGrid = nil
      storageListView = list
    }

    // Initial layout
    recenterGrids()
  }

  // MARK: - Layout

  private func recenterGrids() {
    // Match InventoryView positioning for the player grid (on the right)
    let playerTotal = playerGrid.totalSize
    let isCentered = Config.current.centeredLayout
    let playerX: Float = {
      if isCentered {
        return (Float(Engine.viewportSize.width) - playerTotal.width) * 0.5
      } else {
        let rightMargin: Float = 152
        return Float(Engine.viewportSize.width) - playerTotal.width - rightMargin
      }
    }()
    let playerY: Float = (Float(Engine.viewportSize.height) - playerTotal.height) * 0.5 + 80
    playerGrid.setPosition(Point(playerX, playerY))

    // Storage view to the left of player grid
    switch storageViewStyle {
    case .grid:
      if let storageGrid = storageGrid {
        let storageTotal = storageGrid.totalSize
        let storageX = playerX - interGridSpacing - storageTotal.width
        let storageY = (Float(Engine.viewportSize.height) - storageTotal.height) * 0.5 + 80
        storageGrid.setPosition(Point(storageX, storageY))
      }
    case .list:
      if let storageListView {
        let listWidth: Float = 440
        let listHeight: Float = storageListView.rowHeight * 8.5
        // Center the list between left screen edge and left edge of grid, with slight right bias
        let gridLeftEdge = playerX - interGridSpacing
        let leftMargin: Float = 80  // Margin from left edge
        let availableWidth = gridLeftEdge - leftMargin
        // let storageX = leftMargin + availableWidth * 0.6 - listWidth * 0.5  // 60% from left, 40% from grid
        let storageX: Float = 176
        let storageY = (Float(Engine.viewportSize.height) - listHeight) * 0.5 + 80
        storageListView.setFrame(Rect(x: storageX, y: storageY, width: listWidth, height: listHeight))
      }
    }
  }

  // MARK: - RenderLoop

  func update(window: Window, deltaTime: Float) {
    if isShowingItem {
      currentItemView?.update(window: window, deltaTime: deltaTime)
    } else {
      recenterGrids()
      // Focus colors
      playerGrid.isFocused = (focusedGrid == .player)

      switch storageViewStyle {
      case .grid:
        storageGrid?.isFocused = (focusedGrid == .storage)
        storageGrid?.update(deltaTime: deltaTime)
      case .list:
        storageListView?.setFocused(focusedGrid == .storage)
        storageListView?.update(deltaTime: deltaTime)
      }

      playerGrid.update(deltaTime: deltaTime)
      updateItemDescription()
    }
  }

  func onKeyPressed(window: Window, key: Keyboard.Key, scancode: Int32, mods: Keyboard.Modifier) {
    if isShowingItem {
      if key == .escape {
        UISound.cancel()
        hideItem()
        return
      }
      currentItemView?.onKeyPressed(window: window, key: key, scancode: scancode, mods: mods)
      return
    }

    // Sort with Alt (Option key) - cycle through sort orders
    if key == .leftAlt || key == .rightAlt {
      if focusedGrid == .storage, case .list = storageViewStyle {
        // Cycle sort order
        if let currentOrder = storageListView?.currentSortOrder {
          let allOrders = ItemSortOrder.allCases
          if let currentIndex = allOrders.firstIndex(of: currentOrder) {
            let nextIndex = (currentIndex + 1) % allOrders.count
            storageListView?.setSortOrder(allOrders[nextIndex])
            UISound.navigate()
          }
        }
        return
      }
      // Alt key disabled for inspect in storage view
      return
    }

    // Handle retrieve/take out modes first (but only if menus aren't visible)
    let menuVisible: Bool = {
      if focusedGrid == .player && playerGrid.slotMenu.isVisible {
        return true
      }
      if focusedGrid == .storage {
        switch storageViewStyle {
        case .list:
          return storageListView?.isSlotMenuVisible == true
        case .grid:
          return storageGrid?.slotMenu.isVisible == true
        }
      }
      return false
    }()

    if !menuVisible && (retrieveModeSourceIndex != nil || takeOutModeDestinationSlot != nil) {
      if key == .f || key == .space || key == .enter || key == .numpadEnter {
        if focusedGrid == .player {
          let targetSlot = playerGrid.selectedIndex

          // Retrieve mode: place item from list to selected grid slot
          if let sourceDisplayIndex = retrieveModeSourceIndex {
            if let inventoryIndex = storageListView?.getInventoryIndex(at: sourceDisplayIndex),
              let sourceSlotData = Inventory.storage.slots[inventoryIndex]
            {
              // Check if target slot is empty
              if let targetSlotData = playerGrid.getSlotData(at: targetSlot), targetSlotData.isEmpty {
                // Move item from storage to player grid
                playerGrid.setSlotData(sourceSlotData, at: targetSlot)
                Inventory.storage.slots[inventoryIndex] = nil
                storageListView?.rebuildDisplayList()
                // Clear retrieve mode
                retrieveModeSourceIndex = nil
                playerGrid.highlightedSlotIndex = nil
                UISound.select()
                return
              } else {
                UISound.error()  // Slot not empty
                return
              }
            }
          }
          // Take out mode: place item from selected grid slot to storage
          else if takeOutModeDestinationSlot != nil {
            if let sourceSlotData = playerGrid.getSlotData(at: targetSlot), sourceSlotData.item != nil {
              // Find or create empty slot in storage (storage never fills up)
              let emptyInventoryIndex = findFirstEmptyStorageInventorySlot()
              // Move item from player grid to storage
              playerGrid.setSlotData(nil, at: targetSlot)
              // Handle equipped state
              if playerGrid.equippedWeaponIndex == targetSlot {
                playerGrid.setEquippedWeaponIndex(nil)
              }
              Inventory.storage.slots[emptyInventoryIndex] = sourceSlotData
              storageListView?.rebuildDisplayList()
              // Clear take out mode
              takeOutModeDestinationSlot = nil
              playerGrid.highlightedSlotIndex = nil
              UISound.select()
              return
            }
          }
        }
        return
      }
      if key == .escape {
        // Cancel retrieve/take out mode
        retrieveModeSourceIndex = nil
        takeOutModeDestinationSlot = nil
        playerGrid.highlightedSlotIndex = nil
        UISound.cancel()
        return
      }
    }

    // Escape key: close menus first, then cancel retrieve/take out modes
    if key == .escape {
      // Close any open menus
      if focusedGrid == .player && playerGrid.slotMenu.isVisible {
        playerGrid.slotMenu.hide()
        return
      }
      if focusedGrid == .storage {
        switch storageViewStyle {
        case .grid:
          if storageGrid?.slotMenu.isVisible == true {
            storageGrid?.slotMenu.hide()
            return
          }
        case .list:
          if storageListView?.isSlotMenuVisible == true {
            storageListView?.hideSlotMenu()
            return
          }
        }
      }
      // If no menus, cancel retrieve/take out modes
      if retrieveModeSourceIndex != nil || takeOutModeDestinationSlot != nil {
        retrieveModeSourceIndex = nil
        takeOutModeDestinationSlot = nil
        playerGrid.highlightedSlotIndex = nil
        UISound.cancel()
        return
      }
    }

    // Forward F/space/enter to grid/list to show menu or handle selection
    if key == .f || key == .space || key == .enter || key == .numpadEnter {
      // Check if menus are visible first - if so, forward to menu
      if menuVisible {
        // Menu is visible - let it handle the key
        switch focusedGrid {
        case .player:
          _ = playerGrid.handleKey(key)
        case .storage:
          switch storageViewStyle {
          case .grid:
            _ = storageGrid?.handleKey(key)
          case .list:
            _ = storageListView?.handleKey(key)
          }
        }
        return
      }

      // No menu visible - forward to grid/list to show menu or handle selection
      switch focusedGrid {
      case .player:
        if playerGrid.handleKey(key) {
          return
        }
      case .storage:
        switch storageViewStyle {
        case .grid:
          if storageGrid?.handleKey(key) == true {
            return
          }
        case .list:
          if storageListView?.handleKey(key) == true {
            return
          }
        }
      }
      return
    }

    // Switch active player label with 1/2
    if key == .num1 {
      activePlayerIndex = 1
      UISound.navigate()
      return
    }
    if key == .num2 {
      activePlayerIndex = 2
      UISound.navigate()
      return
    }

    // Cross-grid navigation on horizontal edges
    if handleCrossGridNavigation(for: key) {
      return
    }

    // Otherwise forward navigation to focused grid
    switch focusedGrid {
    case .player:
      // Check if menu is visible - if so, don't update highlight
      if !playerGrid.slotMenu.isVisible {
        _ = playerGrid.handleKey(key)
        // Update highlighted slot in retrieve/take out modes
        if retrieveModeSourceIndex != nil || takeOutModeDestinationSlot != nil {
          let selectedSlot = playerGrid.selectedIndex
          if let slotData = playerGrid.getSlotData(at: selectedSlot), slotData.isEmpty {
            playerGrid.highlightedSlotIndex = selectedSlot
            if takeOutModeDestinationSlot == nil {
              takeOutModeDestinationSlot = selectedSlot
            }
          } else {
            playerGrid.highlightedSlotIndex = nil
          }
        }
      } else {
        // Menu is visible - just forward to grid (which will forward to menu)
        _ = playerGrid.handleKey(key)
      }
    case .storage:
      switch storageViewStyle {
      case .grid:
        _ = storageGrid?.handleKey(key)
      case .list:
        _ = storageListView?.handleKey(key)
      }
    }
  }

  func onMouseMove(window: Window, x: Double, y: Double) {
    lastMouseX = x
    lastMouseY = y

    if isShowingItem {
      currentItemView?.onMouseMove(window: window, x: x, y: y)
      return
    }

    // Flip Y coordinate to match screen coordinates (top-left origin)
    let mousePosition = Point(Float(x), Float(Engine.viewportSize.height) - Float(y))
    playerGrid.handleMouseMove(at: mousePosition)

    switch storageViewStyle {
    case .grid:
      storageGrid?.handleMouseMove(at: mousePosition)
    case .list:
      // Handle both scroll dragging and selection hover
      _ = storageListView?.handleMouseMove(at: mousePosition)
    }
  }

  func onMouseButton(window: Window, button: Mouse.Button, state: ButtonState, mods: Keyboard.Modifier) {
    if isShowingItem {
      // Forward mouse input to ItemView
      currentItemView?.onMouseButton(window: window, button: button, state: state, mods: mods)
      return
    }

    let mousePosition = Point(Float(lastMouseX), Float(Engine.viewportSize.height) - Float(lastMouseY))

    if focusedGrid == .storage, case .list = storageViewStyle {
      if button == .left {
        if state == .pressed {
          _ = storageListView?.handleMouseDown(at: mousePosition)
        } else if state == .released {
          storageListView?.handleMouseUp()
        }
      }
    }
  }

  func onMouseButtonPressed(window: Window, button: Mouse.Button, mods: Keyboard.Modifier) {
    let mousePosition = Point(Float(lastMouseX), Float(Engine.viewportSize.height) - Float(lastMouseY))

    if isShowingItem {
      currentItemView?.onMouseButtonPressed(window: window, button: button, mods: mods)
      return
    }

    // Check if menus are visible - forward clicks to menu handlers
    if button == .left {
      if focusedGrid == .player && playerGrid.slotMenu.isVisible {
        // Menu is visible - let grid handle it (which forwards to menu)
        _ = playerGrid.handleMouseClick(at: mousePosition)
        return
      }
      if focusedGrid == .storage {
        switch storageViewStyle {
        case .grid:
          if storageGrid?.slotMenu.isVisible == true {
            _ = storageGrid?.handleMouseClick(at: mousePosition)
            return
          }
        case .list:
          if storageListView?.isSlotMenuVisible == true {
            // Menu is visible - let list handle it
            _ = storageListView?.handleMouseClick(at: mousePosition)
            return
          }
        }
      }
    }

    // Right-click: cancel retrieve/take out modes
    if button == .right {
      if retrieveModeSourceIndex != nil || takeOutModeDestinationSlot != nil {
        retrieveModeSourceIndex = nil
        takeOutModeDestinationSlot = nil
        playerGrid.highlightedSlotIndex = nil
        UISound.cancel()
        return
      }
      return
    }

    guard button == .left else { return }

    // Handle retrieve/take out modes on click (only if not in menu)
    if retrieveModeSourceIndex != nil || takeOutModeDestinationSlot != nil {
      if let slotIndex = playerGrid.slotIndex(at: mousePosition) {
        // Retrieve mode: place item from list to clicked grid slot
        if let sourceDisplayIndex = retrieveModeSourceIndex {
          if let inventoryIndex = storageListView?.getInventoryIndex(at: sourceDisplayIndex),
            let sourceSlotData = Inventory.storage.slots[inventoryIndex]
          {
            // Check if target slot is empty
            if let targetSlotData = playerGrid.getSlotData(at: slotIndex), targetSlotData.isEmpty {
              // Move item from storage to player grid
              playerGrid.setSlotData(sourceSlotData, at: slotIndex)
              Inventory.storage.slots[inventoryIndex] = nil
              storageListView?.rebuildDisplayList()
              // Clear retrieve mode
              retrieveModeSourceIndex = nil
              playerGrid.highlightedSlotIndex = nil
              UISound.select()
              return
            } else {
              UISound.error()  // Slot not empty
              return
            }
          }
        }
        // Take out mode: place item from clicked grid slot to storage
        else if takeOutModeDestinationSlot != nil {
          if let sourceSlotData = playerGrid.getSlotData(at: slotIndex), sourceSlotData.item != nil {
            // Find or create empty slot in storage (storage never fills up)
            let emptyInventoryIndex = findFirstEmptyStorageInventorySlot()
            // Move item from player grid to storage
            playerGrid.setSlotData(nil, at: slotIndex)
            // Handle equipped state
            if playerGrid.equippedWeaponIndex == slotIndex {
              playerGrid.setEquippedWeaponIndex(nil)
            }
            Inventory.storage.slots[emptyInventoryIndex] = sourceSlotData
            storageListView?.rebuildDisplayList()
            // Clear take out mode
            takeOutModeDestinationSlot = nil
            playerGrid.highlightedSlotIndex = nil
            UISound.select()
            return
          }
        }
      }
      return
    }

    // Normal click handling - forward to grids/lists (they'll show menus)
    let playerIndex = playerGrid.slotIndex(at: mousePosition)
    let storageIndex: Int? = {
      switch storageViewStyle {
      case .grid:
        return storageGrid?.slotIndex(at: mousePosition)
      case .list:
        if storageListView?.handleMouseClick(at: mousePosition) == true {
          return storageListView?.currentSelectedIndex
        }
        return nil
      }
    }()

    // Forward clicks to grids (they handle menu display)
    if playerIndex != nil {
      _ = playerGrid.handleMouseClick(at: mousePosition)
    }
    if storageIndex != nil {
      switch storageViewStyle {
      case .grid:
        _ = storageGrid?.handleMouseClick(at: mousePosition)
      case .list:
        // Already handled above
        break
      }
    }
  }

  func onMouseButtonReleased(window: Window, button: Mouse.Button, mods: Keyboard.Modifier) {
    // no-op
  }

  func onScroll(window: Window, xOffset: Double, yOffset: Double) {
    if isShowingItem {
      // Forward scroll input to ItemView
      currentItemView?.onScroll(window: window, xOffset: xOffset, yOffset: yOffset)
      return
    }

    let mousePosition = Point(Float(lastMouseX), Float(Engine.viewportSize.height) - Float(lastMouseY))

    if focusedGrid == .storage, case .list = storageViewStyle {
      storageListView?.handleScroll(xOffset: xOffset, yOffset: yOffset, mouse: mousePosition)
    }
  }

  func draw() {
    if isShowingItem {
      currentItemView?.draw()
      return
    }

    // Background
    ambientBackground.draw { shader in
      shader.setVec3("uTintDark", value: (0.035, 0.045, 0.055))
      shader.setVec3("uTintLight", value: (0.085, 0.10, 0.11))
      shader.setFloat("uMottle", value: 0.35)
      shader.setFloat("uGrain", value: 0.08)
      shader.setFloat("uVignette", value: 0.35)
      shader.setFloat("uDust", value: 0.06)
    }

    // Grids
    playerGrid.draw()

    switch storageViewStyle {
    case .grid:
      storageGrid?.draw()
    case .list:
      storageListView?.draw()
    }

    // Item description
    itemDescriptionView.draw()

    // Prompts
    // Use itemStorageList if storage list is focused, otherwise itemStorage
    if focusedGrid == .storage, case .list = storageViewStyle {
      promptList.group = .itemStorageList
    } else {
      promptList.group = .itemStorage
    }
    promptList.draw()
  }

  // MARK: - Cross-grid selection navigation

  private func handleCrossGridNavigation(for key: Keyboard.Key) -> Bool {
    let isLeft = (key == .a || key == .left)
    let isRight = (key == .d || key == .right)
    guard isLeft || isRight else { return false }

    // Don't allow cross-grid navigation when menus are visible
    let menuVisible: Bool = {
      if focusedGrid == .player && playerGrid.slotMenu.isVisible {
        return true
      }
      if focusedGrid == .storage {
        switch storageViewStyle {
        case .list:
          return storageListView?.isSlotMenuVisible == true
        case .grid:
          return storageGrid?.slotMenu.isVisible == true
        }
      }
      return false
    }()
    if menuVisible {
      return false
    }

    switch focusedGrid {
    case .player:
      if isLeft {
        // Player grid is on the right now: at left edge, jump to storage
        let currentIndex = playerGrid.selectedIndex
        let col = currentIndex % playerGrid.columns
        if col == 0 {
          switch storageViewStyle {
          case .grid:
            if let storageGrid = storageGrid {
              let row = currentIndex / playerGrid.columns
              let targetRow = min(row, storageGrid.rows - 1)
              let targetIndex = targetRow * storageGrid.columns + (storageGrid.columns - 1)
              storageGrid.setSelected(targetIndex)
            }
          case .list:
            // Save the current row before switching to list
            savedPlayerGridRow = currentIndex / playerGrid.columns
            // Just switch focus, list will handle selection
            break
          }
          focusedGrid = .storage
          UISound.navigate()
          return true
        }
      }
    case .storage:
      if isRight {
        // Storage is on the left now: at right edge, jump to player grid's leftmost column
        switch storageViewStyle {
        case .grid:
          if let storageGrid = storageGrid {
            let currentIndex = storageGrid.selectedIndex
            let col = currentIndex % storageGrid.columns
            if col == storageGrid.columns - 1 {
              let row = currentIndex / storageGrid.columns
              let targetRow = min(row, playerGrid.rows - 1)
              let targetIndex = targetRow * playerGrid.columns + 0
              playerGrid.setSelected(targetIndex)
              focusedGrid = .player
              UISound.navigate()
              return true
            }
          }
        case .list:
          // Always allow switching from list to grid
          // Restore to saved row if available, otherwise use approximate row from list
          let targetRow: Int
          if let savedRow = savedPlayerGridRow {
            targetRow = min(savedRow, playerGrid.rows - 1)
            savedPlayerGridRow = nil  // Clear saved row after restoring
          } else {
            let currentIndex = storageListView?.currentSelectedIndex ?? 0
            targetRow = min(currentIndex / 4, playerGrid.rows - 1)  // Approximate row
          }
          let targetIndex = targetRow * playerGrid.columns + 0  // First column of the row
          playerGrid.setSelected(targetIndex)
          focusedGrid = .player
          UISound.navigate()
          return true
        }
      }
    }
    return false
  }

  // MARK: - Description

  private func updateItemDescription() {
    let selectedIndex: Int = {
      switch focusedGrid {
      case .player: return playerGrid.selectedIndex
      case .storage:
        switch storageViewStyle {
        case .grid: return storageGrid?.selectedIndex ?? 0
        case .list: return storageListView?.currentSelectedIndex ?? 0
        }
      }
    }()

    let data: ItemSlotData? = {
      switch focusedGrid {
      case .player: return playerGrid.getSlotData(at: selectedIndex)
      case .storage:
        switch storageViewStyle {
        case .grid: return storageGrid?.getSlotData(at: selectedIndex)
        case .list: return storageListView?.getSlotData(at: selectedIndex)
        }
      }
    }()

    if let slotData = data, let item = slotData.item {
      itemDescriptionView.title = item.name
      itemDescriptionView.descriptionText = item.description ?? ""
    } else {
      itemDescriptionView.title = ""
      itemDescriptionView.descriptionText = ""
    }
  }

  // MARK: - Helpers

  // MARK: - Menu Action Handlers

  private func handlePlayerGridSlotAction(_ action: SlotAction, slotIndex: Int) {
    switch action {
    case .store:
      // Store item from grid to storage
      if let slotData = playerGrid.getSlotData(at: slotIndex), slotData.item != nil {
        // Find first empty slot in storage
        if let emptyIndex = findFirstEmptyStorageSlot() {
          // Move item to storage
          playerGrid.setSlotData(nil, at: slotIndex)
          // Handle equipped state
          if playerGrid.equippedWeaponIndex == slotIndex {
            playerGrid.setEquippedWeaponIndex(nil)
          }
          // Add to storage
          switch storageViewStyle {
          case .grid:
            storageGrid?.setSlotData(slotData, at: emptyIndex)
          case .list:
            // Find or create actual inventory index for empty slot (storage never fills up)
            let inventoryIndex = findFirstEmptyStorageInventorySlot()
            Inventory.storage.slots[inventoryIndex] = slotData
            storageListView?.rebuildDisplayList()
          }
          UISound.select()
        }
      }
    case .combine:
      // TODO: Implement combine logic
      UISound.select()
    case .inspect:
      if let slotData = playerGrid.getSlotData(at: slotIndex), let item = slotData.item {
        showItem(item)
      }
    default:
      break
    }
  }

  private func handleStorageListSlotAction(_ action: SlotAction, displayIndex: Int) {
    switch action {
    case .retrieve:
      // Enter retrieve mode: highlight this item, wait for grid slot selection
      retrieveModeSourceIndex = displayIndex
      // Move focus to grid
      focusedGrid = .player
      // Highlight first empty slot if available
      if let emptySlot = findFirstEmptyPlayerSlot() {
        playerGrid.highlightedSlotIndex = emptySlot
      }
      UISound.select()
    case .inspect:
      if let slotData = storageListView?.getSlotData(at: displayIndex), let item = slotData.item {
        showItem(item)
      }
    default:
      break
    }
  }

  private func handleStorageListEmptyRowSelected(displayIndex: Int) {
    // Empty row selected - enter take out mode: focus grid, wait for item selection
    guard let storageListView = storageListView else { return }
    // Get the slot data to check if it's empty
    guard let slotData = storageListView.getSlotData(at: displayIndex), slotData.isEmpty else { return }

    // Enter take out mode: store destination slot (will be set when user selects a slot in grid)
    takeOutModeDestinationSlot = nil  // Will be set when user selects a slot
    // Move focus to grid
    focusedGrid = .player
    // Highlight first empty slot if available (for visual feedback)
    if let emptySlot = findFirstEmptyPlayerSlot() {
      playerGrid.highlightedSlotIndex = emptySlot
      takeOutModeDestinationSlot = emptySlot
    }
    UISound.select()
  }

  // MARK: - Helper Functions

  private func findFirstEmptyStorageSlot() -> Int? {
    switch storageViewStyle {
    case .grid:
      guard let storageGrid = storageGrid else { return nil }
      // Check existing slots
      for i in 0..<(storageGrid.columns * storageGrid.rows) {
        if let slotData = storageGrid.getSlotData(at: i), slotData.isEmpty {
          return i
        }
      }
      // If grid is full, expand storage inventory and return new index
      let newIndex = Inventory.storage.slots.count
      Inventory.storage.slots.append(nil)
      // Note: The grid view might need to be updated to reflect new slots, but for now
      // we'll return the index and let the grid handle it
      return newIndex < (storageGrid.columns * storageGrid.rows) ? newIndex : nil
    case .list:
      // For list, we need to find an empty inventory slot (always succeeds)
      return findFirstEmptyStorageInventorySlot()
    }
  }

  private func findFirstEmptyStorageInventorySlot() -> Int {
    // Find first empty slot, or create a new one if all are full
    for (index, slot) in Inventory.storage.slots.enumerated() {
      if slot == nil || slot?.isEmpty == true {
        return index
      }
    }
    // No empty slot found - append a new one
    let newIndex = Inventory.storage.slots.count
    Inventory.storage.slots.append(nil)
    return newIndex
  }

  private func findFirstEmptyPlayerSlot() -> Int? {
    for i in 0..<(playerGrid.columns * playerGrid.rows) {
      if let slotData = playerGrid.getSlotData(at: i), slotData.isEmpty {
        return i
      }
    }
    return nil
  }

  private func getSelectedItemInFocusedGrid() -> Item? {
    switch focusedGrid {
    case .player:
      return playerGrid.getSlotData(at: playerGrid.selectedIndex)?.item
    case .storage:
      switch storageViewStyle {
      case .grid:
        guard let storageGrid = storageGrid else { return nil }
        return storageGrid.getSlotData(at: storageGrid.selectedIndex)?.item
      case .list:
        guard let storageListView = storageListView else { return nil }
        return storageListView.getSlotData(at: storageListView.currentSelectedIndex)?.item
      }
    }
  }

  private func showItem(_ item: Item) {
    currentItemView = ItemView(item: item)
    currentItemView?.onItemFinished = { [weak self] in
      self?.hideItem()
    }
    isShowingItem = true
  }

  private func hideItem() {
    currentItemView = nil
    isShowingItem = false
  }

}
