@MainActor
final class ItemStorageView: RenderLoop {
  // MARK: - UI
  private let promptList = PromptList(.itemStorage)
  private let ambientBackground = GLScreenEffect("Effects/AmbientBackground")
  private let itemDescriptionView = ItemDescriptionView()

  // Item inspection state
  private var currentItemView: ItemView? = nil
  private var isShowingItem: Bool = false
  public var showingItem: Bool { isShowingItem }

  // MARK: - Grids
  private let playerGrid: SlotGrid
  private let storageGrid: SlotGrid

  // MARK: - State
  private enum GridId { case player, storage }
  private enum FocusedGrid { case player, storage }

  private var activePlayerIndex: Int = 1  // 1 or 2
  private var focusedGrid: FocusedGrid = .player

  // Global moving mode across two grids
  private var isMoveModeActive: Bool = false
  private var movingSource: (grid: GridId, index: Int)? = nil

  // Mouse tracking
  private var lastMouseX: Double = 0
  private var lastMouseY: Double = 0

  // Layout
  private let interGridSpacing: Float = 96

  init() {
    // Player inventory grid: same size as InventoryView (4x2)
    playerGrid = SlotGrid(
      columns: 4,
      rows: 4,
      slotSize: 80.0,
      spacing: 3.0
    )
    playerGrid.allowsMoving = true
    playerGrid.showMenuOnSelection = false

    // Storage grid: larger than inventory view
    storageGrid = SlotGrid(
      columns: 6,
      rows: 4,
      slotSize: 80.0,
      spacing: 3.0
    )
    storageGrid.allowsMoving = true
    storageGrid.showMenuOnSelection = false

    // Populate sample data
    setupPlayerSlots()
    setupStorageSlots()

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

    // Storage grid to the left of player grid
    let storageTotal = storageGrid.totalSize
    let storageX = playerX - interGridSpacing - storageTotal.width
    let storageY = (Float(Engine.viewportSize.height) - storageTotal.height) * 0.5 + 80
    storageGrid.setPosition(Point(storageX, storageY))
  }

  // MARK: - RenderLoop

