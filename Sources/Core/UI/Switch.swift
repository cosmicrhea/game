@MainActor
public final class Switch: OptionsControl {
  // MARK: - Public API

  public var frame: Rect
  public var isFocused: Bool = false

  /// Whether the switch is on.
  public var isOn: Bool {
    didSet {
      if isOn != oldValue {
        onToggle?(isOn)
        beginAnimation()
      }
    }
  }

  /// Called when `isOn` changes.
  public var onToggle: ((Bool) -> Void)?

  // MARK: - Styling

  /// When true, renders the larger pill style with circular thumb.
  public var pillStyle: Bool = true

  public var trackOnColor: Color? = nil
  public var trackOffColor = Color.gray700
  public var thumbColor = Color.gray300
  public var thumbOutlineColor = Color.black.withAlphaComponent(0.65)
  public var focusRingColor = Color.gray500.withAlphaComponent(0.35)

  // Dimensions for pill style (approx 44x24). Frame determines final size.
  public var trackCornerRadius: Float = 12
  /// Width multiplier for the thumb relative to its height (pill shape). Only used for pillStyle.
  public var thumbWidthFactor: Float = 1.6

  // Animation configuration
  public var animationDuration: Float = 0.18
  public var animationEasing: Easing = .easeOutCubic

  // MARK: - Private State

  private var isDragging: Bool = false
  private var animating: Bool = false
  private var animFrom: Float = 0
  private var animTo: Float = 0
  private var animTime: Float = 0
  /// Visual progress 0 (off) .. 1 (on)
  private var visualProgress: Float = 0

  // MARK: - Init

  public init(frame: Rect = .zero, isOn: Bool = false) {
    self.frame = frame
    self.isOn = isOn
    self.visualProgress = isOn ? 1 : 0
  }

  // MARK: - Drawing

  public func draw() {
    // Track (rounded pill) centered within frame; prefer a compact pill height
    let desiredTrackHeight: Float = 24
    let trackHeight = pillStyle ? min(desiredTrackHeight, frame.size.height) : frame.size.height
    let trackRect = Rect(
      x: frame.origin.x, y: frame.midY - trackHeight * 0.5, width: frame.size.width, height: trackHeight)
    let corner = pillStyle ? min(trackCornerRadius, trackHeight * 0.5) : 6
    let t = visualProgress
    // Resolve on color: explicit override if provided, else global accent
    let onColor = trackOnColor ?? Color.accent
    let trackColor = blendColor(trackOffColor, onColor, t: t)
    RoundedRect(trackRect, cornerRadius: corner).draw(color: trackColor)

    // Thumb size: a wider pill in pill style; circular in non-pill style
    let thumbHeight = pillStyle ? (trackRect.size.height - 4) : min(20, trackRect.size.height)
    let thumbWidth = pillStyle ? (thumbHeight * thumbWidthFactor) : thumbHeight
    let thumbSize = Size(thumbWidth, thumbHeight)

    // Thumb position (left for off, right for on)
    let insetY = trackRect.origin.y + (trackRect.size.height - thumbSize.height) * 0.5
    let minX = trackRect.origin.x + 2
    let maxX = trackRect.maxX - thumbSize.width - 2
    let thumbX = lerp(minX, maxX, t)
    let thumbRect = Rect(x: thumbX, y: insetY, width: thumbSize.width, height: thumbSize.height)

    RoundedRect(thumbRect, cornerRadius: thumbSize.height * 0.5).draw(color: thumbColor)
    RoundedRect(thumbRect, cornerRadius: thumbSize.height * 0.5).stroke(color: thumbOutlineColor, lineWidth: 2)

    // No additional focus ring; the editor row provides focus styling
  }

  // MARK: - Input Handling

  @discardableResult
  public func handleKey(_ key: Keyboard.Key) -> Bool {
    guard isFocused else { return false }
    switch key {
    case .space, .enter, .numpadEnter, .left, .right, .a, .d:
      toggle()
      UISound.select()
      return true
    default:
      return false
    }
  }

  @discardableResult
  public func handleMouseDown(at position: Point) -> Bool {
    guard frame.contains(position) else { return false }
    isDragging = true
    // Simple behavior: clicking toggles. Drag left/right could be added later.
    toggle()
    return true
  }

  public func handleMouseMove(at position: Point) {
    // No-op for now; reserved for drag gesture to set on/off based on thumb position
    _ = position  // silence unused in some builds
  }

  public func handleMouseUp() { isDragging = false }

  // MARK: - Animation & Update

  public func update(deltaTime: Float) {
    guard animating else { return }
    animTime += deltaTime
    let t = min(1, animTime / max(0.0001, animationDuration))
    let eased = animationEasing.apply(t)
    visualProgress = lerp(animFrom, animTo, eased)
    if t >= 1 {
      animating = false
      visualProgress = animTo
    }
  }

  // MARK: - Private

  private func toggle() { isOn.toggle() }

  private func beginAnimation() {
    animating = true
    animFrom = visualProgress
    animTo = isOn ? 1 : 0
    animTime = 0
  }

  private func blendColor(_ a: Color, _ b: Color, t: Float) -> Color {
    let tt = max(0, min(1, t))
    return Color(
      lerp(a.red, b.red, tt),
      lerp(a.green, b.green, tt),
      lerp(a.blue, b.blue, tt),
      lerp(a.alpha, b.alpha, tt)
    )
  }
}
