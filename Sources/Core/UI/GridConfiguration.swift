import GLMath

/// Configuration for a grid layout
public struct GridConfiguration {
  public let columns: Int
  public let rows: Int
  public let cellSize: Float
  public let spacing: Float
  public let cornerRadius: Float
  public let radialGradientStrength: Float
  public let selectionWraps: Bool

  public init(
    columns: Int,
    rows: Int,
    cellSize: Float = 80.0,
    spacing: Float = 2.0,
    cornerRadius: Float = 3.0,
    radialGradientStrength: Float = 0.6,
    selectionWraps: Bool = false
  ) {
    self.columns = columns
    self.rows = rows
    self.cellSize = cellSize
    self.spacing = spacing
    self.cornerRadius = cornerRadius
    self.radialGradientStrength = radialGradientStrength
    self.selectionWraps = selectionWraps
  }
}