  func update(window: Window, deltaTime: Float) {
    if isShowingItem {
      currentItemView?.update(window: window, deltaTime: deltaTime)
    } else {
      recenterGrids()
      // Focus colors
      playerGrid.isFocused = (focusedGrid == .player)
      storageGrid.isFocused = (focusedGrid == .storage)

      playerGrid.update(deltaTime: deltaTime)
      storageGrid.update(deltaTime: deltaTime)

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

    // Inspect with Alt
    if key == .leftAlt || key == .rightAlt {
      if let item = getSelectedItemInFocusedGrid() {
        UISound.select()
        showItem(item)
      }
      return
    }

    // Enter/confirm move mode with f/space/enter/numpadEnter
    if key == .f || key == .space || key == .enter || key == .numpadEnter {
      if isMoveModeActive {
        // Confirm move to currently selected cell in focused grid
        if let source = movingSource {
          switch (source.grid, focusedGrid) {
          case (.player, .player):
            performSameGridSwap(grid: playerGrid, sourceIndex: source.index, targetIndex: playerGrid.selectedIndex)
          case (.player, .storage):
            performCrossGridSwap(
              sourceGrid: playerGrid,
              sourceIndex: source.index,
              targetGrid: storageGrid,
              targetIndex: storageGrid.selectedIndex,
              keepMoving: true
            )
          case (.storage, .storage):
            performSameGridSwap(grid: storageGrid, sourceIndex: source.index, targetIndex: storageGrid.selectedIndex)
          case (.storage, .player):
            performCrossGridSwap(
              sourceGrid: storageGrid,
              sourceIndex: source.index,
              targetGrid: playerGrid,
              targetIndex: playerGrid.selectedIndex,
              keepMoving: true
            )
          }
        }
      } else {
        enterMoveModeFromFocusedSelection()
      }
      return
    }

    // Switch focused grid with Tab
    if key == .tab {
      focusedGrid = (focusedGrid == .player) ? .storage : .player
      UISound.navigate()
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
      _ = playerGrid.handleKey(key)
    case .storage:
      _ = storageGrid.handleKey(key)
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
    storageGrid.handleMouseMove(at: mousePosition)
  }

  func onMouseButton(window: Window, button: Mouse.Button, state: ButtonState, mods: Keyboard.Modifier) {
    // no-op
  }

  func onMouseButtonPressed(window: Window, button: Mouse.Button, mods: Keyboard.Modifier) {
    let mousePosition = Point(Float(lastMouseX), Float(Engine.viewportSize.height) - Float(lastMouseY))

    if isShowingItem {
      currentItemView?.onMouseButtonPressed(window: window, button: button, mods: mods)
      return
    }

    if button == .right {
      // Cancel move mode
      cancelMoveMode()
      return
    }

    guard button == .left else { return }

    // Determine clicked grid and index
    let playerIndex = playerGrid.slotIndex(at: mousePosition)
    let storageIndex = storageGrid.slotIndex(at: mousePosition)

    if isMoveModeActive {
      handleMoveClick(playerIndex: playerIndex, storageIndex: storageIndex)
      return
    }

    // Not in move mode: click picks up (enter move mode) if slot has item
    if let idx = playerIndex, let data = playerGrid.getSlotData(at: idx), data.item != nil {
      focusedGrid = .player
      movingSource = (.player, idx)
      playerGrid.setSelected(idx)
      playerGrid.setMovingModeActive(true)
      isMoveModeActive = true
      UISound.select()
      return
    }
    if let idx = storageIndex, let data = storageGrid.getSlotData(at: idx), data.item != nil {
      focusedGrid = .storage
      movingSource = (.storage, idx)
      storageGrid.setSelected(idx)
      storageGrid.setMovingModeActive(true)
      isMoveModeActive = true
      UISound.select()
      return
    }
  }

  func onMouseButtonReleased(window: Window, button: Mouse.Button, mods: Keyboard.Modifier) {
    // no-op
  }

  func onScroll(window: Window, xOffset: Double, yOffset: Double) {}

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
    storageGrid.draw()

    // Item description
    itemDescriptionView.draw()

    // Prompts
    promptList.group = isMoveModeActive ? .confirmCancel : .itemStorage
    promptList.draw()
  }

  // MARK: - Move mode and transfer

  private func toggleMoveMode() {
    if isMoveModeActive {
      cancelMoveMode()
    } else {
      isMoveModeActive = true
      movingSource = nil
      // Ensure both grids are not already in their internal move state
      playerGrid.setMovingModeActive(false)
      storageGrid.setMovingModeActive(false)
    }
  }

  private func cancelMoveMode() {
    isMoveModeActive = false
    movingSource = nil
    playerGrid.cancelPendingMove()
    storageGrid.cancelPendingMove()
    playerGrid.setMovingModeActive(false)
    storageGrid.setMovingModeActive(false)
  }

  private func handleMoveClick(playerIndex: Int?, storageIndex: Int?) {
    // 1) Pick up
    if movingSource == nil {
      if let idx = playerIndex, let data = playerGrid.getSlotData(at: idx), data.item != nil {
        movingSource = (.player, idx)
        playerGrid.setSelected(idx)
        playerGrid.setMovingModeActive(true)
        UISound.select()
        return
      }
      if let idx = storageIndex, let data = storageGrid.getSlotData(at: idx), data.item != nil {
        movingSource = (.storage, idx)
        storageGrid.setSelected(idx)
        storageGrid.setMovingModeActive(true)
        UISound.select()
        return
      }
      return
    }

    // 2) Drop/Swap
    guard let source = movingSource else { return }

    switch source.grid {
    case .player:
      if let targetIdx = storageIndex {
        performCrossGridSwap(
          sourceGrid: playerGrid, sourceIndex: source.index, targetGrid: storageGrid, targetIndex: targetIdx)
        return
      }
      if let targetIdx = playerIndex {
        // Same-grid move: delegate to grid logic
        _ = targetIdx
        _ = playerGrid.handleMouseClick(
          at: Point(Float(lastMouseX), Float(Engine.viewportSize.height) - Float(lastMouseY)))
        return
      }
    case .storage:
      if let targetIdx = playerIndex {
        performCrossGridSwap(
          sourceGrid: storageGrid, sourceIndex: source.index, targetGrid: playerGrid, targetIndex: targetIdx)
        return
      }
      if let targetIdx = storageIndex {
        // Same-grid move: delegate to grid logic
        _ = targetIdx
        _ = storageGrid.handleMouseClick(
          at: Point(Float(lastMouseX), Float(Engine.viewportSize.height) - Float(lastMouseY)))
        return
      }
    }
  }

  private func performCrossGridSwap(
    sourceGrid: SlotGrid, sourceIndex: Int, targetGrid: SlotGrid, targetIndex: Int, keepMoving: Bool = true
  ) {
    let sourceData = sourceGrid.getSlotData(at: sourceIndex)
    let targetData = targetGrid.getSlotData(at: targetIndex)

    sourceGrid.setSlotData(targetData, at: sourceIndex)
    targetGrid.setSlotData(sourceData, at: targetIndex)

    UISound.select()

    if keepMoving, let movedItem = sourceData?.item {
      _ = movedItem
      // Continue moving with the item now at target
      if targetGrid === playerGrid {
        movingSource = (.player, targetIndex)
        playerGrid.setSelected(targetIndex)
        playerGrid.setMovingModeActive(true)
        storageGrid.setMovingModeActive(false)
        focusedGrid = .player
      } else {
        movingSource = (.storage, targetIndex)
        storageGrid.setSelected(targetIndex)
        storageGrid.setMovingModeActive(true)
        playerGrid.setMovingModeActive(false)
        focusedGrid = .storage
      }
      isMoveModeActive = true
    } else {
      // Exit move mode
      playerGrid.cancelPendingMove()
      storageGrid.cancelPendingMove()
      playerGrid.setMovingModeActive(false)
      storageGrid.setMovingModeActive(false)
      movingSource = nil
      isMoveModeActive = false
    }
  }

  private func performSameGridSwap(grid: SlotGrid, sourceIndex: Int, targetIndex: Int) {
    guard sourceIndex != targetIndex else { return }
    let sourceData = grid.getSlotData(at: sourceIndex)
    let targetData = grid.getSlotData(at: targetIndex)
    grid.setSlotData(targetData, at: sourceIndex)
    grid.setSlotData(sourceData, at: targetIndex)
    UISound.select()

    // Continue moving with the item now at target
    if grid === playerGrid {
      movingSource = (.player, targetIndex)
      playerGrid.setSelected(targetIndex)
      playerGrid.setMovingModeActive(true)
      storageGrid.setMovingModeActive(false)
      focusedGrid = .player
    } else {
      movingSource = (.storage, targetIndex)
      storageGrid.setSelected(targetIndex)
      storageGrid.setMovingModeActive(true)
      playerGrid.setMovingModeActive(false)
      focusedGrid = .storage
    }
    isMoveModeActive = true
  }

  // MARK: - Cross-grid selection navigation

  private func handleCrossGridNavigation(for key: Keyboard.Key) -> Bool {
    let isLeft = (key == .a || key == .left)
    let isRight = (key == .d || key == .right)
    guard isLeft || isRight else { return false }

    switch focusedGrid {
    case .player:
      if isLeft {
        // Player grid is on the right now: at left edge, jump to storage grid's rightmost column
        let currentIndex = playerGrid.selectedIndex
        let col = currentIndex % playerGrid.columns
        let row = currentIndex / playerGrid.columns
        if col == 0 {
          let targetRow = min(row, storageGrid.rows - 1)
          let targetIndex = targetRow * storageGrid.columns + (storageGrid.columns - 1)
          storageGrid.setSelected(targetIndex)
          focusedGrid = .storage
          UISound.navigate()
          return true
        }
      }
    case .storage:
      if isRight {
        // Storage grid is on the left now: at right edge, jump to player grid's leftmost column
        let currentIndex = storageGrid.selectedIndex
        let col = currentIndex % storageGrid.columns
        let row = currentIndex / storageGrid.columns
        if col == storageGrid.columns - 1 {
          let targetRow = min(row, playerGrid.rows - 1)
          let targetIndex = targetRow * playerGrid.columns + 0
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
      case .storage: return storageGrid.selectedIndex
      }
    }()

    let data: SlotData? = {
      switch focusedGrid {
      case .player: return playerGrid.getSlotData(at: selectedIndex)
      case .storage: return storageGrid.getSlotData(at: selectedIndex)
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

  private func getSelectedItemInFocusedGrid() -> Item? {
    switch focusedGrid {
    case .player:
      return playerGrid.getSlotData(at: playerGrid.selectedIndex)?.item
    case .storage:
      return storageGrid.getSlotData(at: storageGrid.selectedIndex)?.item
    }
  }

  private func enterMoveModeFromFocusedSelection() {
    switch focusedGrid {
    case .player:
      let idx = playerGrid.selectedIndex
      if let data = playerGrid.getSlotData(at: idx), data.item != nil {
        movingSource = (.player, idx)
        playerGrid.setMovingModeActive(true)
        isMoveModeActive = true
        UISound.select()
      }
    case .storage:
      let idx = storageGrid.selectedIndex
      if let data = storageGrid.getSlotData(at: idx), data.item != nil {
        movingSource = (.storage, idx)
        storageGrid.setMovingModeActive(true)
        isMoveModeActive = true
        UISound.select()
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

  // MARK: - Sample data

  private func setupPlayerSlots() {
    let totalSlots = playerGrid.columns * playerGrid.rows
    var data: [SlotData?] = Array(repeating: nil, count: totalSlots)
    let items: [(Item, Int?)] = [
      (.knife, nil),
      (.glock17, 15),
      (.handgunAmmo, 48),
      (.morphine, nil),
      (.metroKey, nil),
      (.handgunAmmo, 30),
      (.morphine, nil),
      (.knife, nil),
    ]
    for (i, pair) in items.enumerated() where i < totalSlots {
      data[i] = SlotData(item: pair.0, quantity: pair.1)
    }
    playerGrid.setSlotData(data)
  }

  private func setupStorageSlots() {
    let totalSlots = storageGrid.columns * storageGrid.rows
    var data: [SlotData?] = Array(repeating: nil, count: totalSlots)
    let items: [(Item, Int?)] = [
      (.handgunAmmo, 99),
      (.morphine, nil),
      (.knife, nil),
      (.glock17, 15),
      (.handgunAmmo, 24),
      (.morphine, nil),
    ]
    for (i, pair) in items.enumerated() where i < totalSlots {
      data[i] = SlotData(item: pair.0, quantity: pair.1)
    }
    storageGrid.setSlotData(data)
  }
}
