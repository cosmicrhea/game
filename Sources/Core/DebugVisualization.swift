import Foundation

/// A reusable debug visualization system for 3D scenes
/// Provides orthographic viewports (top, side, front) showing camera, lights, and objects
public class DebugVisualization {

  // MARK: - Configuration

  public struct Config {
    public var viewportSize: Float = 200
    public var margin: Float = 20
    public var spacing: Float = 10
    public var scale: Float = 100
    public var gridSpacing: Float = 20
    public var showGrid: Bool = true
    public var showLabels: Bool = true

    public init() {}
  }

  public struct SceneData {
    public var cameraPosition: vec3
    public var cameraTarget: vec3
    public var cameraRotation: Float
    public var lights: [LightData]
    public var objects: [ObjectData]

    public init(
      cameraPosition: vec3, cameraTarget: vec3, cameraRotation: Float, lights: [LightData] = [],
      objects: [ObjectData] = []
    ) {
      self.cameraPosition = cameraPosition
      self.cameraTarget = cameraTarget
      self.cameraRotation = cameraRotation
      self.lights = lights
      self.objects = objects
    }
  }

  public struct LightData {
    public var position: vec3
    public var direction: vec3
    public var color: vec3
    public var intensity: Float
    public var name: String?

    public init(position: vec3, direction: vec3, color: vec3, intensity: Float, name: String? = nil) {
      self.position = position
      self.direction = direction
      self.color = color
      self.intensity = intensity
      self.name = name
    }
  }

  public struct ObjectData {
    public var position: vec3
    public var rotation: Float
    public var size: Float
    public var color: Color
    public var name: String?

    public init(position: vec3, rotation: Float, size: Float, color: Color, name: String? = nil) {
      self.position = position
      self.rotation = rotation
      self.size = size
      self.color = color
      self.name = name
    }
  }

  // MARK: - Properties

  private let config: Config
  private var isVisible: Bool = false

  // MARK: - Initialization

  public init(config: Config = Config()) {
    self.config = config
  }

  // MARK: - Public Interface

  public func toggle() {
    isVisible.toggle()
  }

  public func show() {
    isVisible = true
  }

  public func hide() {
    isVisible = false
  }

  public func draw(sceneData: SceneData, at position: Point) {
    guard isVisible else { return }

    let viewportSize = config.viewportSize
    let margin = config.margin
    let spacing = config.spacing

    // Calculate positions for three viewports
    let topY = position.y - margin - viewportSize
    let sideY = topY - viewportSize - spacing
    let frontY = sideY - viewportSize - spacing

    let rightX = position.x - margin - viewportSize

    // Draw three orthographic views
    drawTopView(at: Point(rightX, topY), size: viewportSize, sceneData: sceneData)
    drawSideView(at: Point(rightX, sideY), size: viewportSize, sceneData: sceneData)
    drawFrontView(at: Point(rightX, frontY), size: viewportSize, sceneData: sceneData)
  }

  // MARK: - View Drawing

  private func drawTopView(at position: Point, size: Float, sceneData: SceneData) {
    // Top-down view (XZ plane)
    let scale = config.scale

    if config.showGrid {
      drawGrid(at: position, size: size, color: .gray500)
    }

    // Draw objects
    for object in sceneData.objects {
      let objectPos = Point(
        position.x + size / 2 + object.position.x * scale,
        position.y + size / 2 + object.position.z * scale
      )
      drawCube(at: objectPos, size: object.size, color: object.color, rotation: object.rotation)
    }

    // Draw camera
    let cameraOffset = sceneData.cameraPosition - sceneData.cameraTarget
    let cameraScreenPos = Point(
      position.x + size / 2 + cameraOffset.x * scale,
      position.y + size / 2 + cameraOffset.z * scale
    )
    let cameraDirection = sceneData.cameraTarget - sceneData.cameraPosition
    drawCamera(at: cameraScreenPos, direction: cameraDirection, color: .blue)

    // Draw lights
    for light in sceneData.lights {
      let lightPos = Point(
        position.x + size / 2 + light.position.x * scale,
        position.y + size / 2 + light.position.z * scale
      )
      drawLightWithDirection(
        at: lightPos, direction: light.direction,
        color: Color(light.color.x, light.color.y, light.color.z),
        intensity: light.intensity)
    }

    if config.showLabels {
      "Top View".draw(at: Point(position.x + 5, position.y + 5), style: .itemDescription, anchor: .bottomLeft)
    }
  }

