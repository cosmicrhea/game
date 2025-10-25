import struct Foundation.Date

@MainActor
public final class ScrollView {
  // MARK: - Public API

  public var frame: Rect

  /// Total content size inside the scroll view.
  public var contentSize: Size {
    didSet { updateScrollableRanges() }
  }

  /// Current content offset (top-left of viewport in content coordinates).
  public var contentOffset: Point = .zero

  /// Enable/disable horizontal and vertical scrolling.
  public var allowsHorizontalScroll: Bool = false
  public var allowsVerticalScroll: Bool = true

  /// Called during draw to let the owner render its content.
  /// The provided origin is the content origin translated into view space so you can draw
  /// content at `origin + localPosition`.
  public var onDrawContent: ((Point) -> Void)?

  /// Optional: Called to learn whether the cursor is inside the scroll view (for routing wheel input).
  public func contains(_ p: Point) -> Bool { frame.contains(p) }

  // MARK: - Styling

  public var backgroundColor: Color? = nil
  public var cornerRadius: Float = 6

  // Scrollbar styling (vertical)
  public var showsScrollbar: Bool = true
  public var scrollbarWidth: Float = 4
  public var scrollbarCornerRadius: Float = 2
  public var scrollbarInset: Float = 2
  public var scrollbarColor = Color.gray500.withAlphaComponent(0.85)
  public var autohideScrollbars: Bool = true

  // Edge fades were experimental; disabled for now

  // MARK: - Physics / Interaction

  private var isDragging: Bool = false
  private var lastMouse: Point = .zero
  private var velocity: Point = .zero
  private var lastUpdateTime: Double = Date().timeIntervalSinceReferenceDate
  private var isHovered: Bool = false

  // Deceleration tuned to feel close to macOS
  // velocity is in px/sec; decay per second
  public var decelerationRate: Float = 8.0  // higher = faster slow down

  // Rubber-banding factor when dragging beyond edges (0..1, lower = stretchier)
  public var rubberBandFactor: Float = 0.25

  // Spring-back strength towards bounds when released beyond edges
  public var springStrength: Float = 140.0
  public var springDamping: Float = 26.0

  // Scroll wheel/trackpad scale (GLFW yOffset units to pixels)
  public var wheelPixelsPerUnit: Float = 16.0

  // Scrollbar fade
  private var scrollbarAlpha: Float = 0
  private var scrollbarTargetAlpha: Float = 0
  private var scrollbarHoldTime: Float = 0
  private let scrollbarShowDuration: Float = 0.9
  private let scrollbarFadeSpeed: Float = 6.0

  // Cached ranges
  private var maxOffsetX: Float = 0
  private var maxOffsetY: Float = 0

  // MARK: - Init

  public init(frame: Rect = .zero, contentSize: Size = .zero) {
    self.frame = frame
    self.contentSize = contentSize
    updateScrollableRanges()
  }

  // MARK: - Public Methods

  public func update(deltaTime: Float) {
    // Integrate wheel-induced velocity and drag inertia
    applyInertia(deltaTime: deltaTime)
    // Update scrollbar fade
    updateScrollbar(deltaTime: deltaTime)
  }

  public func draw() {
    // Background
    if let bg = backgroundColor {
      RoundedRect(frame, cornerRadius: cornerRadius).draw(color: bg)
    }

    guard let ctx = GraphicsContext.current else { return }
    ctx.save()
    ctx.clip(to: frame)

    // Draw content directly inside clip
    let origin = Point(
      frame.origin.x - contentOffset.x,
      frame.origin.y - contentOffset.y
    )
    onDrawContent?(origin)
    ctx.restore()

    // Scrollbars always on top
    if showsScrollbar { drawVerticalScrollbar() }
  }

  // MARK: - Input Handling

  @discardableResult
  public func handleMouseDown(at position: Point) -> Bool {
    guard frame.contains(position) else { return false }
    isDragging = true
    isHovered = true
    lastMouse = position
    revealScrollbar()
    return true
  }

