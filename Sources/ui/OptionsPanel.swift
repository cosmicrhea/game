/// Protocol for focusable, mouse/keyboard-driven option controls (e.g., Slider, Picker).
@MainActor
public protocol OptionsControl: AnyObject {
  var frame: Rect { get set }
  var isFocused: Bool { get set }
  // Controls like section headers can opt-out of keyboard focus
  var isFocusable: Bool { get }
  func draw()
  @discardableResult func handleKey(_ key: Keyboard.Key) -> Bool
  @discardableResult func handleMouseDown(at position: Point) -> Bool
  func handleMouseMove(at position: Point)
  func handleMouseUp()
}

extension OptionsControl {
  public var isFocusable: Bool { true }
}

/// Optional behavior for controls that support an Alt-click action (e.g., reset to default)
@MainActor
public protocol AltClickable: AnyObject {
  func altClick(at position: Point)
}

/// Base panel for options pages. Handles layout, focus, and input dispatch.
@MainActor
public class OptionsPanel: Screen {
  /// A button row control that triggers an action when clicked or when action keys are pressed.
  private final class ButtonRow: OptionsControl {
    var frame: Rect
    var isFocused: Bool = false
    var action: () -> Void

    init(frame: Rect = .zero, action: @escaping () -> Void) {
      self.frame = frame
      self.action = action
    }

    func draw() {
      // Button rows don't draw anything - they're just interactive labels
      // The label is drawn by the OptionsPanel
    }

    @discardableResult
    func handleKey(_ key: Keyboard.Key) -> Bool {
      guard isFocused else { return false }
      switch key {
      case .f, .space, .enter, .numpadEnter:
        action()
        UISound.select()
        return true
      default:
        return false
      }
    }

    @discardableResult
    func handleMouseDown(at position: Point) -> Bool {
      guard frame.contains(position) else { return false }
      action()
      UISound.select()
      return true
    }

    func handleMouseMove(at position: Point) {}
    func handleMouseUp() {}
  }

  struct Row {
    let label: String
    let control: OptionsControl

    /// Convenience initializer for button rows that trigger an action.
    @MainActor
    init(button label: String, action: @escaping () -> Void) {
      self.label = label
      self.control = ButtonRow(action: action)
    }

    /// Standard initializer for rows with a control.
    init(label: String, control: OptionsControl) {
      self.label = label
      self.control = control
    }
  }

  // Layout configuration
  var sidePadding: Float = 20
  var topMargin: Float = 96
  var bottomMargin: Float = 20
  var rowHeight: Float = 60
  var labelStyle: TextStyle = TextStyle.menuItem.withFontSize(22).withColor(.gray300)
  var rightPaneRatio: Float = 0.70

  // Internal state
  private(set) var rows: [Row] = []
  public var panelRect: Rect = .zero
  public var rowRects: [Rect] = []
  private var focusedIndex: Int? { didSet { updateFocus() } }
  private var focusViaKeyboard: Bool = false

  // MARK: - Configuration
  func setRows(_ rows: [Row]) {
    self.rows = rows
  }

  // MARK: - Rendering
  override func draw() {
    layout()

    for (i, row) in rows.enumerated() {
      guard i < rowRects.count else { continue }
      let r = rowRects[i]
      // Draw focus border only when navigating via keyboard
      if focusViaKeyboard, let focusedIndex, focusedIndex == i, rows[i].control.isFocusable {
        let focusRect = Rect(x: r.origin.x - 8, y: r.origin.y - 6, width: r.size.width + 16, height: r.size.height + 12)
        focusRect.frame(with: Color.gray500.withAlphaComponent(0.35), lineWidth: 2)
      }
      let labelSize = row.label.size(with: labelStyle)
      let labelY = r.origin.y + (rowHeight - labelSize.height) * 0.5
      row.label.draw(at: Point(r.origin.x, labelY), style: labelStyle, anchor: .bottomLeft)
      row.control.draw()
    }
  }

  // MARK: - Input
  func handleKey(_ key: Keyboard.Key) -> Bool {
    focusViaKeyboard = true
    switch key {
    case .w, .up:
      // Move selection visually upward (previous row, lower index)
      moveFocus(-1)
      return true
    case .s, .down:
      // Move selection visually downward (next row, higher index)
      moveFocus(+1)
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
    focusViaKeyboard = false

    // End any ongoing drags before starting a new one to avoid cross-control dragging
    rows.forEach { $0.control.handleMouseUp() }

    for (i, row) in rows.enumerated() {
      // Alt-click support: if Alt is pressed and control supports it and the click is within control frame, trigger it
      if mods.contains(.alt), let alt = row.control as? AltClickable, i < rowRects.count {
        if row.control.frame.contains(p) {
          alt.altClick(at: p)
          focusedIndex = i
          UISound.select()
          return
        }
      }
      // If the click lands anywhere inside the row rect and the control is a Switch,
      // toggle it even if the click is on the label area.
      if rowRects.indices.contains(i), rowRects[i].contains(p), let sw = row.control as? Switch {
        focusedIndex = i
        sw.isOn.toggle()
        UISound.select()
        return
      }
      // If the click lands anywhere inside the row rect and the control is a ButtonRow,
      // trigger the action even if the click is on the label area.
      if rowRects.indices.contains(i), rowRects[i].contains(p), let buttonRow = row.control as? ButtonRow {
        focusedIndex = i
        buttonRow.action()
        UISound.select()
        return
      }
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
    focusViaKeyboard = false
    rows.forEach { $0.control.handleMouseMove(at: p) }
  }

  override func onMouseButtonReleased(window: Window, button: Mouse.Button, mods: Keyboard.Modifier) {
    guard button == .left else { return }
    rows.forEach { $0.control.handleMouseUp() }
  }

  // MARK: - Private
  private func moveFocus(_ delta: Int) {
    guard !rows.isEmpty else {
      focusedIndex = nil
      return
    }

    // Gather focusable indices
    let focusable = rows.enumerated().compactMap { (i, r) in r.control.isFocusable ? i : nil }
    guard !focusable.isEmpty else {
      focusedIndex = nil
      return
    }

    UISound.navigate()

    // Initialize focus on first focusable row if none selected yet
    if focusedIndex == nil {
      focusedIndex = focusable.first
      return
    }

    // Find next focusable index in the given direction
    var idx = focusedIndex!
    for _ in 0..<rows.count {
      idx = (idx + delta + rows.count) % rows.count
      if rows[idx].control.isFocusable {
        focusedIndex = idx
        return
      }
    }
  }

  private func updateFocus() {
    for (i, row) in rows.enumerated() {
      row.control.isFocused = (i == focusedIndex)
    }
  }

  public func layout() {
    let w = Float(Engine.viewportSize.width)
    let h = Float(Engine.viewportSize.height)

    let left = w * (1.0 - rightPaneRatio)
    let width = w * rightPaneRatio - 2 * sidePadding
    let bottom = bottomMargin
    let height = h - bottomMargin - topMargin
    panelRect = Rect(x: left + sidePadding, y: bottom, width: width, height: height)

    // Rows rects and control frames anchored to top of panelRect
    rowRects = rows.enumerated().map { (i, _) in
      Rect(
        x: panelRect.origin.x + 24, y: panelRect.maxY - Float(i + 1) * rowHeight, width: panelRect.size.width - 48,
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
