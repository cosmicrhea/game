

/// A compact picker that centers the current option text and shows chevrons when focused.
@MainActor
public final class Picker: OptionsControl {
  public var frame: Rect
  public var isFocused: Bool = false

  public var options: [String]
  public var selectedIndex: Int {
    didSet {
      selectedIndex = clampIndex(selectedIndex)
      if selectedIndex != oldValue { onSelectionChanged?(selectedIndex) }
    }
  }
  public var onSelectionChanged: ((Int) -> Void)?

  // Styling
  public var backgroundColor = Color.gray700.withAlphaComponent(0.30)
  public var backgroundCornerRadius: Float = 6
  public var textStyle = TextStyle.menuItem.withFontSize(20).withColor(.gray300)
  public var focusedTextStyle = TextStyle.menuItem.withFontSize(20).withColor(.rose)
  public var chevronStyle = TextStyle.menuItem.withFontSize(24).withColor(.gray300)
  private let leftChevronImage = Image("UI/Icons/Carets/caret-left.png")
  private let rightChevronImage = Image("UI/Icons/Carets/caret-right.png")

  public init(frame: Rect = .zero, options: [String], selectedIndex: Int = 0) {
    self.frame = frame
    self.options = options
    self.selectedIndex = max(0, min(selectedIndex, max(0, options.count - 1)))
  }

  public func draw() {
    // Subtle background
    RoundedRect(frame, cornerRadius: backgroundCornerRadius).draw(color: backgroundColor)

    // Current option centered
    if let current = options.indices.contains(selectedIndex) ? options[selectedIndex] as String? : nil {
      let style = isFocused ? focusedTextStyle : textStyle
      //let textSize = current.size(with: style)
      let x = frame.midX
      let y = frame.midY
      current.draw(at: Point(x, y), style: style, anchor: .center)
    }

    // Chevrons at edges when focused (use images)
    if isFocused, let ctx = GraphicsContext.current {
      let chevronHeight: Float = 20
      let aspectLeft = leftChevronImage.naturalSize.width / max(1, leftChevronImage.naturalSize.height)
      let aspectRight = rightChevronImage.naturalSize.width / max(1, rightChevronImage.naturalSize.height)
      let leftSize = Size(chevronHeight * aspectLeft, chevronHeight)
      let rightSize = Size(chevronHeight * aspectRight, chevronHeight)
      let leftRect = Rect(
        x: frame.origin.x + 8,
        y: frame.midY - leftSize.height * 0.5,
        width: leftSize.width,
        height: leftSize.height
      )
      let rightRect = Rect(
        x: frame.maxX - rightSize.width - 8,
        y: frame.midY - rightSize.height * 0.5,
        width: rightSize.width,
        height: rightSize.height
      )
      ctx.renderer.drawImage(textureID: leftChevronImage.textureID, in: leftRect, tint: .gray300, strokeWidth: 0, strokeColor: nil, shadowColor: nil, shadowOffset: Point(0, 0), shadowBlur: 0)
      ctx.renderer.drawImage(textureID: rightChevronImage.textureID, in: rightRect, tint: .gray300, strokeWidth: 0, strokeColor: nil, shadowColor: nil, shadowOffset: Point(0, 0), shadowBlur: 0)
    }
  }

  @discardableResult
  public func handleKey(_ key: Keyboard.Key) -> Bool {
    guard isFocused else { return false }
    switch key {
    case .a, .left:
      if selectedIndex > 0 {
        selectedIndex -= 1
        UISound.navigate()
        return true
      }
      return false
    case .d, .right:
      if selectedIndex < max(0, options.count - 1) {
        selectedIndex += 1
        UISound.navigate()
        return true
      }
      return false
    default:
      return false
    }
  }

  @discardableResult
  public func handleMouseDown(at position: Point) -> Bool {
    guard frame.contains(position), options.count > 0 else { return false }
    let edgeWidth = max(24, frame.size.width * 0.2)
    let leftZone = Rect(x: frame.origin.x, y: frame.origin.y, width: edgeWidth, height: frame.size.height)
    let rightZone = Rect(x: frame.maxX - edgeWidth, y: frame.origin.y, width: edgeWidth, height: frame.size.height)
    if leftZone.contains(position) {
      if selectedIndex > 0 {
        selectedIndex -= 1
        UISound.navigate()
      }
      return true
    }
    if rightZone.contains(position) {
      if selectedIndex < max(0, options.count - 1) {
        selectedIndex += 1
        UISound.navigate()
      }
      return true
    }
    return false
  }

  public func handleMouseMove(at position: Point) {}
  public func handleMouseUp() {}

  private func clampIndex(_ i: Int) -> Int { max(0, min(i, max(0, options.count - 1))) }
}
