final class PickupView: RenderLoop {
  /// Sliding behavior for the item animation
  enum SlidingBehavior {
    case slideIn  // Only slide in from bottom when shown
    case slideOut  // Only slide out to bottom when transitioning to grid
    case slideInAndOut  // Slide in from bottom, then slide out to bottom when transitioning
  }

  private var promptList = PromptList(.continue)
  private var slotGrid: ItemSlotGrid
  private let ambientBackground = GLScreenEffect("Effects/AmbientBackground")

  // Mouse tracking
  private var lastMouseX: Double = 0
  private var lastMouseY: Double = 0

  // Item description component
  private let itemDescriptionView = ItemDescriptionView()

  // Picked up item
  let pickedUpItem: Item
  let pickedUpQuantity: Int

  // Callback when item is placed
  var onItemPlaced: ((Int, Item, Int) -> Void)?  // slotIndex, item, quantity
  var onCancel: (() -> Void)?

  // Dismissal delay state
  private var isDismissing: Bool = false
  private var dismissTimer: Float = 0.0
  private let dismissDelay: Float = 0.3  // 300ms
  private var pendingPlacement: (slotIndex: Int, item: Item, quantity: Int)? = nil

  // View state: showing item inspection or slot grid
  private enum ViewState {
    case showingItem
    case showingGrid
  }
  private var viewState: ViewState = .showingItem

  // 3D model rendering (similar to ItemView)
  private var meshInstances: [MeshInstance] = []
  private var camera: ItemInspectionCamera
  private let light = Light.itemInspection
  private let fillLight = Light.itemInspectionFill
  private let loadingProgress = LoadingProgress()

  // Framebuffer for 3D item rendering
  private var itemFramebufferID: UInt64? = nil
  private var itemFramebufferSize: Size {
    return Engine.viewportSize
  }
  private let itemFramebufferScale: Float = 1.0

  // Framebuffer for slot grid rendering (for fade effect)
  private var gridFramebufferID: UInt64? = nil
  private var gridFramebufferSize: Size {
    return Engine.viewportSize
  }
  private let gridFramebufferScale: Float = 1.0

  // Sliding animation configuration
  private var slidingBehavior: SlidingBehavior = .slideInAndOut
  private var isSlidingIn: Bool = false
  private var isSlidingOut: Bool = false
  private var slideTimer: Float = 0.0
  private let slideDuration: Float = 0.5  // 500ms
  private let slideInEasing: Easing = .easeOutCubic
  private let slideOutEasing: Easing = .easeInCubic
  private var itemSlideOffset: Float = 0.0  // Y offset for sliding animation

  // Grid fade animation
  private var gridOpacity: Float = 0.0
  private var isFadingInGrid: Bool = false
  private let gridFadeDuration: Float = 0.25  // Half of slide-out duration (fades in from 50% to 100%)

  init(item: Item, quantity: Int = 1, slidingBehavior: SlidingBehavior = .slideInAndOut) {
    self.slidingBehavior = slidingBehavior
    self.pickedUpItem = item
    self.pickedUpQuantity = quantity
    self.camera = ItemInspectionCamera(distance: item.inspectionDistance)

    slotGrid = ItemSlotGrid(
      columns: 4,
      rows: 4,
      slotSize: 80.0,
      spacing: 3.0
    )
    // Disable menu and moving mode for placement
    slotGrid.showMenuOnSelection = false
    slotGrid.allowsMoving = false

    // Set inventory on slot grid
    slotGrid.inventory = Inventory.player1

    // Enable placement mode
    slotGrid.setPlacementMode(item: pickedUpItem, quantity: pickedUpQuantity)
    slotGrid.onPlacementConfirmed = { [weak self] slotIndex, item, quantity in
      guard let self = self else { return }
      // Start dismissal delay
      self.isDismissing = true
      self.dismissTimer = 0.0
      self.pendingPlacement = (slotIndex, item, quantity)
    }
    slotGrid.onPlacementCancelled = { [weak self] in
      self?.cleanupFramebuffer()
      self?.onCancel?()
    }

    // Set item description to always show picked up item
    itemDescriptionView.title = pickedUpItem.name
    itemDescriptionView.descriptionText = pickedUpItem.description ?? ""

    // Select first empty slot, or first slot if none
    selectFirstEmptySlot()

    // Center the grid on X axis, slightly above center on Y
    recenterGrid()

    // Create framebuffers for 3D item and slot grid rendering
    if let renderer = Engine.shared.renderer {
      itemFramebufferID = renderer.createFramebuffer(size: itemFramebufferSize, scale: itemFramebufferScale)
      gridFramebufferID = renderer.createFramebuffer(size: gridFramebufferSize, scale: gridFramebufferScale)
    }

    // Start async loading if model is available
    if let modelPath = item.modelPath {
      Task { await loadModelAsync(path: modelPath) }
    }

    // Start with item slide offset based on sliding behavior
    switch slidingBehavior {
    case .slideIn, .slideInAndOut:
      // Start below screen (off-screen, will slide in after fade)
      // Framebuffer uses ortho(0, W, H, 0) where Y=0 is bottom, Y=H is top
      // So positive Y offset moves down (below screen)
      itemSlideOffset = Float(Engine.viewportSize.height)
    case .slideOut:
      // Start on-screen
      itemSlideOffset = 0.0
    }
  }