  private func drawSideView(at position: Point, size: Float, sceneData: SceneData) {
    // Side view (YZ plane)
    let scale = config.scale

    if config.showGrid {
      drawGrid(at: position, size: size, color: .gray500)
    }

    // Draw objects
    for object in sceneData.objects {
      let objectPos = Point(
        position.x + size / 2 + object.position.x * scale,
        position.y + size / 2 + object.position.y * scale
      )
      drawCube(at: objectPos, size: object.size, color: object.color, rotation: object.rotation)
    }

    // Draw camera
    let cameraOffset = sceneData.cameraPosition - sceneData.cameraTarget
    let cameraScreenPos = Point(
      position.x + size / 2 + cameraOffset.x * scale,
      position.y + size / 2 + cameraOffset.y * scale
    )
    let cameraDirection = sceneData.cameraTarget - sceneData.cameraPosition
    drawCamera(at: cameraScreenPos, direction: cameraDirection, color: .blue)

    // Draw lights
    for light in sceneData.lights {
      let lightPos = Point(
        position.x + size / 2 + light.position.x * scale,
        position.y + size / 2 + light.position.y * scale
      )
      // Project 3D direction to 2D (X, Y plane)
      let lightDir2D = vec3(light.direction.x, light.direction.y, 0)
      drawLightWithDirection(
        at: lightPos, direction: lightDir2D,
        color: Color(light.color.x, light.color.y, light.color.z),
        intensity: light.intensity)
    }

    if config.showLabels {
      "Side View".draw(at: Point(position.x + 5, position.y + 5), style: .itemDescription, anchor: .bottomLeft)
    }
  }

  private func drawFrontView(at position: Point, size: Float, sceneData: SceneData) {
    // Front view (XY plane)
    let scale = config.scale

    if config.showGrid {
      drawGrid(at: position, size: size, color: .gray500)
    }

    // Draw objects
    for object in sceneData.objects {
      let objectPos = Point(
        position.x + size / 2 + object.position.x * scale,
        position.y + size / 2 + object.position.y * scale
      )
      drawCube(at: objectPos, size: object.size, color: object.color, rotation: object.rotation)
    }

    // Draw camera
    let cameraOffset = sceneData.cameraPosition - sceneData.cameraTarget
    let cameraScreenPos = Point(
      position.x + size / 2 + cameraOffset.x * scale,
      position.y + size / 2 + cameraOffset.y * scale
    )
    let cameraDirection = sceneData.cameraTarget - sceneData.cameraPosition
    drawCamera(at: cameraScreenPos, direction: cameraDirection, color: .blue)

    // Draw lights
    for light in sceneData.lights {
      let lightPos = Point(
        position.x + size / 2 + light.position.x * scale,
        position.y + size / 2 + light.position.y * scale
      )
      // Project 3D direction to 2D (X, Y plane)
      let lightDir2D = vec3(light.direction.x, light.direction.y, 0)
      drawLightWithDirection(
        at: lightPos, direction: lightDir2D,
        color: Color(light.color.x, light.color.y, light.color.z),
        intensity: light.intensity)
    }

    if config.showLabels {
      "Front View".draw(at: Point(position.x + 5, position.y + 5), style: .itemDescription, anchor: .bottomLeft)
    }
  }

  // MARK: - Helper Drawing Methods

  private func drawGrid(at position: Point, size: Float, color: Color) {
    let gridSpacing = config.gridSpacing
    let lineColor = color.withAlphaComponent(0.3)

    // Vertical lines
    for i in stride(from: 0, through: size, by: gridSpacing) {
      let start = Point(position.x + i, position.y)
      let end = Point(position.x + i, position.y + size)
      drawLine(from: start, to: end, color: lineColor)
    }

    // Horizontal lines
    for i in stride(from: 0, through: size, by: gridSpacing) {
      let start = Point(position.x, position.y + i)
      let end = Point(position.x + size, position.y + i)
      drawLine(from: start, to: end, color: lineColor)
    }

    // Border
    let borderRect = Rect(x: position.x, y: position.y, width: size, height: size)
    borderRect.frame(with: color)
  }

  private func drawCamera(at position: Point, direction: vec3, color: Color) {
    // Draw camera as a triangle pointing in direction
    let normalizedDir = normalize(direction)
    let angle = atan2(normalizedDir.x, normalizedDir.z)

    let size: Float = 12
    let x1 = position.x + cos(angle) * size
    let y1 = position.y + sin(angle) * size
    let x2 = position.x + cos(angle + 2.4) * size * 0.6
    let y2 = position.y + sin(angle + 2.4) * size * 0.6
    let x3 = position.x + cos(angle - 2.4) * size * 0.6
    let y3 = position.y + sin(angle - 2.4) * size * 0.6

    // Draw triangle
    drawTriangle(
      Point(x1, y1), Point(x2, y2), Point(x3, y3),
      color: color, filled: true
    )
  }

  private func drawLightWithDirection(at position: Point, direction: vec3, color: Color, intensity: Float) {
    // Draw light position as a circle
    let radius = min(8 + intensity * 2, 16)
    drawCircle(at: position, radius: radius, color: color, filled: true)

    // Draw direction arrow (normalized direction)
    let normalizedDir = normalize(direction)
    let arrowLength: Float = 20
    let endX = position.x + normalizedDir.x * arrowLength
    let endY = position.y + normalizedDir.z * arrowLength  // Use Z for top view

    // Draw main direction arrow
    drawArrow(from: position, to: Point(endX, endY), color: color, lineWidth: 3)

    // Draw some reference rays around the light
    let rayLength: Float = 12
    for i in 0..<6 {
      let angle = Float(i) * .pi / 3
      let endRayX = position.x + cos(angle) * rayLength
      let endRayY = position.y + sin(angle) * rayLength
      drawLine(from: position, to: Point(endRayX, endRayY), color: color.withAlphaComponent(0.4))
    }
  }

