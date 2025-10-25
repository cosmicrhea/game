/// A horizontal slider control with tick marks and a large thumb.
///
/// - Draws a rounded track with evenly spaced tick marks
/// - Supports mouse dragging when not focused
/// - Supports keyboard input with A/D or Left/Right when `isFocused == true`
@MainActor
public final class Slider: OptionsControl, AltClickable {
  public enum Style { case tall, pill, inspector }

  // MARK: - Public API

  /// The frame where the slider is drawn.
  public var frame: Rect

  /// The minimum value of the slider.
  public var minimumValue: Float

  /// The maximum value of the slider.
  public var maximumValue: Float

  /// The current value of the slider. Setting this clamps to `[minimumValue, maximumValue]`
  /// and fires `onValueChanged` if it actually changed.
  public var value: Float {
    didSet {
      let clamped = Self.clamp(value, minimumValue, maximumValue)
      if clamped != value {
        value = clamped
        return
      }
      if value != oldValue { onValueChanged?(value) }
    }
  }

  /// Number of visual tick marks (including endpoints). Use 0 for no ticks.
  public var tickCount: Int

  /// Whether this slider has keyboard focus. When true, A/D and Left/Right adjust value.
  public var isFocused: Bool = false

  /// Called whenever `value` changes after clamping.
  public var onValueChanged: ((Float) -> Void)?

  /// Neutral baseline value from which the filled track segment starts.
  /// Defaults to 0. When outside the slider's range, it is effectively clamped.
  public var neutralValue: Float = 0

  // MARK: - Styling

  /// Visual style of the slider. `.tall` matches the original look; `.pill` is a HUD pill.
  public var style: Style = .tall

  public var cornerRadius: Float = 4
  public var trackHeight: Float = 6
  public var trackInset: Float = 12  // Horizontal inset for track inside frame
  public var thumbSize: Size = Size(9, 28)
  public var tickHeight: Float = 14
  public var tickWidth: Float = 2

  public var trackColor = Color.gray700
  public var trackFillColor: Color? = nil
  public var tickColor = Color.gray500.withAlphaComponent(0.8)
  public var thumbColor = Color.gray300
  public var thumbFocusedColor = Color.gray300
  public var thumbOutlineColor = Color.black.withAlphaComponent(0.65)

  // Value label (optional)
  public var showsValueLabel: Bool = false
  public var valueLabelStyle: TextStyle = TextStyle.itemDescription
  public var valueFormatter: ((Float) -> String)? = nil

  /// If true, suppress tick marks and allow continuous value updates.
  public var isContinuous: Bool = false

  // MARK: - Private State

  private var isDragging: Bool = false
  private let initialValue: Float
  private var mouseDownPoint: Point = .zero
  private var draggedBeyondClickThreshold: Bool = false
  private var inlineEditor: TextField? = nil
  private var dragStartValue: Float = 0

  // MARK: - Init

  public init(
    frame: Rect = .zero, minimumValue: Float = 0, maximumValue: Float = 1, value: Float = 0.5, tickCount: Int = 5
  ) {
    self.frame = frame
    self.minimumValue = minimumValue
    self.maximumValue = max(maximumValue, minimumValue + 0.0001)
    self.value = value
    self.tickCount = max(0, tickCount)
    self.value = Self.clamp(value, minimumValue, self.maximumValue)
    self.initialValue = self.value
  }

  /// Smooth slider initializer: no tick marks, continuous value changes.
  public convenience init(smooth frame: Rect = .zero, min: Float = 0, max: Float = 1, value: Float = 0.5) {
    self.init(frame: frame, minimumValue: min, maximumValue: max, value: value, tickCount: 0)
    self.isContinuous = true
  }

  // MARK: - Drawing