  /// Start the slide-in animation (called after fade from black completes)
  func startSlideInAnimation() {
    guard slidingBehavior == .slideIn || slidingBehavior == .slideInAndOut else { return }
    isSlidingIn = true
    slideTimer = 0.0
    // Start below screen (positive Y offset moves down in framebuffer coordinate system)
    itemSlideOffset = Float(Engine.viewportSize.height)
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
        let rightMargin: Float = 152
        return Float(Engine.viewportSize.width) - totalSize.width - rightMargin
      }
    }()
    let y: Float = (Float(Engine.viewportSize.height) - totalSize.height) * 0.5 + 64
    let gridPosition = Point(x, y)
    slotGrid.setPosition(gridPosition)
  }

  /// Select the first empty slot, or first slot if none are empty
  private func selectFirstEmptySlot() {
    let totalSlots = slotGrid.columns * slotGrid.rows
    for i in 0..<totalSlots {
      if let slotData = slotGrid.getSlotData(at: i), slotData.isEmpty {
        slotGrid.setSelected(i)
        return
      }
    }
    // No empty slots, just select the first one
    slotGrid.setSelected(0)
  }

  /// Load 3D model asynchronously with progress updates
  private func loadModelAsync(path: String) async {
    do {
      meshInstances = try await MeshInstance.loadAsync(
        path: path,
        onSceneProgress: { progress in
          Task { @MainActor in
            self.loadingProgress.updateSceneProgress(progress)
          }
        },
        onTextureProgress: { current, total, progress in
          Task { @MainActor in
            self.loadingProgress.updateTextureProgress(current: current, total: total, progress: progress)
          }
        }
      )

      await MainActor.run {
        self.loadingProgress.markCompleted()
      }
    } catch {
      print("Failed to load model: \(error)")
      await MainActor.run {
        self.loadingProgress.markCompleted()
      }
    }
  }

  /// Transition from item view to grid view
  private func transitionToGrid() {
    guard viewState == .showingItem else { return }

    // Handle slide-out animation if needed
    if slidingBehavior == .slideOut || slidingBehavior == .slideInAndOut {
      isSlidingOut = true
      slideTimer = 0.0
      itemSlideOffset = 0.0  // Start from on-screen
      UISound.select()
    } else {
      // No slide-out, just switch immediately
      viewState = .showingGrid
      promptList = PromptList(.confirmCancel)
      UISound.select()
      itemSlideOffset = 0.0
    }
  }

  func update(window: Window, deltaTime: Float) {
    // Update camera (for smooth rotation)
    if viewState == .showingItem {
      camera.update(deltaTime: deltaTime)
    }

    // Handle slide-in animation (item slides up from bottom after fade)
    if isSlidingIn {
      slideTimer += deltaTime
      let progress = min(slideTimer / slideDuration, 1.0)
      let easedProgress = slideInEasing.apply(progress)
      // Slide item up from below screen (positive Y) to on-screen (Y=0)
      // Framebuffer uses ortho(0, W, H, 0) where Y=0 is bottom, Y=H is top
      // So positive Y offset moves down (below screen), Y=0 is on-screen at bottom
      let startOffset = Float(Engine.viewportSize.height)
      itemSlideOffset = startOffset + (0.0 - startOffset) * easedProgress

      if progress >= 1.0 {
        isSlidingIn = false
        itemSlideOffset = 0.0  // Fully on-screen (at bottom)
      }
    }

    // Handle slide-out animation (item slides down to bottom when transitioning to grid)
    if isSlidingOut {
      slideTimer += deltaTime
      let progress = min(slideTimer / slideDuration, 1.0)
      let easedProgress = slideOutEasing.apply(progress)
      // Slide item down from on-screen (Y=0) to below screen (positive Y)
      let endOffset = Float(Engine.viewportSize.height)
      itemSlideOffset = 0.0 + (endOffset - 0.0) * easedProgress

      // Switch to grid view halfway through the animation (at 50% progress)
      if progress >= 0.5 && viewState == .showingItem {
        viewState = .showingGrid
        promptList = PromptList(.confirmCancel)
        // Start fading in the grid
        isFadingInGrid = true
        gridOpacity = 0.0
      }

      if progress >= 1.0 {
        // Animation complete
        isSlidingOut = false
        itemSlideOffset = endOffset  // Fully off-screen below
      }
    }

    // Handle grid fade-in animation
    if isFadingInGrid {
      // Calculate fade progress from 50% to 100% of slide-out animation
      let fadeStartProgress: Float = 0.5
      let slideProgress = slideTimer / slideDuration
      let fadeRange = 1.0 - fadeStartProgress
      let fadeProgress = max(0.0, (slideProgress - fadeStartProgress) / fadeRange)
      let clampedProgress = min(fadeProgress, 1.0)
      let easedProgress = slideOutEasing.apply(clampedProgress)
      gridOpacity = easedProgress

      if fadeProgress >= 1.0 {
        isFadingInGrid = false
        gridOpacity = 1.0
      }
    } else if viewState == .showingGrid {
      // Keep grid at full opacity when not fading
      gridOpacity = 1.0
    }

    if viewState == .showingGrid {
      recenterGrid()

      // Handle dismissal delay
      if isDismissing {
        dismissTimer += deltaTime
        if dismissTimer >= dismissDelay {
          // Delay complete, actually dismiss
          cleanupFramebuffer()
          if let placement = pendingPlacement {
            onItemPlaced?(placement.slotIndex, placement.item, placement.quantity)
          }
          isDismissing = false
          dismissTimer = 0.0
          pendingPlacement = nil
        }
      } else {
        // Update slot grid (this now handles placement blink animation)
        slotGrid.update(deltaTime: deltaTime)
      }
    }
  }

  func onKeyPressed(window: Window, key: Keyboard.Key, scancode: Int32, mods: Keyboard.Modifier) {
    // Disable input while dismissing
    if isDismissing {
      return
    }

    // Disable input while sliding in or out
    if isSlidingIn || isSlidingOut {
      return
    }

    // Handle item view state
    if viewState == .showingItem {
      switch key {
      case .f, .space, .enter, .numpadEnter:
        // Continue to grid view
        transitionToGrid()
        return
      case .escape:
        // Cancel pickup
        cleanupFramebuffer()
        UISound.cancel()
        onCancel?()
        return
      default:
        break
      }
      return
    }

    // Handle grid view state
    // Let ItemSlotGrid handle navigation and placement (placement mode handles F/space/enter/escape)
    if slotGrid.handleKey(key) {
      return
    }
  }

  func onMouseMove(window: Window, x: Double, y: Double) {
    // Disable input while dismissing or in item view
    if isDismissing || viewState == .showingItem {
      return
    }
    lastMouseX = x
    lastMouseY = y

    // Flip Y coordinate to match screen coordinates (top-left origin)
    let mousePosition = Point(Float(x), Float(Engine.viewportSize.height) - Float(y))
    slotGrid.handleMouseMove(at: mousePosition)
  }

  func onMouseButton(window: Window, button: Mouse.Button, state: ButtonState, mods: Keyboard.Modifier) {
    // No-op
  }

  func onMouseButtonPressed(window: Window, button: Mouse.Button, mods: Keyboard.Modifier) {
    // Disable input while dismissing
    if isDismissing {
      return
    }

    // Disable input while sliding in or out
    if isSlidingIn || isSlidingOut {
      return
    }

    // Handle item view state
    if viewState == .showingItem {
      if button == .left {
        // Continue to grid view
        transitionToGrid()
      } else if button == .right {
        // Cancel pickup
        cleanupFramebuffer()
        UISound.cancel()
        onCancel?()
      }
      return
    }

    // Handle grid view state
    let mousePosition = Point(Float(lastMouseX), Float(Engine.viewportSize.height) - Float(lastMouseY))

    if button == .left {
      // Select slot and try to place
      if let slotIndex = slotGrid.slotIndex(at: mousePosition) {
        slotGrid.setSelected(slotIndex)
        // Try to place - check if slot is empty
        if let slotData = slotGrid.getSlotData(at: slotIndex), slotData.isEmpty {
          // Slot is empty, place the item
          if let item = slotGrid.placementItem {
            UISound.select()
            // Start dismissal delay
            isDismissing = true
            dismissTimer = 0.0
            pendingPlacement = (slotIndex, item, slotGrid.placementQuantity)
          }
        } else {
          // Slot is occupied, play error sound
          UISound.error()
        }
      }
    } else if button == .right {
      // Cancel pickup
      cleanupFramebuffer()
      UISound.cancel()
      onCancel?()
    }
  }

  func onScroll(window: Window, xOffset: Double, yOffset: Double) {
    // No-op
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

    if viewState == .showingItem {
      // Draw 3D item view (or sliding item framebuffer during slide-in)
      if isSlidingIn || isSlidingOut || itemSlideOffset != 0.0 {
        // Draw framebuffer with slide offset (when sliding in/out)
        drawItemFramebuffer()
      } else {
        // Draw live 3D item view (when fully on-screen)
        drawItemView()
      }
    } else {
      // Draw slot grid view
      // Draw the 3D item framebuffer sliding out if transitioning
      if isSlidingOut || itemSlideOffset > 0.0 {
        drawItemFramebuffer()
      }

      // Render slot grid to framebuffer, then draw with opacity
      drawGridWithFade()
    }

    // Draw item description
    itemDescriptionView.draw()

    // Draw the prompt list
    promptList.draw()
  }

  /// Draw the 3D item view (renders directly to screen when not sliding, or to framebuffer when sliding)
  private func drawItemView() {
    guard let renderer = Engine.shared.renderer else { return }

    // If sliding in, render to framebuffer and draw with offset
    if isSlidingIn || itemSlideOffset != 0.0 {
      guard let framebufferID = itemFramebufferID else { return }

      // Render 3D model to framebuffer
      renderer.beginFramebuffer(framebufferID)
      renderer.setClearColor(.clear)

      // Draw 3D model if available
      if !meshInstances.isEmpty {
        let aspectRatio = Float(itemFramebufferSize.width) / Float(itemFramebufferSize.height)
        let projection = GLMath.perspective(45.0, aspectRatio, 0.001, 1000.0)
        let view = camera.getViewMatrix()
        let modelMatrix = camera.getModelMatrix()

        // Draw all mesh instances
        meshInstances.forEach { meshInstance in
          let combinedModelMatrix = modelMatrix * meshInstance.transformMatrix
          meshInstance.draw(
            projection: projection,
            view: view,
            modelMatrix: combinedModelMatrix,
            cameraPosition: camera.position,
            lightDirection: light.direction,
            lightColor: light.color,
            lightIntensity: light.intensity,
            fillLightDirection: fillLight.direction,
            fillLightColor: fillLight.color,
            fillLightIntensity: fillLight.intensity,
            diffuseOnly: false
          )
        }
      }

      renderer.endFramebuffer()

      // Draw the framebuffer on screen with slide offset
      let screenRect = Rect(
        x: 0,
        y: itemSlideOffset,
        width: Float(Engine.viewportSize.width),
        height: Float(Engine.viewportSize.height)
      )
      renderer.drawFramebuffer(framebufferID, in: screenRect, transform: nil, alpha: 1.0)
    } else {
      // Draw directly to screen (no offset needed, no framebuffer)
      if !meshInstances.isEmpty {
        let aspectRatio = Float(Engine.viewportSize.width) / Float(Engine.viewportSize.height)
        let projection = GLMath.perspective(45.0, aspectRatio, 0.001, 1000.0)
        let view = camera.getViewMatrix()
        let modelMatrix = camera.getModelMatrix()

        // Draw all mesh instances
        meshInstances.forEach { meshInstance in
          let combinedModelMatrix = modelMatrix * meshInstance.transformMatrix
          meshInstance.draw(
            projection: projection,
            view: view,
            modelMatrix: combinedModelMatrix,
            cameraPosition: camera.position,
            lightDirection: light.direction,
            lightColor: light.color,
            lightIntensity: light.intensity,
            fillLightDirection: fillLight.direction,
            fillLightColor: fillLight.color,
            fillLightIntensity: fillLight.intensity,
            diffuseOnly: false
          )
        }
      }
    }
  }

  /// Draw the item framebuffer during transition (renders to framebuffer first, then draws it)
  private func drawItemFramebuffer() {
    guard let renderer = Engine.shared.renderer, let framebufferID = itemFramebufferID else { return }

    // First, render the 3D model to the framebuffer
    renderer.beginFramebuffer(framebufferID)
    renderer.setClearColor(.clear)

    // Draw 3D model if available
    if !meshInstances.isEmpty {
      let aspectRatio = Float(itemFramebufferSize.width) / Float(itemFramebufferSize.height)
      let projection = GLMath.perspective(45.0, aspectRatio, 0.001, 1000.0)
      let view = camera.getViewMatrix()
      let modelMatrix = camera.getModelMatrix()

      // Draw all mesh instances
      meshInstances.forEach { meshInstance in
        let combinedModelMatrix = modelMatrix * meshInstance.transformMatrix
        meshInstance.draw(
          projection: projection,
          view: view,
          modelMatrix: combinedModelMatrix,
          cameraPosition: camera.position,
          lightDirection: light.direction,
          lightColor: light.color,
          lightIntensity: light.intensity,
          fillLightDirection: fillLight.direction,
          fillLightColor: fillLight.color,
          fillLightIntensity: fillLight.intensity,
          diffuseOnly: false
        )
      }
    }

    renderer.endFramebuffer()

    // Then draw the framebuffer on screen with slide offset
    let screenRect = Rect(
      x: 0,
      y: itemSlideOffset,
      width: Float(Engine.viewportSize.width),
      height: Float(Engine.viewportSize.height)
    )
    renderer.drawFramebuffer(framebufferID, in: screenRect, transform: nil, alpha: 1.0)
  }

  /// Draw the slot grid with fade effect (renders to framebuffer, then draws with opacity)
  private func drawGridWithFade() {
    guard let renderer = Engine.shared.renderer, let framebufferID = gridFramebufferID else {
      // Fallback: draw directly if framebuffer not available
      slotGrid.draw()
      return
    }

    // Render slot grid to framebuffer
    renderer.beginFramebuffer(framebufferID)
    renderer.setClearColor(.clear)

    // Draw the slot grid (this now draws the blinking placement item)
    slotGrid.draw()

    renderer.endFramebuffer()

    // Draw the framebuffer with opacity
    let screenRect = Rect(
      x: 0,
      y: 0,
      width: Float(Engine.viewportSize.width),
      height: Float(Engine.viewportSize.height)
    )
    renderer.drawFramebuffer(framebufferID, in: screenRect, transform: nil, alpha: gridOpacity)
  }

  /// Clean up framebuffers (call before dismissing)
  private func cleanupFramebuffer() {
    if let renderer = Engine.shared.renderer {
      if let framebufferID = itemFramebufferID {
        renderer.destroyFramebuffer(framebufferID)
        itemFramebufferID = nil
      }
      if let framebufferID = gridFramebufferID {
        renderer.destroyFramebuffer(framebufferID)
        gridFramebufferID = nil
      }
    }
  }
}