  private func drawArrow(from start: Point, to end: Point, color: Color, lineWidth: Float) {
    // Draw main line
    drawLine(from: start, to: end, color: color)

    // Draw arrowhead
    let direction = Point(end.x - start.x, end.y - start.y)
    let length = sqrt(direction.x * direction.x + direction.y * direction.y)
    if length > 0 {
      let normalizedDir = Point(direction.x / length, direction.y / length)
      let arrowSize: Float = 6
      let perpX = -normalizedDir.y
      let perpY = normalizedDir.x

      // Arrowhead points
      let arrowPoint1 = Point(
        end.x - normalizedDir.x * arrowSize + perpX * arrowSize * 0.5,
        end.y - normalizedDir.y * arrowSize + perpY * arrowSize * 0.5
      )
      let arrowPoint2 = Point(
        end.x - normalizedDir.x * arrowSize - perpX * arrowSize * 0.5,
        end.y - normalizedDir.y * arrowSize - perpY * arrowSize * 0.5
      )

      // Draw arrowhead
      drawLine(from: end, to: arrowPoint1, color: color)
      drawLine(from: end, to: arrowPoint2, color: color)
    }
  }

  private func drawCircle(at center: Point, radius: Float, color: Color, filled: Bool) {
    // Create a circle using BezierPath
    var path = BezierPath()

    // Create a circle by approximating with line segments
    let segments = 16
    let angleStep = Float.pi * 2 / Float(segments)

    // Start at the rightmost point
    let startX = center.x + radius
    let startY = center.y
    path.move(to: Point(startX, startY))

    // Add line segments around the circle
    for i in 1...segments {
      let angle = Float(i) * angleStep
      let x = center.x + cos(angle) * radius
      let y = center.y + sin(angle) * radius
      path.addLine(to: Point(x, y))
    }

    path.closePath()

    // Draw using the renderer
    if filled {
      GraphicsContext.current?.renderer.drawPath(path, color: color)
    } else {
      GraphicsContext.current?.renderer.drawStroke(path, color: color, lineWidth: 2)
    }
  }

  private func drawLine(from start: Point, to end: Point, color: Color) {
    var path = BezierPath()
    path.move(to: start)
    path.addLine(to: end)
    GraphicsContext.current?.renderer.drawStroke(path, color: color, lineWidth: 1)
  }

  private func drawTriangle(_ p1: Point, _ p2: Point, _ p3: Point, color: Color, filled: Bool) {
    var path = BezierPath()
    path.move(to: p1)
    path.addLine(to: p2)
    path.addLine(to: p3)
    path.closePath()

    // Draw using the renderer
    if filled {
      GraphicsContext.current?.renderer.drawPath(path, color: color)
    } else {
      GraphicsContext.current?.renderer.drawStroke(path, color: color, lineWidth: 2)
    }
  }

  private func drawCube(at center: Point, size: Float, color: Color, rotation: Float) {
    // Draw a cube outline to show rotation
    let halfSize = size / 2
    let cosR = cos(radians(rotation))
    let sinR = sin(radians(rotation))

    // Define cube corners (before rotation)
    let corners = [
      Point(-halfSize, -halfSize),  // bottom-left
      Point(halfSize, -halfSize),  // bottom-right
      Point(halfSize, halfSize),  // top-right
      Point(-halfSize, halfSize),  // top-left
    ]

    // Rotate corners around center
    let rotatedCorners = corners.map { corner in
      let x = corner.x * cosR - corner.y * sinR
      let y = corner.x * sinR + corner.y * cosR
      return Point(center.x + x, center.y + y)
    }

    // Draw cube outline
    var path = BezierPath()
    path.move(to: rotatedCorners[0])
    for i in 1..<rotatedCorners.count {
      path.addLine(to: rotatedCorners[i])
    }
    path.closePath()

    // Draw the outline
    GraphicsContext.current?.renderer.drawStroke(path, color: color, lineWidth: 2)

    // Draw a small cross in the center to show orientation
    let crossSize: Float = 4
    var crossPath = BezierPath()
    crossPath.move(to: Point(center.x - crossSize, center.y))
    crossPath.addLine(to: Point(center.x + crossSize, center.y))
    crossPath.move(to: Point(center.x, center.y - crossSize))
    crossPath.addLine(to: Point(center.x, center.y + crossSize))

    GraphicsContext.current?.renderer.drawStroke(crossPath, color: color, lineWidth: 1)
  }
}
