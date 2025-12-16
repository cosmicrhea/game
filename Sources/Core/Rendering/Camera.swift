/// Represents a camera with perspective or orthographic projection settings.
/// Supports both perspective (FOV-based) and orthographic (parallel projection) cameras.
/// Used for scene cameras, viewport rendering, and prerendered environment integration.
public struct Camera {
  public let name: String?

  /// Horizontal field of view angle, in radians (for perspective cameras)
  /// For orthographic cameras, this is 0
  public let horizontalFOV: Float

  /// Distance of the near clipping plane from the camera
  public let clipPlaneNear: Float

  /// Distance of the far clipping plane from the camera
  public let clipPlaneFar: Float

  /// Screen aspect ratio (width/height)
  /// 0 if not defined
  public let aspect: Float

  /// Half horizontal orthographic width, in scene units (for orthographic cameras)
  /// 0 if perspective camera
  public let orthographicWidth: Float

  /// Whether this is an orthographic camera
  public var isOrthographic: Bool {
    return orthographicWidth > 0.0 || horizontalFOV == 0.0
  }

  public init(
    name: String? = nil,
    horizontalFOV: Float = 0.0,
    clipPlaneNear: Float = 0.1,
    clipPlaneFar: Float = 1000.0,
    aspect: Float = 0.0,
    orthographicWidth: Float = 0.0
  ) {
    self.name = name
    self.horizontalFOV = horizontalFOV
    self.clipPlaneNear = clipPlaneNear
    self.clipPlaneFar = clipPlaneFar
    self.aspect = aspect
    self.orthographicWidth = orthographicWidth
  }
}

extension Camera: CustomDebugStringConvertible {
  public var debugDescription: String {
    let typeStr = isOrthographic ? "orthographic" : "perspective"
    return
      "Camera(name: \(name ?? "nil"), type: \(typeStr), fov: \(horizontalFOV), aspect: \(aspect), near: \(clipPlaneNear), far: \(clipPlaneFar), orthoWidth: \(orthographicWidth))"
  }
}

// GLTF conversion
import GLTF

extension Camera {
  init(gltfCamera: GLTFCamera) {
    self.name = gltfCamera.name.isEmpty ? nil : gltfCamera.name

    switch gltfCamera.type {
    case .perspective:
      let perspective = gltfCamera.perspective
      // GLTF uses vertical FOV (yfov), convert to horizontal FOV
      // If aspect ratio is available, use it; otherwise default to 16:9
      let aspectRatio = perspective.hasAspectRatio ? perspective.aspectRatio : (16.0 / 9.0)
      // Convert vertical FOV to horizontal FOV: hfov = 2 * atan(tan(vfov/2) * aspect)
      let vfovHalf = perspective.yfov / 2.0
      let hfov = 2.0 * atan(tan(vfovHalf) * aspectRatio)

      self.horizontalFOV = hfov
      self.clipPlaneNear = perspective.znear
      self.clipPlaneFar = perspective.hasZFar ? perspective.zfar : 1000.0
      self.aspect = perspective.hasAspectRatio ? perspective.aspectRatio : 0.0
      self.orthographicWidth = 0.0

    case .orthographic:
      let orthographic = gltfCamera.orthographic
      // GLTF orthographic uses xmag and ymag (half-width and half-height)
      // Store xmag as orthographicWidth (half-width)
      self.horizontalFOV = 0.0
      self.clipPlaneNear = orthographic.znear
      self.clipPlaneFar = orthographic.zfar
      // Calculate aspect from xmag/ymag
      let aspectRatio = orthographic.ymag > 0.0 ? (orthographic.xmag / orthographic.ymag) : 0.0
      self.aspect = aspectRatio
      self.orthographicWidth = orthographic.xmag

    case .invalid:
      // Fallback to default perspective camera
      self.horizontalFOV = .pi / 4.0  // 45 degrees
      self.clipPlaneNear = 0.1
      self.clipPlaneFar = 1000.0
      self.aspect = 0.0
      self.orthographicWidth = 0.0
    @unknown default:
      // Fallback to default perspective camera
      self.horizontalFOV = .pi / 4.0  // 45 degrees
      self.clipPlaneNear = 0.1
      self.clipPlaneFar = 1000.0
      self.aspect = 0.0
      self.orthographicWidth = 0.0
    }
  }
}
