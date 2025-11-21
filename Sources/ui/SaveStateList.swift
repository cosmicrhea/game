import struct GLFW.Keyboard
import struct GLFW.Mouse

@MainActor
final class SaveStateList {
  private let scrollView: ScrollView
  private var saveStates: [SaveState?] = Array(repeating: nil, count: SaveState.numberOfSaveSlots)
  private let rowHeight: Float = 76
  private let rowSpacing: Float = 1
  private let horizontalInset: Float = 16
  private let contentPadding: Float = 18
  private var selectedIndex: Int = 0
  private var pendingFocusRect: Rect?
  private var rowFrames: [Rect] = []

  private let focusRing = FocusRing()

  var isFocused: Bool = true

  var onSelectionChanged: ((SaveState?) -> Void)?
  var onActivate: ((SaveState?) -> Void)?

  init(frame: Rect) {
    scrollView = ScrollView(frame: frame, contentSize: Size(frame.size.width, frame.size.height))
    scrollView.cornerRadius = 12
    scrollView.backgroundColor = Color.black.withAlphaComponent(0.35)
    scrollView.mouseDragCanScroll = true
    scrollView.showsScrollbar = true
    scrollView.autohideScrollbars = false
    scrollView.scrollbarPosition = .outside
    scrollView.onDrawContent = { [weak self] origin in
      self?.drawContent(origin: origin)
    }
    focusRing.cornerRadius = 3
  }

  func setFrame(_ frame: Rect) {
    scrollView.frame = frame
    updateContentSize()
  }

  func setSaveStates(_ states: [SaveState]) {
    var filled = Array<SaveState?>(repeating: nil, count: SaveState.numberOfSaveSlots)
    for state in states {
      let index = max(0, min(state.slotIndex, SaveState.numberOfSaveSlots - 1))
      filled[index] = state
    }
    saveStates = filled
    selectedIndex = min(max(0, selectedIndex), max(0, saveStates.count - 1))
    updateContentSize()
    scrollToSelectedRow()
  }

  func update(deltaTime: Float) {
    scrollView.update(deltaTime: deltaTime)
  }

  func draw() {
    pendingFocusRect = nil
    scrollView.draw()

    if isFocused, let focusRect = pendingFocusRect {
      guard let context = GraphicsContext.current else { return }
      context.save()
      context.clip(to: scrollView.frame)
      focusRing.draw(around: focusRect, intensity: 1.0, padding: 0)
      context.restore()
    }
  }

  func handleScroll(xOffset: Double, yOffset: Double, mouse: Point) {
    scrollView.handleScroll(xOffset: xOffset, yOffset: yOffset, mouse: mouse)
  }

  @discardableResult
  func handleMouseDown(at position: Point) -> Bool {
    return scrollView.handleMouseDown(at: position)
  }

  func handleMouseUp() {
    scrollView.handleMouseUp()
  }

  func handleMouseMove(at position: Point) {
    scrollView.handleMouseMove(at: position)
  }

  @discardableResult
  func handleMouseClick(at position: Point) -> Bool {
    guard scrollView.contains(position) else { return false }

    if let index = rowFrames.firstIndex(where: { $0.contains(position) }) {
      if index == selectedIndex {
        activateSelected()
      } else {
        setSelectedIndex(index)
      }
      return true
    }

    return false
  }

  func handleKey(_ key: Keyboard.Key) -> Bool {
    guard !saveStates.isEmpty else { return false }

    switch key {
    case .up, .w:
      setSelectedIndex(selectedIndex > 0 ? selectedIndex - 1 : saveStates.count - 1)
      return true
    case .down, .s:
      setSelectedIndex(selectedIndex < saveStates.count - 1 ? selectedIndex + 1 : 0)
      return true
    case .enter, .numpadEnter, .space, .f:
      activateSelected()
      return true
    default:
      return false
    }
  }

  func setFocused(_ focused: Bool) {
    isFocused = focused
  }

  private func activateSelected() {
    guard saveStates.indices.contains(selectedIndex) else { return }
    onActivate?(saveStates[selectedIndex])
  }

  private func setSelectedIndex(_ index: Int) {
    let clamped = max(0, min(index, max(0, saveStates.count - 1)))
    guard clamped != selectedIndex else {
      onSelectionChanged?(saveStates.indices.contains(clamped) ? saveStates[clamped] : nil)
      return
    }
    selectedIndex = clamped
    onSelectionChanged?(saveStates.indices.contains(clamped) ? saveStates[clamped] : nil)
    scrollToSelectedRow()
  }

  private func scrollToSelectedRow() {
    guard !saveStates.isEmpty else { return }
    let contentHeight = calculatedContentHeight()
    let viewportHeight = scrollView.frame.size.height
    guard viewportHeight > 0 else { return }  // Don't scroll if frame not set yet
    let selectedTopFromTop = contentPadding + Float(selectedIndex) * (rowHeight + rowSpacing)
    let maxOffset = max(0, contentHeight - viewportHeight)

    // In Y-flipped coordinates: 0 = bottom, maxOffset = top
    // Calculate ideal offset to center the row (same as StorageList)
    let idealOffset = contentHeight - selectedTopFromTop - rowHeight - (viewportHeight - rowHeight) * 0.5

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

  private func updateContentSize() {
    let height = max(scrollView.frame.size.height, calculatedContentHeight())
    scrollView.contentSize = Size(scrollView.frame.size.width, height)
  }

  private func calculatedContentHeight() -> Float {
    let rows = Float(max(saveStates.count, 1))
    let totalSpacing = rowSpacing * max(0, rows - 1)
    return rows * rowHeight + totalSpacing + contentPadding * 2
  }

  private func drawContent(origin: Point) {
    rowFrames.removeAll(keepingCapacity: true)

    let contentHeight = calculatedContentHeight()
    let startY = origin.y + contentHeight - contentPadding - rowHeight
    let rowWidth = scrollView.frame.size.width - horizontalInset * 2

    for (index, state) in saveStates.enumerated() {
      let rowY = startY - Float(index) * (rowHeight + rowSpacing)
      let rowRect = Rect(
        x: origin.x + horizontalInset,
        y: rowY,
        width: rowWidth,
        height: rowHeight
      )
      rowFrames.append(rowRect)

      let isSelected = index == selectedIndex
      SaveStateRow(slotIndex: index, state: state).draw(in: rowRect, isSelected: isSelected)

      if isSelected {
        pendingFocusRect = rowRect
      }
    }
  }
}
