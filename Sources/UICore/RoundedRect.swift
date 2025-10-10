import Foundation

/// A rounded rectangle UI primitive that can be drawn with fill or stroke.
public struct RoundedRect {
  /// The rectangle bounds.
  public let rect: Rect
  /// The radius of the rounded corners.
  public let cornerRadius: Float

  /// Creates a rounded rectangle with the specified bounds and corner radius.
  /// - Parameters:
  ///   - rect: The rectangle bounds.
  ///   - cornerRadius: The radius of the rounded corners.
  public init(_ rect: Rect, cornerRadius: Float) {
    self.rect = rect
    self.cornerRadius = cornerRadius
  }

  /// Creates a rounded rectangle with the specified coordinates and corner radius.
  /// - Parameters:
  ///   - x: The x-coordinate of the origin.
  ///   - y: The y-coordinate of the origin.
  ///   - width: The width of the rectangle.
  ///   - height: The height of the rectangle.
  ///   - cornerRadius: The radius of the rounded corners.
  public init(x: Float, y: Float, width: Float, height: Float, cornerRadius: Float) {
    self.rect = Rect(x: x, y: y, width: width, height: height)
    self.cornerRadius = cornerRadius
  }

  /// Draws the rounded rectangle filled with the specified color.
  /// - Parameters:
  ///   - color: The color to fill the rectangle with.
  ///   - context: Target `GraphicsContext`; defaults to `GraphicsContext.current`.
  public func draw(color: Color, context: GraphicsContext? = nil) {
    let ctx = context ?? GraphicsContext.current
    guard let ctx else { return }
    ctx.drawRoundedRect(rect, cornerRadius: cornerRadius, color: color)
  }

  /// Draws the rounded rectangle stroked with the specified color and line width.
  /// - Parameters:
  ///   - color: The color to stroke the rectangle with.
  ///   - lineWidth: The width of the stroke.
  ///   - context: Target `GraphicsContext`; defaults to `GraphicsContext.current`.
  public func stroke(color: Color, lineWidth: Float, context: GraphicsContext? = nil) {
    let ctx = context ?? GraphicsContext.current
    guard let ctx else { return }
    ctx.drawStrokeRoundedRect(rect, cornerRadius: cornerRadius, color: color, lineWidth: lineWidth)
  }
}
