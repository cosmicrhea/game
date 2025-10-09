import Foundation
import GLFW

/// Demo showcasing bezier path drawing capabilities
public class PathDemo: RenderLoop {
  private var time: Float = 0

  public init() {}

  public func update(window: GLFWWindow, deltaTime: Float) {
    time += deltaTime
  }

  public func draw() {
    guard let context = GraphicsContext.current else { return }

    let centerX = 400.0
    let centerY = 300.0

    // Draw a simple rounded rectangle
    let roundedRect = Rect(x: 50, y: 50, width: 200, height: 100)
    context.drawRoundedRect(roundedRect, cornerRadius: 20, color: Color(0, 0, 1))

    // Draw a stroked rounded rectangle
    let strokedRect = Rect(x: 300, y: 50, width: 200, height: 100)
    context.drawStrokeRoundedRect(strokedRect, cornerRadius: 20, color: Color(1, 0, 0), lineWidth: 3)

    // Draw a custom bezier path - a heart shape
    var heartPath = BezierPath()
    let heartX = Float(centerX)
    let heartY = Float(centerY)
    let heartSize: Float = 50

    // Heart shape using cubic bezier curves
    heartPath.move(to: Point(heartX, heartY + heartSize * 0.3))
    heartPath.addCurve(
      to: Point(heartX - heartSize * 0.5, heartY - heartSize * 0.3),
      control1: Point(heartX - heartSize * 0.25, heartY + heartSize * 0.5),
      control2: Point(heartX - heartSize * 0.5, heartY)
    )
    heartPath.addCurve(
      to: Point(heartX, heartY - heartSize * 0.8),
      control1: Point(heartX - heartSize * 0.5, heartY - heartSize * 0.6),
      control2: Point(heartX - heartSize * 0.25, heartY - heartSize * 0.8)
    )
    heartPath.addCurve(
      to: Point(heartX + heartSize * 0.5, heartY - heartSize * 0.3),
      control1: Point(heartX + heartSize * 0.25, heartY - heartSize * 0.8),
      control2: Point(heartX + heartSize * 0.5, heartY - heartSize * 0.6)
    )
    heartPath.addCurve(
      to: Point(heartX, heartY + heartSize * 0.3),
      control1: Point(heartX + heartSize * 0.5, heartY),
      control2: Point(heartX + heartSize * 0.25, heartY + heartSize * 0.5)
    )
    heartPath.closePath()

    context.drawPath(heartPath, color: Color(1, 0, 0))

    // Draw an animated wave using quadratic curves
    var wavePath = BezierPath()
    let waveY = Float(centerY + 150)
    let waveWidth: Float = 300
    let waveHeight: Float = 30
    let waveOffset = sin(time * 2) * 20

    wavePath.move(to: Point(heartX - waveWidth / 2, waveY))

    for i in 0..<4 {
      let x1 = heartX - waveWidth / 2 + Float(i) * waveWidth / 4
      let x2 = heartX - waveWidth / 2 + Float(i + 1) * waveWidth / 4
      let controlX = (x1 + x2) / 2
      let controlY = waveY + waveHeight + Float(waveOffset)

      wavePath.addQuadCurve(
        to: Point(x2, waveY),
        control: Point(controlX, controlY)
      )
    }

    context.drawStroke(wavePath, color: Color(0, 1, 0), lineWidth: 2)

    // Draw a simple circle using quadratic curves
    var circlePath = BezierPath()
    let circleRadius: Float = 40
    let circleX = heartX + 150
    let circleY = heartY - 100

    // Circle using 4 quadratic curves
    circlePath.move(to: Point(circleX + circleRadius, circleY))
    circlePath.addQuadCurve(
      to: Point(circleX, circleY + circleRadius),
      control: Point(circleX + circleRadius, circleY + circleRadius)
    )
    circlePath.addQuadCurve(
      to: Point(circleX - circleRadius, circleY),
      control: Point(circleX - circleRadius, circleY + circleRadius)
    )
    circlePath.addQuadCurve(
      to: Point(circleX, circleY - circleRadius),
      control: Point(circleX - circleRadius, circleY - circleRadius)
    )
    circlePath.addQuadCurve(
      to: Point(circleX + circleRadius, circleY),
      control: Point(circleX + circleRadius, circleY - circleRadius)
    )
    circlePath.closePath()

    context.drawPath(circlePath, color: .purple)
  }
}
