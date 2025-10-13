import Foundation
import GLMath

extension Transform2D {
  /// Converts the Transform2D to a 4x4 matrix for OpenGL
  public func toMatrix() -> mat4 {
    // Create translation matrix
    let translationMatrix = mat4(
      vec4(1, 0, 0, 0),
      vec4(0, 1, 0, 0),
      vec4(0, 0, 1, 0),
      vec4(translation.x, translation.y, 0, 1)
    )

    // Create rotation matrix (around Z axis)
    let cosR = cos(rotation)
    let sinR = sin(rotation)
    let rotationMatrix = mat4(
      vec4(cosR, -sinR, 0, 0),
      vec4(sinR, cosR, 0, 0),
      vec4(0, 0, 1, 0),
      vec4(0, 0, 0, 1)
    )

    // Create scale matrix
    let scaleMatrix = mat4(
      vec4(scale.x, 0, 0, 0),
      vec4(0, scale.y, 0, 0),
      vec4(0, 0, 1, 0),
      vec4(0, 0, 0, 1)
    )

    // Combine: T * R * S
    return translationMatrix * rotationMatrix * scaleMatrix
  }
}