  public func draw() {
    // Metrics for current style
    let m = metricsForCurrentStyle()

    // Track rect (horizontally inset, vertically centered within frame)
    let trackWidth = max(0, frame.size.width - m.trackInset * 2)
    let trackX = frame.origin.x + m.trackInset
    let trackY = frame.midY - m.trackHeight * 0.5
    let trackRect = Rect(x: trackX, y: trackY, width: trackWidth, height: m.trackHeight)

    // Draw base track
    RoundedRect(trackRect, cornerRadius: m.trackCornerRadius).draw(color: trackColor)

    // Draw tick marks
    if tickCount > 0 && !isContinuous {
      let segments = max(1, tickCount - 1)
      for i in 0...segments {
        let t = Float(i) / Float(segments)
        let cx = trackRect.origin.x + t * trackRect.size.width
        let tickRect = Rect(
          x: cx - tickWidth * 0.5,
          y: frame.midY - tickHeight * 0.5,
          width: tickWidth,
          height: tickHeight
        )
        tickRect.fill(with: tickColor)
      }
    }

    // Draw filled portion of the track from neutralValue to current value
    let valueRatio = normalizedValue()
    let clampedNeutral = Self.clamp(neutralValue, minimumValue, maximumValue)
    let neutralRatio: Float =
      (maximumValue == minimumValue)
      ? 0
      : (clampedNeutral - minimumValue) / (maximumValue - minimumValue)

    let leftRatio = min(valueRatio, neutralRatio)
    let rightRatio = max(valueRatio, neutralRatio)
    let fillX = trackRect.origin.x + trackRect.size.width * leftRatio
    let fillW = trackRect.size.width * (rightRatio - leftRatio)
    if fillW > 0.0001 {
      let fillRect = Rect(x: fillX, y: trackRect.origin.y, width: fillW, height: trackRect.size.height)
      let fillColor = trackFillColor ?? Color.accent
      RoundedRect(fillRect, cornerRadius: m.trackCornerRadius).draw(color: fillColor)
    }

    // Thumb (skip for inspector style)
    if style != .inspector {
      let thumbCenterX = trackRect.origin.x + trackRect.size.width * valueRatio
      let thumbRect = Rect(
        x: thumbCenterX - m.thumbSize.width * 0.5,
        y: frame.midY - m.thumbSize.height * 0.5,
        width: m.thumbSize.width,
        height: m.thumbSize.height
      )

      let thumbFill = isFocused ? thumbFocusedColor : thumbColor
      RoundedRect(thumbRect, cornerRadius: m.thumbCornerRadius).draw(color: thumbFill)
      RoundedRect(thumbRect, cornerRadius: m.thumbCornerRadius).stroke(color: thumbOutlineColor, lineWidth: 2)
    }

    // Draw value label on the right if enabled
    if showsValueLabel {
      let text = (valueFormatter ?? { String(format: "%.2f", $0) })(value)
      let textOrigin = Point(frame.maxX + 52, frame.midY)
      text.draw(at: textOrigin, style: valueLabelStyle.withMonospacedDigits(true), anchor: .right)
    }

    // Inspector: draw centered value text inside the control
    if style == .inspector && inlineEditor == nil {
      let text = (valueFormatter ?? { String(format: "%.2f", $0) })(value)
      text.draw(at: Point(frame.midX, frame.midY), style: valueLabelStyle.withMonospacedDigits(true), anchor: .center)
    }

    // Draw inline editor on top if active
    inlineEditor?.draw()
  }

  // MARK: - Input Handling

  /// Handle a key press. Returns true if consumed.
  @discardableResult
  public func handleKey(_ key: Keyboard.Key) -> Bool {
    if let editor = inlineEditor {
      if key == .escape {
        inlineEditor = nil
        return true
      }
      return editor.handleKey(key)
    }
    guard isFocused else { return false }
    switch key {
    case .a, .left:
      stepValue(by: -keyboardStep())
      UISound.navigate()
      return true
    case .d, .right:
      stepValue(by: keyboardStep())
      UISound.navigate()
      return true
    default:
      return false
    }
  }

  /// Call when the left mouse button is pressed. Returns true if the slider starts a drag or changes value.
  @discardableResult
  public func handleMouseDown(at position: Point) -> Bool {
    // If inline editor is active, forward to it
    if let editor = inlineEditor, editor.frame.contains(position) {
      editor.isFocused = true
      return editor.handleMouseDown(at: position)
    }

    let (trackRect, thumbRect) = layoutRects()
    // Expand hit area vertically to thumb height around the track center
    let expandedHit = Rect(
      x: trackRect.origin.x,
      y: min(trackRect.origin.y, thumbRect.origin.y),
      width: trackRect.size.width,
      height: max(trackRect.size.height, thumbRect.size.height)
    )
    if thumbRect.contains(position) || expandedHit.contains(position) {
      isDragging = true
      draggedBeyondClickThreshold = false
      mouseDownPoint = position
      if style == .inspector {
        dragStartValue = value
      } else {
        value = valueForPoint(position, within: trackRect)
      }
      return true
    }
    return false
  }

  /// Call on mouse move. If dragging, updates the value.
  public func handleMouseMove(at position: Point) {
    if let editor = inlineEditor {
      editor.handleMouseMove(at: position)
      return
    }
    guard isDragging else { return }
    let (trackRect, _) = layoutRects()
    let dx = position.x - mouseDownPoint.x
    let dy = position.y - mouseDownPoint.y
    if (dx * dx + dy * dy) > 4 { draggedBeyondClickThreshold = true }
    if style == .inspector {
      let width = max(1, trackRect.size.width)
      let t = dx / width
      let delta = t * (maximumValue - minimumValue)
      value = Self.clamp(dragStartValue + delta, minimumValue, maximumValue)
    } else {
      value = valueForPoint(position, within: trackRect)
    }
  }

