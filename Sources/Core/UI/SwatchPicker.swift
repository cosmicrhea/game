@MainActor
public final class SwatchPicker: OptionsControl {

  // MARK: - Public API

  public struct Swatch: Sendable, Equatable {
    public let name: String
    public let color: Color
    public init(_ name: String, _ color: Color) {
      self.name = name
      self.color = color
    }
  }

  public var frame: Rect
  public var isFocused: Bool = false

  /// Ordered swatches to display left-to-right
  public var swatches: [Swatch]

  /// Currently selected index
  public var selectedIndex: Int {
    didSet {
      selectedIndex = max(0, min(selectedIndex, max(0, swatches.count - 1)))
      if selectedIndex != oldValue {
        let sw = swatches[selectedIndex]
        Color.accent = sw.color
        onSelectionChanged?(sw)
      }
    }
  }

  /// Event fired whenever selection changes
  public var onSelectionChanged: ((Swatch) -> Void)?

  // Styling
  public var swatchDiameter: Float = 24
  public var swatchSpacing: Float = 14
  public var selectionRingWidth: Float = 3
  public var selectionDotDiameter: Float = 7
  public var labelStyle: TextStyle = TextStyle(fontName: "CreatoDisplay-Bold", fontSize: 14, color: .gray400)
  public var labelVerticalPadding: Float = 12
  public var labelToSwatchGap: Float = 8

  // MARK: - Init

  public init(frame: Rect = .zero, selectedIndex: Int = 0, swatches: [Swatch] = SwatchPicker.defaultSwatches()) {
    self.frame = frame
    self.swatches = swatches
    self.selectedIndex = max(0, min(selectedIndex, max(0, swatches.count - 1)))
    // Ensure initial size is reasonable
    let size = intrinsicSize()
    self.frame.size.width = size.width
    self.frame.size.height = size.height
    // Initialize from persisted config if present; otherwise set from selected swatch
    if let persisted = Self.loadAccentFromConfig() {
      Color.accent = persisted
      if let idx = swatches.firstIndex(where: { nearlyEqualColor($0.color, persisted) }) {
        self.selectedIndex = idx
      }
    } else if self.swatches.indices.contains(self.selectedIndex) {
      Color.accent = self.swatches[self.selectedIndex].color
    }
  }

  // MARK: - Layout

  public func intrinsicSize() -> Size {
    let count = Float(swatches.count)
    let width = count * swatchDiameter + max(0, count - 1) * swatchSpacing
    // Room for label below plus gap to swatches
    let height = labelAreaHeight + labelToSwatchGap + swatchDiameter
    return Size(width, height)
  }

  private static func loadAccentFromConfig() -> Color? {
    return Config.current.accentColor
  }

  private func nearlyEqualColor(_ a: Color, _ b: Color, eps: Float = 0.001) -> Bool {
    return abs(a.red - b.red) < eps && abs(a.green - b.green) < eps && abs(a.blue - b.blue) < eps
      && abs(a.alpha - b.alpha) < eps
  }

  // MARK: - Drawing

  public func draw() {
    // Keep frame sized to content
    let size = intrinsicSize()
    frame.size.width = size.width
    frame.size.height = size.height

    // Draw swatches row
    for (index, sw) in swatches.enumerated() {
      let rect = swatchRect(at: index)
      RoundedRect(rect, cornerRadius: swatchDiameter * 0.5).draw(color: sw.color)

      if index == selectedIndex {
        // Selection ring
        RoundedRect(rect, cornerRadius: swatchDiameter * 0.5).stroke(color: .white, lineWidth: selectionRingWidth)
        // Inner dot
        let dotSize = selectionDotDiameter
        let dotRect = Rect(
          x: rect.midX - dotSize * 0.5,
          y: rect.midY - dotSize * 0.5,
          width: dotSize,
          height: dotSize
        )
        RoundedRect(dotRect, cornerRadius: dotSize * 0.5).draw(color: .white)
      }
    }

    // Label under the row aligned to left
    if swatches.indices.contains(selectedIndex) {
      let swatch = swatches[selectedIndex]
      let selectedRect = swatchRect(at: selectedIndex)
      let labelPoint = labelPosition(for: swatch.name, under: selectedRect)
      swatch.name.draw(at: labelPoint, style: labelStyle, anchor: .topLeft)
    }
  }

  // MARK: - Input Handling

  @discardableResult
  public func handleKey(_ key: Keyboard.Key) -> Bool {
    guard isFocused else { return false }
    switch key {
    case .a, .left:
      moveSelection(-1)
      UISound.navigate()
      return true
    case .d, .right:
      moveSelection(+1)
      UISound.navigate()
      return true
    case .space, .enter, .numpadEnter:
      // Already selected; treat as handled to prevent button sounds elsewhere
      UISound.select()
      return true
    default:
      return false
    }
  }

  @discardableResult
  public func handleMouseDown(at position: Point) -> Bool {
    guard hitTest(position) else { return false }
    if let idx = swatchIndex(at: position) {
      selectedIndex = idx
      UISound.select()
      return true
    }
    return false
  }

  public func handleMouseMove(at position: Point) {}
  public func handleMouseUp() {}

  // MARK: - Helpers

  public func hitTest(_ p: Point) -> Bool {
    return frame.contains(p)
  }

  private func swatchIndex(at p: Point) -> Int? {
    for i in 0..<swatches.count {
      let rect = swatchRect(at: i)
      if rect.contains(p) { return i }
    }
    return nil
  }

  private func moveSelection(_ delta: Int) {
    let count = swatches.count
    guard count > 0 else { return }
    let newIndex = (selectedIndex + delta + count) % count
    selectedIndex = newIndex
  }

  private var swatchRowY: Float {
    frame.origin.y + labelAreaHeight + labelToSwatchGap
  }

  private func swatchRect(at index: Int) -> Rect {
    let x = frame.origin.x + Float(index) * (swatchDiameter + swatchSpacing)
    return Rect(x: x, y: swatchRowY, width: swatchDiameter, height: swatchDiameter)
  }

  private func labelPosition(for name: String, under rect: Rect) -> Point {
    let textSize = name.size(with: labelStyle)
    let desiredLeft = rect.midX - textSize.width * 0.5
    let minX = frame.origin.x
    let maxX = frame.origin.x + frame.size.width
    let availableMax = max(minX, maxX - textSize.width)
    let clampedX = min(max(desiredLeft, minX), availableMax)
    let labelTop = frame.origin.y + labelVerticalPadding + textSize.height
    let maxLabelTop = frame.origin.y + labelAreaHeight
    return Point(clampedX, min(labelTop, maxLabelTop))
  }

  private var labelAreaHeight: Float {
    max(labelStyle.fontSize + labelVerticalPadding, labelVerticalPadding + 18)
  }

  // Default palette
  public static func defaultSwatches() -> [Swatch] {
    return [
      Swatch("Indigo", .indigo),
      //Swatch("Purple", .purple),
      Swatch("Rose", .rose900),
      //Swatch("Orange", .orange),
      Swatch("Amber", .amber),
      Swatch("Emerald", .emerald),
      Swatch("Graphite", .gray500),
    ]
  }
}