  public func handleMouseMove(at position: Point) {
    // Update hover state regardless of dragging
    isHovered = frame.contains(position)
    guard isDragging else { return }
    let dx = position.x - lastMouse.x
    let dy = position.y - lastMouse.y
    lastMouse = position

    var applied = Point(dx, dy)
    // Dragging moves content opposite to pointer delta
    applied.x = -applied.x
    applied.y = -applied.y

    // Apply rubber-banding near edges
    applied = dampedDeltaForEdges(delta: applied)

    contentOffset.x =
      allowsHorizontalScroll
      ? clamp(contentOffset.x + applied.x, -overscrollMarginX(), maxOffsetX + overscrollMarginX()) : contentOffset.x
    contentOffset.y =
      allowsVerticalScroll
      ? clamp(contentOffset.y + applied.y, -overscrollMarginY(), maxOffsetY + overscrollMarginY()) : contentOffset.y

    // Estimate instantaneous velocity from drag (px/sec)
    // Using simple last frame delta; smoothed by later deceleration
    let dt = max(1.0 / 240.0, Float(Date().timeIntervalSinceReferenceDate - lastUpdateTime))
    velocity = Point(applied.x / dt, applied.y / dt)
    revealScrollbar()
  }

  public func handleMouseUp() { isDragging = false }

  /// Handle wheel/trackpad scroll input (GLFW units).
  public func handleScroll(xOffset: Double, yOffset: Double, mouse: Point? = nil) {
    // Route only if inside frame (when a point is provided)
    if let p = mouse, !frame.contains(p) { return }

    let dx = allowsHorizontalScroll ? -Float(xOffset) * wheelPixelsPerUnit : 0
    // Flip Y so natural scrolling matches macOS: positive yOffset scrolls content down
    let dy = allowsVerticalScroll ? Float(yOffset) * wheelPixelsPerUnit : 0

    var applied = Point(dx, dy)
    applied = dampedDeltaForEdges(delta: applied)

    contentOffset.x =
      allowsHorizontalScroll
      ? clamp(contentOffset.x + applied.x, -overscrollMarginX(), maxOffsetX + overscrollMarginX()) : contentOffset.x
    contentOffset.y =
      allowsVerticalScroll
      ? clamp(contentOffset.y + applied.y, -overscrollMarginY(), maxOffsetY + overscrollMarginY()) : contentOffset.y

    // Add momentum
    velocity.x += applied.x * 12
    velocity.y += applied.y * 12
    revealScrollbar()
  }

  // MARK: - Private Helpers

  private func updateScrollableRanges() {
    maxOffsetX = max(0, contentSize.width - frame.size.width)
    maxOffsetY = max(0, contentSize.height - frame.size.height)
    contentOffset.x = clamp(contentOffset.x, 0, maxOffsetX)
    contentOffset.y = clamp(contentOffset.y, 0, maxOffsetY)
  }

  private func overscrollMarginX() -> Float { frame.size.width * 0.22 }
  private func overscrollMarginY() -> Float { frame.size.height * 0.22 }

  private func dampedDeltaForEdges(delta: Point) -> Point {
    var out = delta

    if allowsHorizontalScroll {
      if contentOffset.x <= 0 && delta.x < 0 { out.x *= rubberBandFactor }
      if contentOffset.x >= maxOffsetX && delta.x > 0 { out.x *= rubberBandFactor }
    } else {
      out.x = 0
    }

    if allowsVerticalScroll {
      if contentOffset.y <= 0 && delta.y < 0 { out.y *= rubberBandFactor }
      if contentOffset.y >= maxOffsetY && delta.y > 0 { out.y *= rubberBandFactor }
    } else {
      out.y = 0
    }

    return out
  }

