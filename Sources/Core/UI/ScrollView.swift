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

  public enum ScrollbarPosition {
    case inside
    case outside
  }
  public var scrollbarPosition: ScrollbarPosition = .inside

  // Edge fades were experimental; disabled for now

  // MARK: - Physics / Interaction

  /// If true, allows scrolling by clicking and dragging the mouse. Default is false.
  public var mouseDragCanScroll: Bool = false

  private var isDragging: Bool = false
  private var lastMouse: Point = .zero
  private var velocity: Point = .zero
  private var lastUpdateTime: Double = GLFWSession.currentTime
  private var isHovered: Bool = false

  // Deceleration tuned to feel close to macOS
  // velocity is in px/sec; decay per second
  public var decelerationRate: Float = 8.0  // higher = faster slow down

  // Rubber-banding: resistance curve based on overscroll distance
  // The further you overscroll, the more resistance (native-like behavior)
  public var rubberBandResistance: Float = 0.55  // Controls how quickly resistance increases (0.0 = linear, higher = more aggressive)
  public var rubberBandMaxResistance: Float = 0.12  // Minimum movement factor at maximum overscroll

  // Spring-back strength towards bounds when released beyond edges
  public var springStrength: Float = 140.0
  public var springDamping: Float = 26.0

  // Scroll wheel/trackpad scale (GLFW yOffset units to pixels)
  public var wheelPixelsPerUnit: Float = 8.0  // Reduced from 16.0 for slower scrolling

  // Raw scroll tracking for better physics
  private var rawScrollVelocity: Point = .zero  // Raw GLFW units per second
  private var lastScrollTime: Double = 0
  private var lastScrollDelta: Point = .zero

  // Scrollbar fade
  private var scrollbarAlpha: Float = 0
  private var scrollbarTargetAlpha: Float = 0
  private var scrollbarHoldTime: Float = 0
  private let scrollbarShowDuration: Float = 0.9
  private let scrollbarFadeSpeed: Float = 6.0

  // Cached ranges
  private var maxOffsetX: Float = 0
  private var maxOffsetY: Float = 0
  private var hasInitializedOffset: Bool = false

  // Animated scrolling
  private var targetScrollOffset: Point?
  private let scrollAnimationSpeed: Float = 8.0

  // MARK: - Init

  public init(frame: Rect = .zero, contentSize: Size = .zero) {
    self.frame = frame
    self.contentSize = contentSize
    updateScrollableRanges()
  }

  // MARK: - Public Methods

  /// Scroll to the specified offset, optionally with animation.
  public func scroll(to offset: Point, animated: Bool = false) {
    let clamped = Point(
      x: allowsHorizontalScroll ? max(0, min(offset.x, maxOffsetX)) : contentOffset.x,
      y: allowsVerticalScroll ? max(0, min(offset.y, maxOffsetY)) : contentOffset.y
    )
    if animated {
      targetScrollOffset = clamped
    } else {
      contentOffset = clamped
      targetScrollOffset = nil
    }
  }

  public func update(deltaTime: Float) {
    // Integrate wheel-induced velocity and drag inertia
    applyInertia(deltaTime: deltaTime)

    // Smooth scroll animation (apply after inertia to override it)
    if let target = targetScrollOffset {
      let current = contentOffset
      let diff = Point(target.x - current.x, target.y - current.y)
      if abs(diff.x) > 0.1 || abs(diff.y) > 0.1 {
        let step = Point(
          diff.x * min(1.0, scrollAnimationSpeed * deltaTime),
          diff.y * min(1.0, scrollAnimationSpeed * deltaTime)
        )
        contentOffset = Point(current.x + step.x, current.y + step.y)
      } else {
        contentOffset = target
        targetScrollOffset = nil
      }
    }

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
    targetScrollOffset = nil  // Cancel animation on drag
    isDragging = true
    isHovered = true
    lastMouse = position
    revealScrollbar()
    return true
  }

  public func handleMouseMove(at position: Point) {
    // Update hover state regardless of dragging
    isHovered = frame.contains(position)
    guard isDragging && mouseDragCanScroll else { return }
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
    let dt = max(1.0 / 240.0, Float(GLFWSession.currentTime - lastUpdateTime))
    velocity = Point(applied.x / dt, applied.y / dt)
    revealScrollbar()
  }

  public func handleMouseUp() { isDragging = false }

  /// Handle wheel/trackpad scroll input (GLFW units).
  /// Receives raw scroll deltas from GLFW - these are used directly for physics calculations
  /// to achieve native-feeling rubberbanding behavior.
  public func handleScroll(xOffset: Double, yOffset: Double, mouse: Point? = nil) {
    // Route only if inside frame (when a point is provided)
    if let p = mouse, !frame.contains(p) { return }
    targetScrollOffset = nil  // Cancel animation on manual scroll

    let now = GLFWSession.currentTime
    let rawDelta = Point(
      Float(xOffset),
      Float(yOffset)
    )

    // Track raw scroll velocity for momentum calculations
    if lastScrollTime > 0 {
      let dt = Float(max(1.0 / 1000.0, now - lastScrollTime))  // Prevent division by zero
      // Exponential smoothing of raw scroll velocity
      let instantVelocity = Point(rawDelta.x / dt, rawDelta.y / dt)
      let smoothing: Float = 0.3  // How quickly to adapt to new velocity
      rawScrollVelocity.x = rawScrollVelocity.x * (1.0 - smoothing) + instantVelocity.x * smoothing
      rawScrollVelocity.y = rawScrollVelocity.y * (1.0 - smoothing) + instantVelocity.y * smoothing
    }
    lastScrollTime = now
    lastScrollDelta = rawDelta

    // Convert raw scroll to pixel delta
    // Note: rawDelta.x is already negative from GLFW on macOS, so we flip it
    let dx = allowsHorizontalScroll ? -Float(xOffset) * wheelPixelsPerUnit : 0
    // Flip Y so natural scrolling matches macOS: positive yOffset scrolls content down
    let dy = allowsVerticalScroll ? Float(yOffset) * wheelPixelsPerUnit : 0

    var applied = Point(dx, dy)

    // Apply rubber-banding with resistance curve based on overscroll distance
    applied = applyRubberBanding(delta: applied, rawDelta: rawDelta)

    contentOffset.x =
      allowsHorizontalScroll
      ? clamp(contentOffset.x + applied.x, -overscrollMarginX(), maxOffsetX + overscrollMarginX()) : contentOffset.x
    contentOffset.y =
      allowsVerticalScroll
      ? clamp(contentOffset.y + applied.y, -overscrollMarginY(), maxOffsetY + overscrollMarginY()) : contentOffset.y

    // Add momentum based on raw scroll velocity (feels more natural)
    // Convert raw velocity to pixel velocity
    let momentumX = -rawScrollVelocity.x * wheelPixelsPerUnit * 0.15
    let momentumY = rawScrollVelocity.y * wheelPixelsPerUnit * 0.15
    velocity.x += momentumX
    velocity.y += momentumY

    revealScrollbar()
  }

  // MARK: - Private Helpers

  private func updateScrollableRanges() {
    maxOffsetX = max(0, contentSize.width - frame.size.width)
    maxOffsetY = max(0, contentSize.height - frame.size.height)
    contentOffset.x = clamp(contentOffset.x, 0, maxOffsetX)
    // In Y-flipped coordinates, contentOffset.y = 0 means bottom, maxOffsetY means top
    // Initialize to top only once on first setup (when contentOffset.y is still 0 and we have scrollable content)
    if !hasInitializedOffset && contentOffset.y == 0 && maxOffsetY > 0 {
      contentOffset.y = maxOffsetY
      hasInitializedOffset = true
    } else {
      contentOffset.y = clamp(contentOffset.y, 0, maxOffsetY)
    }
  }

  private func overscrollMarginX() -> Float { frame.size.width * 0.22 }
  private func overscrollMarginY() -> Float { frame.size.height * 0.22 }

  /// Apply rubber-banding resistance based on overscroll distance.
  /// Uses a resistance curve (exponential) that increases resistance the further you overscroll,
  /// matching native scroll view behavior more closely than a simple multiplier.
  private func applyRubberBanding(delta: Point, rawDelta: Point) -> Point {
    // Note: rawDelta is available for future velocity-dependent rubberbanding if needed
    let _ = rawDelta
    var out = delta

    if allowsHorizontalScroll {
      let overscrollX: Float
      if contentOffset.x < 0 {
        // Overscrolled past top edge (negative offset)
        overscrollX = abs(contentOffset.x)
      } else if contentOffset.x > maxOffsetX {
        // Overscrolled past bottom edge
        overscrollX = contentOffset.x - maxOffsetX
      } else {
        overscrollX = 0
      }

      if overscrollX > 0 {
        let margin = overscrollMarginX()
        let normalizedOverscroll = min(overscrollX / margin, 1.0)  // 0.0 at edge, 1.0 at max overscroll
        // Resistance curve: starts at 1.0 (full movement) and decreases exponentially
        // At max overscroll, resistance reaches rubberBandMaxResistance
        let resistance = 1.0 - (1.0 - rubberBandMaxResistance) * pow(normalizedOverscroll, rubberBandResistance)
        out.x *= resistance
      }
    } else {
      out.x = 0
    }

    if allowsVerticalScroll {
      let overscrollY: Float
      if contentOffset.y < 0 {
        // Overscrolled past top edge (negative offset)
        overscrollY = abs(contentOffset.y)
      } else if contentOffset.y > maxOffsetY {
        // Overscrolled past bottom edge
        overscrollY = contentOffset.y - maxOffsetY
      } else {
        overscrollY = 0
      }

      if overscrollY > 0 {
        let margin = overscrollMarginY()
        let normalizedOverscroll = min(overscrollY / margin, 1.0)  // 0.0 at edge, 1.0 at max overscroll
        // Resistance curve: starts at 1.0 (full movement) and decreases exponentially
        // At max overscroll, resistance reaches rubberBandMaxResistance
        let resistance = 1.0 - (1.0 - rubberBandMaxResistance) * pow(normalizedOverscroll, rubberBandResistance)
        out.y *= resistance
      }
    } else {
      out.y = 0
    }

    return out
  }

  /// Legacy method for mouse drag rubber-banding (still uses simpler physics)
  private func dampedDeltaForEdges(delta: Point) -> Point {
    var out = delta

    if allowsHorizontalScroll {
      let overscrollX: Float
      if contentOffset.x < 0 {
        overscrollX = abs(contentOffset.x)
      } else if contentOffset.x > maxOffsetX {
        overscrollX = contentOffset.x - maxOffsetX
      } else {
        overscrollX = 0
      }

      if overscrollX > 0 {
        let margin = overscrollMarginX()
        let normalizedOverscroll = min(overscrollX / margin, 1.0)
        let resistance = 1.0 - (1.0 - rubberBandMaxResistance) * pow(normalizedOverscroll, rubberBandResistance)
        out.x *= resistance
      }
    } else {
      out.x = 0
    }

    if allowsVerticalScroll {
      let overscrollY: Float
      if contentOffset.y < 0 {
        overscrollY = abs(contentOffset.y)
      } else if contentOffset.y > maxOffsetY {
        overscrollY = contentOffset.y - maxOffsetY
      } else {
        overscrollY = 0
      }

      if overscrollY > 0 {
        let margin = overscrollMarginY()
        let normalizedOverscroll = min(overscrollY / margin, 1.0)
        let resistance = 1.0 - (1.0 - rubberBandMaxResistance) * pow(normalizedOverscroll, rubberBandResistance)
        out.y *= resistance
      }
    } else {
      out.y = 0
    }

    return out
  }

  private func applyInertia(deltaTime: Float) {
    let now = GLFWSession.currentTime
    let _ = now - lastUpdateTime
    lastUpdateTime = now

    guard !isDragging else { return }

    // Decay raw scroll velocity when not actively scrolling
    if lastScrollTime > 0 && (now - lastScrollTime) > 0.1 {
      // If no scroll input for 100ms, start decaying raw velocity
      rawScrollVelocity.x *= exp(-decelerationRate * Float(now - lastScrollTime))
      rawScrollVelocity.y *= exp(-decelerationRate * Float(now - lastScrollTime))
    }

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

    // Calculate scrollbar position (inside or outside)
    let trackX: Float
    if scrollbarPosition == .outside {
      trackX = frame.maxX + scrollbarInset
    } else {
      trackX = frame.maxX - scrollbarInset - scrollbarWidth
    }

    let trackY = frame.origin.y + scrollbarInset
    let trackH = frame.size.height - 2 * scrollbarInset

    let visible = frame.size.height
    let total = max(visible, contentSize.height)
    let baseRatio = max(visible / total, 0.05)

    // Calculate overscroll amount (rubberbanding)
    let overscrollY: Float
    if contentOffset.y < 0 {
      overscrollY = abs(contentOffset.y)
    } else if contentOffset.y > maxOffsetY {
      overscrollY = contentOffset.y - maxOffsetY
    } else {
      overscrollY = 0
    }

    // Shrink thumb height proportionally when rubberbanding
    // When fully overscrolled at margin, thumb should be ~50% of normal size
    let margin = overscrollMarginY()
    let overscrollRatio = margin > 0 ? min(overscrollY / margin, 1.0) : 0.0
    // Shrink factor: 1.0 at no overscroll, 0.5 at max overscroll
    let shrinkFactor = 1.0 - overscrollRatio * 0.5
    let ratio = baseRatio * shrinkFactor

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