  /// Call when the left mouse button is released.
  public func handleMouseUp() {
    defer { isDragging = false }
    if let editor = inlineEditor {
      editor.handleMouseUp()
      return
    }
    if style == .inspector && isDragging && !draggedBeyondClickThreshold {
      beginInlineEdit()
    }
  }

  // MARK: - AltClickable

  public func altClick(at position: Point) {
    isDragging = false
    value = initialValue
  }

  // MARK: - Helpers

  private func normalizedValue() -> Float {
    if maximumValue == minimumValue { return 0 }
    return (value - minimumValue) / (maximumValue - minimumValue)
  }

  private func keyboardStep() -> Float {
    if tickCount > 1 && !isContinuous {
      return (maximumValue - minimumValue) / Float(tickCount - 1)
    }
    return (maximumValue - minimumValue) / 20.0
  }

  private func stepValue(by delta: Float) {
    value = Self.clamp(value + delta, minimumValue, maximumValue)
  }

  private func valueForPoint(_ p: Point, within track: Rect) -> Float {
    let clampedX = max(track.minX, min(track.maxX, p.x))
    let t = (clampedX - track.origin.x) / max(1, track.size.width)
    let v = minimumValue + t * (maximumValue - minimumValue)
    if tickCount > 1 && !isContinuous {
      let step = (maximumValue - minimumValue) / Float(tickCount - 1)
      let snapped = ((v - minimumValue) / step).rounded() * step + minimumValue
      return Self.clamp(snapped, minimumValue, maximumValue)
    }
    return Self.clamp(v, minimumValue, maximumValue)
  }

  private func layoutRects() -> (track: Rect, thumb: Rect) {
    let m = metricsForCurrentStyle()
    let trackWidth = max(0, frame.size.width - m.trackInset * 2)
    let trackX = frame.origin.x + m.trackInset
    let trackY = frame.midY - m.trackHeight * 0.5
    let trackRect = Rect(x: trackX, y: trackY, width: trackWidth, height: m.trackHeight)

    let ratio = normalizedValue()
    let thumbCenterX = trackRect.origin.x + trackRect.size.width * ratio
    let thumbRect = Rect(
      x: thumbCenterX - m.thumbSize.width * 0.5,
      y: frame.midY - m.thumbSize.height * 0.5,
      width: m.thumbSize.width,
      height: m.thumbSize.height
    )
    return (trackRect, thumbRect)
  }

  private static func clamp(_ v: Float, _ a: Float, _ b: Float) -> Float {
    return max(min(v, b), a)
  }

  private struct StyleMetrics {
    let trackHeight: Float
    let trackInset: Float
    let trackCornerRadius: Float
    let thumbSize: Size
    let thumbCornerRadius: Float
  }

  private func metricsForCurrentStyle() -> StyleMetrics {
    switch style {
    case .tall:
      return StyleMetrics(
        trackHeight: trackHeight,
        trackInset: trackInset,
        trackCornerRadius: cornerRadius,
        thumbSize: thumbSize,
        thumbCornerRadius: 6
      )
    case .pill:
      let pillTrackHeight: Float = 24
      let pillThumbSize = Size(pillTrackHeight, pillTrackHeight)
      return StyleMetrics(
        trackHeight: pillTrackHeight,
        trackInset: trackInset,
        trackCornerRadius: pillTrackHeight * 0.5,
        thumbSize: pillThumbSize,
        thumbCornerRadius: pillThumbSize.width * 0.5
      )
    case .inspector:
      let h: Float = 24
      // No visible thumb; keep size minimal for hit testing expansion
      let tSize = Size(0, 0)
      return StyleMetrics(
        trackHeight: h,
        trackInset: trackInset,
        trackCornerRadius: h * 0.5,
        thumbSize: tSize,
        thumbCornerRadius: 0
      )
    }
  }

  // MARK: - Inline editing (inspector)

  private func beginInlineEdit() {
    // Avoid stacking editors
    if inlineEditor != nil { return }
    let editor = TextField(frame: frame, text: (valueFormatter ?? { String(format: "%.2f", $0) })(value))
    editor.bezeled = true
    editor.textStyle = valueLabelStyle
    editor.onCommit = { [weak self] in
      guard let self else { return }
      if let v = Float(editor.text) {
        self.value = Self.clamp(v, self.minimumValue, self.maximumValue)
      }
      self.inlineEditor = nil
    }
    inlineEditor = editor
    inlineEditor?.isFocused = true
  }

  // Public helpers for demos to route input when editing
  public var isEditingInline: Bool { inlineEditor != nil }

  @discardableResult
  public func insertText(_ string: String) -> Bool {
    guard let editor = inlineEditor else { return false }
    return editor.insertText(string)
  }

}