  private func applyInertia(deltaTime: Float) {
    let now = Date().timeIntervalSinceReferenceDate
    let _ = now - lastUpdateTime
    lastUpdateTime = now

    guard !isDragging else { return }

    // Apply velocity
    if allowsHorizontalScroll {
      contentOffset.x += velocity.x * deltaTime
    }
    if allowsVerticalScroll {
      contentOffset.y += velocity.y * deltaTime
    }

    // Decelerate exponentially
    let decay = exp(-decelerationRate * deltaTime)
    velocity.x *= decay
    velocity.y *= decay

    // Spring back into bounds if necessary
    if allowsHorizontalScroll {
      if contentOffset.x < 0 || contentOffset.x > maxOffsetX {
        let target = clamp(contentOffset.x, 0, maxOffsetX)
        let displacement = target - contentOffset.x
        // Critically damped spring approximation
        let accel = displacement * springStrength - velocity.x * springDamping
        contentOffset.x += accel * deltaTime * deltaTime
        velocity.x += accel * deltaTime
        // Extra damping when out of bounds to settle faster
        velocity.x *= 0.65
      }
    }

    if allowsVerticalScroll {
      if contentOffset.y < 0 || contentOffset.y > maxOffsetY {
        let target = clamp(contentOffset.y, 0, maxOffsetY)
        let displacement = target - contentOffset.y
        let accel = displacement * springStrength - velocity.y * springDamping
        contentOffset.y += accel * deltaTime * deltaTime
        velocity.y += accel * deltaTime
        velocity.y *= 0.65
      }
    }
  }

  private func revealScrollbar() {
    guard showsScrollbar else { return }
    scrollbarTargetAlpha = 1
    scrollbarHoldTime = scrollbarShowDuration
  }

  private func updateScrollbar(deltaTime: Float) {
    guard showsScrollbar else { return }
    if !autohideScrollbars {
      scrollbarTargetAlpha = 1
    } else if isHovered {
      // While hovered, keep scrollbars visible
      scrollbarTargetAlpha = 1
    } else if scrollbarHoldTime > 0 {
      scrollbarHoldTime -= deltaTime
      scrollbarTargetAlpha = 1
    } else {
      scrollbarTargetAlpha = 0
    }

    // Smoothly approach target alpha
    let diff = scrollbarTargetAlpha - scrollbarAlpha
    let step = max(-1, min(1, diff)) * scrollbarFadeSpeed * deltaTime
    if abs(diff) <= abs(step) {
      scrollbarAlpha = scrollbarTargetAlpha
    } else {
      scrollbarAlpha += step
    }
  }

  private func drawVerticalScrollbar() {
    guard scrollbarAlpha > 0.001 else { return }
    guard contentSize.height > frame.size.height + 0.5 else { return }

    let trackX = frame.maxX - scrollbarInset - scrollbarWidth
    let trackY = frame.origin.y + scrollbarInset
    let trackH = frame.size.height - 2 * scrollbarInset

    let visible = frame.size.height
    let total = max(visible, contentSize.height)
    let ratio = max(visible / total, 0.05)
    let thumbH = max(20, trackH * ratio)

    let maxScroll = max(0.0001, maxOffsetY)
    let t = clamp(contentOffset.y / maxScroll, 0, 1)
    let thumbY = trackY + (trackH - thumbH) * t

    let color = Color(
      scrollbarColor.red,
      scrollbarColor.green,
      scrollbarColor.blue,
      scrollbarColor.alpha * scrollbarAlpha
    )

    let thumbRect = Rect(x: trackX, y: thumbY, width: scrollbarWidth, height: thumbH)
    RoundedRect(thumbRect, cornerRadius: scrollbarCornerRadius).draw(color: color)
  }

  // Edge fades removed
}

// MARK: - Small Utilities

@inline(__always)
private func clamp(_ v: Float, _ lo: Float, _ hi: Float) -> Float { max(lo, min(hi, v)) }
