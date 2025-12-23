/// Shared animation controller for a scene
/// Animations target nodes, not meshes, so multiple meshes can share the same animation state
class AnimationController {
  private var animationTime: Double = 0.0
  private var isPlaying: Bool = false
  private var currentAnimation: Animation?

  /// Current animated node transforms (node name -> transform matrix)
  private var animatedNodeTransforms: [String: mat4] = [:]

  /// Start playing an animation
  func play(animation: Animation) {
    currentAnimation = animation
    isPlaying = true
    animationTime = 0.0
    animatedNodeTransforms.removeAll()
  }

  /// Pause the current animation
  func pause() {
    isPlaying = false
  }

  /// Resume the current animation
  func resume() {
    isPlaying = true
  }

  /// Stop the current animation
  func stop() {
    isPlaying = false
    animationTime = 0.0
    animatedNodeTransforms.removeAll()
  }

  /// Whether animation is playing
  var playing: Bool {
    get { isPlaying }
    set { isPlaying = newValue }
  }

  /// Current animation time
  var time: Double {
    get { animationTime }
    set { animationTime = newValue }
  }

  /// Update animation with delta time
  func update(deltaTime: Float) {
    guard let animation = currentAnimation else {
      animatedNodeTransforms.removeAll()
      return
    }

    // Update time only when playing
    if isPlaying {
      let tps = animation.ticksPerSecond > 0 ? animation.ticksPerSecond : 1.0
      animationTime += Double(deltaTime) * tps

      // Loop
      if animationTime >= animation.duration {
        animationTime = animationTime.truncatingRemainder(dividingBy: animation.duration)
      }
    }

    // Calculate animated node transforms at current time (even when paused)
    animatedNodeTransforms.removeAll()
    for channel in animation.channels {
      let nodeName = channel.nodeName
      let transform = calculateAnimatedTransform(channel: channel, time: animationTime)
      animatedNodeTransforms[nodeName] = transform
    }

  }

  /// Get animated node transforms for use by mesh instances
  func getAnimatedNodeTransforms() -> [String: mat4] {
    return animatedNodeTransforms
  }

  // MARK: - Private Helpers

  private func calculateAnimatedTransform(channel: AnimationChannel, time: Double) -> mat4 {
    let pos = interpolateVector(keys: channel.positionKeys, time: time, defaultValue: vec3(0))
    let rot = interpolateQuaternion(keys: channel.rotationKeys, time: time)
    let scale = interpolateVector(keys: channel.scalingKeys, time: time, defaultValue: vec3(1))

    // Build transform matrix
    // For column-major matrices: T * R * S means apply S first, then R, then T (read right to left)
    // This is the standard order: scale -> rotate -> translate
    let t = GLMath.translate(mat4(1), pos)
    let r = quatToMatrix(rot)
    let s = GLMath.scale(mat4(1), scale)

    // Standard order: T * R * S (for column-major, this applies S, then R, then T)
    // But maybe GLTF needs a different order? Let's try both and see
    // Try: S * R * T (would apply T, then R, then S - probably wrong)
    // Standard: T * R * S (applies S, then R, then T - this is correct)
    return t * r * s
  }

  private func interpolateVector(keys: [VectorKey], time: Double, defaultValue: vec3) -> vec3 {
    guard !keys.isEmpty else { return defaultValue }
    if keys.count == 1 { return keys[0].value }

    for i in 0..<keys.count - 1 {
      if time >= keys[i].time && time <= keys[i + 1].time {
        let t1 = keys[i].time
        let t2 = keys[i + 1].time
        let factor = Float((time - t1) / (t2 - t1))
        return keys[i].value + (keys[i + 1].value - keys[i].value) * factor
      }
    }
    return keys.last!.value
  }

  private func interpolateQuaternion(keys: [QuatKey], time: Double) -> Quaternion<Float> {
    // Identity quaternion is (x:0, y:0, z:0, w:1)
    guard !keys.isEmpty else { return Quaternion<Float>(0, 0, 0, 1) }
    if keys.count == 1 { return normalize(keys[0].value) }

    for i in 0..<keys.count - 1 {
      if time >= keys[i].time && time <= keys[i + 1].time {
        let t1 = keys[i].time
        let t2 = keys[i + 1].time
        let factor = Float((time - t1) / (t2 - t1))
        return normalize(slerp(keys[i].value, keys[i + 1].value, factor))
      }
    }
    return normalize(keys.last!.value)
  }

  private func slerp(_ q1: Quaternion<Float>, _ q2: Quaternion<Float>, _ t: Float) -> Quaternion<Float> {
    var q2 = q2
    var dot = q1.x * q2.x + q1.y * q2.y + q1.z * q2.z + q1.w * q2.w

    if dot < 0 {
      q2 = Quaternion<Float>(-q2.x, -q2.y, -q2.z, -q2.w)
      dot = -dot
    }

    if dot > 0.9995 {
      return normalize(
        Quaternion<Float>(
          q1.x + t * (q2.x - q1.x),
          q1.y + t * (q2.y - q1.y),
          q1.z + t * (q2.z - q1.z),
          q1.w + t * (q2.w - q1.w)
        ))
    }

    let theta = acos(dot)
    let sinTheta = sin(theta)
    let w1 = sin((1 - t) * theta) / sinTheta
    let w2 = sin(t * theta) / sinTheta

    return Quaternion<Float>(
      w1 * q1.x + w2 * q2.x,
      w1 * q1.y + w2 * q2.y,
      w1 * q1.z + w2 * q2.z,
      w1 * q1.w + w2 * q2.w
    )
  }

  private func normalize(_ q: Quaternion<Float>) -> Quaternion<Float> {
    let len = sqrt(q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w)
    guard len > 0 else { return Quaternion<Float>(0, 0, 0, 1) }
    return Quaternion<Float>(q.x / len, q.y / len, q.z / len, q.w / len)
  }

  private func quatToMatrix(_ q: Quaternion<Float>) -> mat4 {
    let x = q.x, y = q.y, z = q.z, w = q.w
    let x2 = x + x, y2 = y + y, z2 = z + z
    let xx = x * x2, xy = x * y2, xz = x * z2
    let yy = y * y2, yz = y * z2, zz = z * z2
    let wx = w * x2, wy = w * y2, wz = w * z2

    return mat4(
      1 - (yy + zz), xy + wz, xz - wy, 0,
      xy - wz, 1 - (xx + zz), yz + wx, 0,
      xz + wy, yz - wx, 1 - (xx + yy), 0,
      0, 0, 0, 1
    )
  }
}
