@MainActor
public final class ColorPicker: OptionsControl {
  public var frame: Rect
  public var isFocused: Bool = false

  public var color: Color {
    didSet {
      // Only update well and wheel if they're initialized (not during init)
      if !isInitializing {
        colorWell.color = color
        colorWheel.color = color
        onColorChanged?(color)
      }
    }
  }

  /// Called whenever `color` changes.
  public var onColorChanged: ((Color) -> Void)?

  private let colorWell: ColorWell
  private let colorWheel: ColorWheel
  private var isWheelVisible: Bool = false
  private var colorWellHeight: Float = 28
  private var colorWheelSize: Float = 200
  private var isInitializing: Bool = true

  public init(frame: Rect = .zero, color: Color = .white) {
    self.frame = frame
    // Initialize well and wheel first
    self.colorWell = ColorWell(frame: .zero, color: color)
    self.colorWheel = ColorWheel(frame: .zero, color: color)
    // Initialize color (didSet will skip updates because isInitializing is true)
    self.color = color
    // Set up callback after color is initialized
    self.colorWheel.onColorChanged = { [weak self] newColor in
      guard let self = self else { return }
      // Prevent infinite loop by checking if color actually changed
      if self.color != newColor {
        self.color = newColor
      }
    }
    // Mark initialization complete
    self.isInitializing = false
  }

  public func draw() {
    // Calculate color well frame (centered vertically, full width)
    let wellFrame = Rect(
      x: frame.origin.x,
      y: frame.origin.y + (frame.size.height - colorWellHeight) * 0.5,
      width: frame.size.width,
      height: colorWellHeight
    )
    colorWell.frame = wellFrame
    colorWell.draw()

    // Draw color wheel if visible - anchored bottom-right to top-left of well
    if isWheelVisible {
      let wheelFrame = Rect(
        x: wellFrame.origin.x - colorWheelSize,  // Left of well
        y: wellFrame.maxY - colorWheelSize,  // Above well (bottom-right of wheel at top-left of well)
        width: colorWheelSize,
        height: colorWheelSize
      )
      colorWheel.frame = wheelFrame
      colorWheel.draw()
    }
  }

  @discardableResult
  public func handleKey(_ key: Keyboard.Key) -> Bool { return false }

  @discardableResult
  public func handleMouseDown(at position: Point) -> Bool {
    let wellFrame = colorWell.frame
    
    // Calculate wheel frame (same as in draw)
    let wheelFrame = Rect(
      x: wellFrame.origin.x - colorWheelSize,
      y: wellFrame.maxY - colorWheelSize,
      width: colorWheelSize,
      height: colorWheelSize
    )
    
    // If wheel is visible, check clicks there first
    if isWheelVisible && wheelFrame.contains(position) {
      // Click is in the wheel area, forward it for interaction
      return colorWheel.handleMouseDown(at: position)
    }
    
    // If clicking the well, toggle wheel visibility
    if wellFrame.contains(position) {
      // Toggle wheel visibility
      isWheelVisible.toggle()
      return true
    }
    
    // Click outside both well and wheel - hide wheel if visible
    if isWheelVisible {
      isWheelVisible = false
    }
    
    return false
  }

  public func handleMouseMove(at position: Point) {
    // Only forward mouse moves when wheel is visible and being dragged
    if isWheelVisible {
      colorWheel.handleMouseMove(at: position)
    }
  }

  public func handleMouseUp() {
    // Only forward mouse up when wheel is visible
    // Don't hide wheel on mouse up - let user toggle it manually
    if isWheelVisible {
      colorWheel.handleMouseUp()
    }
  }
}

