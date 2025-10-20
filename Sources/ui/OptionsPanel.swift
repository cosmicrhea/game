


/// Protocol for focusable, mouse/keyboard-driven option controls (e.g., Slider, Picker).
@MainActor
public protocol OptionsControl: AnyObject {
  var frame: Rect { get set }
  var isFocused: Bool { get set }
  func draw()
  @discardableResult func handleKey(_ key: Keyboard.Key) -> Bool
  @discardableResult func handleMouseDown(at position: Point) -> Bool
  func handleMouseMove(at position: Point)
  func handleMouseUp()
}

/// Base panel for options pages. Handles layout, focus, and input dispatch.
@MainActor
class OptionsPanel: Screen {
  struct Row {
    let label: String
    let control: OptionsControl
  }

  // Layout configuration
  var sidePadding: Float = 20
  var contentTop: Float = 24
  var contentBottom: Float = 24
  var rowHeight: Float = 60
  var labelStyle: TextStyle = TextStyle.menuItem.withFontSize(22).withColor(.gray300)
  var rightPaneRatio: Float = 0.70

  // Internal state
  private(set) var rows: [Row] = []
  private var panelRect: Rect = .zero
  private var rowRects: [Rect] = []
  private var focusedIndex: Int? { didSet { updateFocus() } }

  // MARK: - Configuration
  func setRows(_ rows: [Row]) {
    self.rows = rows
  }

  // MARK: - Rendering
  override func draw() {
    layout()

    // No background; panel overlays directly on scene

    for (i, row) in rows.enumerated() {
      guard i < rowRects.count else { continue }
      let r = rowRects[i]
      let labelSize = row.label.size(with: labelStyle)
      let labelY = r.origin.y + (rowHeight - labelSize.height) * 0.5
      row.label.draw(at: Point(r.origin.x, labelY), style: labelStyle)
      row.control.draw()
    }
  }

  // MARK: - Input
  func handleKey(_ key: Keyboard.Key) -> Bool {
    switch key {
    case .w, .up:
      moveFocus(+1)
      return true
    case .s, .down:
      moveFocus(-1)
      return true
    default:
      break
    }
    if let i = focusedIndex, rows.indices.contains(i) {
      return rows[i].control.handleKey(key)
    }
    return false
  }

  override func onMouseButtonPressed(window: Window, button: Mouse.Button, mods: Keyboard.Modifier) {
    guard button == .left else { return }
    let p = mousePoint(window)
    guard panelRect.contains(p) else { return }

    // End any ongoing drags before starting a new one to avoid cross-control dragging
    rows.forEach { $0.control.handleMouseUp() }

    for (i, row) in rows.enumerated() {
      if row.control.handleMouseDown(at: p) {
        focusedIndex = i
        UISound.select()
        return
      }
    }
  }

  override func onMouseMove(window: Window, x: Double, y: Double) {
    let p = mousePoint(window)
    guard panelRect.contains(p) else { return }
    rows.forEach { $0.control.handleMouseMove(at: p) }
  }

  func onMouseButtonReleased(window: Window, button: Mouse.Button, mods: Keyboard.Modifier) {
    guard button == .left else { return }
    rows.forEach { $0.control.handleMouseUp() }
  }

  // MARK: - Private
  private func moveFocus(_ delta: Int) {
    if rows.isEmpty {
      focusedIndex = nil
      return
    }
    UISound.navigate()
    let current = focusedIndex ?? 0
    let next = (current + delta + rows.count) % rows.count
    focusedIndex = next
  }

  private func updateFocus() {
    for (i, row) in rows.enumerated() {
      row.control.isFocused = (i == focusedIndex)
    }
  }

  private func layout() {
    let w = Float(Engine.viewportSize.width)
    let h = Float(Engine.viewportSize.height)

    let left = w * (1.0 - rightPaneRatio)
    let width = w * rightPaneRatio - 2 * sidePadding
    let top = contentTop
    let height = h - contentTop - contentBottom
    panelRect = Rect(x: left + sidePadding, y: top, width: width, height: height)

    // Rows rects and control frames anchored to bottom of panelRect
    let totalRowsHeight = Float(rows.count) * rowHeight
    let startY = panelRect.maxY - totalRowsHeight
    rowRects = rows.enumerated().map { (i, _) in
      Rect(
        x: panelRect.origin.x + 24, y: startY + Float(i) * rowHeight, width: panelRect.size.width - 48,
        height: rowHeight)
    }

    for (i, r) in rowRects.enumerated() where rows.indices.contains(i) {
      let sliderWidth = r.size.width * 0.58
      let sliderX = r.origin.x + r.size.width - sliderWidth
      let sliderY = r.origin.y + (rowHeight - 36) * 0.5
      let controlFrame = Rect(x: sliderX, y: sliderY, width: sliderWidth, height: 36)
      rows[i].control.frame = controlFrame
    }
  }

  private func mousePoint(_ window: Window) -> Point {
    Point(Float(window.mouse.position.x), Float(Engine.viewportSize.height) - Float(window.mouse.position.y))
  }
}
