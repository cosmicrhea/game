public final class Caret {
  private let direction: Direction
  private let animationBehavior: AnimationBehavior

  public let image: Image
  public var visible: Bool = true

  private var animationTime: Float = 0

  // Cached prerendered image with stroke baked in (for fade animation)
  private var prerenderedImage: Image?
  private var cachedStrokeWidth: Float?
  private var cachedStrokeColor: Color?

  public enum Direction {
    case left
    case right
    case up
    case down
  }

  public enum AnimationBehavior {
    case move
    case fade
    case blink
  }

  public init(direction: Direction, animationBehavior: AnimationBehavior = .move) {
    self.direction = direction
    self.animationBehavior = animationBehavior

    switch direction {
    case .left: image = Image("UI/Icons/Carets/caret-left.png")
    case .right: image = Image("UI/Icons/Carets/caret-right.png")
    case .up: image = Image("UI/Icons/Carets/caret-up.png")
    case .down: image = Image("UI/Icons/Carets/caret-down.png")
    }
  }

  /// Reset the animation to start fresh
  public func resetAnimation() {
    animationTime = 0
  }

  /// Get or create a prerendered image with stroke baked in
  @MainActor
  private func getOrCreatePrerenderedImage(
    size: Size,
    tint: Color,
    strokeWidth: Float,
    strokeColor: Color
  ) -> Image {
    // Check if we have a cached prerendered image with matching stroke params
    if let cached = prerenderedImage,
      cachedStrokeWidth == strokeWidth,
      cachedStrokeColor == strokeColor,
      cached.naturalSize.width >= size.width,
      cached.naturalSize.height >= size.height
    {
      return cached
    }

    // Create new prerendered image with padding for stroke
    // Add stroke width on all sides to ensure stroke doesn't get clipped
    let strokePadding = strokeWidth * 2  // Padding on both sides
    let prerenderedSize = Size(
      max(size.width, image.naturalSize.width) + strokePadding,
      max(size.height, image.naturalSize.height) + strokePadding
    )

    let caretImage = image
    prerenderedImage = Image(size: prerenderedSize, pixelScale: 1.0, isFlipped: false) {
      // Render the caret image with stroke into the framebuffer
      // Center the image in the framebuffer (using flipped coordinates)
      // Account for stroke padding by offsetting from edges
      let imageSize = caretImage.naturalSize
      let halfStrokePadding = strokeWidth
      let imageRect = Rect(
        origin: Point(
          halfStrokePadding + (prerenderedSize.width - strokePadding - imageSize.width) * 0.5,
          halfStrokePadding + (prerenderedSize.height - strokePadding - imageSize.height) * 0.5
        ),
        size: imageSize
      )

      caretImage.draw(
        in: imageRect,
        tint: tint,
        strokeWidth: strokeWidth,
        strokeColor: strokeColor
      )
    }

    cachedStrokeWidth = strokeWidth
    cachedStrokeColor = strokeColor

    return prerenderedImage!
  }

  @MainActor
  public func draw(
    at point: Point,
    tint: Color = .emerald,
    scale: Float = 0.5,
    deltaTime: Float,
    strokeWidth: Float? = nil,
    strokeColor: Color? = nil
  ) {
    // Update animation time with proper delta time
    animationTime += deltaTime

    guard visible else { return }

    let originalSize = image.naturalSize

    let animatedPoint: Point
    var rect: Rect
    let finalTint: Color
    let usePrerendered: Bool
    let alpha: Float

    switch animationBehavior {
    case .move:
      // Animate with slow back-and-forth movement
      let animationOffset: Float = GLMath.sin(animationTime * 0.8) * 8  // 8px amplitude, slow speed

      let animatedX: Float
      let animatedY: Float

      switch direction {
      case .left:
        animatedX = point.x - animationOffset
        animatedY = point.y
      case .right:
        animatedX = point.x + animationOffset
        animatedY = point.y
      case .up:
        animatedX = point.x
        animatedY = point.y - animationOffset
      case .down:
        animatedX = point.x
        animatedY = point.y + animationOffset
      }

      animatedPoint = Point(animatedX, animatedY)
      finalTint = tint
      usePrerendered = false
      alpha = 1.0

    case .fade:
      // Quick fade in, wait, slower fade out, repeating cycle
      // Total cycle: 0.3s fade in + 0.7s wait + 1.0s fade out = 2.0s
      let fadeInDuration: Float = 0.4
      let waitDuration: Float = 0.5
      let fadeOutDuration: Float = 0.6
      let cycleDuration: Float = 2.0

      let cycleTime = animationTime.truncatingRemainder(dividingBy: cycleDuration)
      let calculatedAlpha: Float

      if cycleTime < fadeInDuration {
        // Fade in phase - quick, eased
        let progress = cycleTime / fadeInDuration
        let easedProgress = Easing.easeOutCubic.apply(progress)
        calculatedAlpha = easedProgress
      } else if cycleTime < fadeInDuration + waitDuration {
        // Wait phase - full opacity
        calculatedAlpha = 1.0
      } else {
        // Fade out phase - slower, eased
        let fadeOutStart = fadeInDuration + waitDuration
        let fadeOutTime = cycleTime - fadeOutStart
        let progress = fadeOutTime / fadeOutDuration
        let easedProgress = Easing.easeInCubic.apply(progress)
        calculatedAlpha = 1.0 - easedProgress
      }

      animatedPoint = point  // No position change
      finalTint = tint
      usePrerendered = (strokeWidth ?? 0) > 0 && strokeColor != nil  // Use prerendered when stroke is present
      alpha = calculatedAlpha

    case .blink:
      // Blink animation: visible for 600ms, hidden for 400ms (similar to macOS text cursor)
      // Total cycle: 1000ms
      let visibleDuration: Float = 0.6
      //let hiddenDuration: Float = 0.4
      let cycleDuration: Float = 1.0

      let cycleTime = animationTime.truncatingRemainder(dividingBy: cycleDuration)
      let calculatedAlpha: Float = cycleTime < visibleDuration ? 1.0 : 0.0

      animatedPoint = point  // No position change
      finalTint = tint
      usePrerendered = (strokeWidth ?? 0) > 0 && strokeColor != nil  // Use prerendered when stroke is present
      alpha = calculatedAlpha
    }

    // Calculate size based on direction
    let elongatedWidth: Float
    let elongatedHeight: Float

    switch direction {
    case .left, .right:
      elongatedWidth = originalSize.width * scale * 1.5  // Make wider
      elongatedHeight = originalSize.height * scale  // Keep height at half
    case .up, .down:
      elongatedWidth = originalSize.width * scale * 0.75  // Make narrower
      elongatedHeight = originalSize.height * scale * 1.75  // Make taller
    }

    rect = Rect(origin: animatedPoint, size: Size(elongatedWidth, elongatedHeight))

    // Draw with tint by directly calling the renderer
    if let context = GraphicsContext.current {
      if usePrerendered {
        // Use prerendered image with stroke baked in, then fade as a single unit
        let prerendered = getOrCreatePrerenderedImage(
          size: Size(elongatedWidth, elongatedHeight),
          tint: tint,
          strokeWidth: strokeWidth!,
          strokeColor: strokeColor!
        )
        // FIXME: This is a hack; should be handled by the renderer by respecting `isFlipped`
        rect.origin.y += rect.size.height
        rect.size.height *= -1
        prerendered.draw(in: rect, tint: finalTint.withAlphaComponent(alpha), context: context)
      } else {
        // Draw normally (move animation or no stroke)
        context.renderer.drawImage(
          textureID: image.textureID,
          in: rect,
          tint: finalTint,
          strokeWidth: strokeWidth ?? 0,
          strokeColor: strokeColor
        )
      }
    }
  }
}
