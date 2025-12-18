/// TODO: docs
public struct Animation {
  public let name: String?
  public let duration: Double  // Duration in ticks
  public let ticksPerSecond: Double
  public let channels: [AnimationChannel]

  public init(
    name: String? = nil,
    duration: Double,
    ticksPerSecond: Double = 25.0,
    channels: [AnimationChannel]
  ) {
    self.name = name
    self.duration = duration
    self.ticksPerSecond = ticksPerSecond
    self.channels = channels
  }
}

/// Animation channel for a specific node
public struct AnimationChannel {
  public let nodeName: String
  public let positionKeys: [VectorKey]
  public let rotationKeys: [QuatKey]
  public let scalingKeys: [VectorKey]

  public init(
    nodeName: String,
    positionKeys: [VectorKey] = [],
    rotationKeys: [QuatKey] = [],
    scalingKeys: [VectorKey] = []
  ) {
    self.nodeName = nodeName
    self.positionKeys = positionKeys
    self.rotationKeys = rotationKeys
    self.scalingKeys = scalingKeys
  }
}

/// Vector key for position/scale animation
public struct VectorKey {
  public let time: Double
  public let value: vec3

  public init(time: Double, value: vec3) {
    self.time = time
    self.value = value
  }
}

/// Quaternion key for rotation animation
public struct QuatKey {
  public let time: Double
  public let value: Quaternion<Float>  // (w, x, y, z)

  public init(time: Double, value: Quaternion<Float>) {
    self.time = time
    self.value = value
  }
}
