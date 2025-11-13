import Assimp

/// A class that can play NodeAnimations from Assimp scenes
class NodeAnimator {
  private var currentTime: Double = 0.0
  private var isPlaying: Bool = false
  private var animation: Animation?
  private var nodeTransforms: [String: mat4] = [:]

  /// Current animation time in ticks
  var animationTime: Double {
    get { currentTime }
    set { currentTime = newValue }
  }

  /// Whether the animator is currently playing
  var playing: Bool {
    get { isPlaying }
    set { isPlaying = newValue }
  }

  /// Start playing an animation
  func play(animation: Animation) {
    self.animation = animation
    self.isPlaying = true
    self.currentTime = 0.0
  }

  /// Stop the current animation
  func stop() {
    self.isPlaying = false
  }

  /// Pause the current animation
  func pause() {
    self.isPlaying = false
  }

  /// Resume the current animation
  func resume() {
    self.isPlaying = true
  }

  /// Update the animator with delta time
  func update(deltaTime: Float) {
    guard let animation = animation, isPlaying else { return }

    // Update animation time
    let ticksPerSecond = animation.ticksPerSecond > 0 ? animation.ticksPerSecond : 25.0
    currentTime += Double(deltaTime) * ticksPerSecond

    // Handle animation looping
    if currentTime >= animation.duration {
      currentTime = currentTime.truncatingRemainder(dividingBy: animation.duration)
    }

    // Update node transforms
    updateNodeTransforms()
  }

  /// Get the transform matrix for a specific node
  func getNodeTransform(nodeName: String) -> mat4 {
    return nodeTransforms[nodeName] ?? mat4(1)
  }

  /// Get all current node transforms
  func getAllNodeTransforms() -> [String: mat4] {
    return nodeTransforms
  }

  /// Calculate bone transforms for skeletal animation
  func calculateBoneTransforms(scene: Scene) -> [String: mat4] {
    var boneTransforms: [String: mat4] = [:]

    // For skeletal animation, we need to calculate the final bone matrices
    // that will be sent to the GPU. These should be: currentBoneTransform * offsetMatrix

    // First, get all the node transforms from animation
    let nodeTransforms = getAllNodeTransforms()

    // Debug: Print available node transforms
    logger.trace("Available node transforms: \(nodeTransforms.keys.joined(separator: ", "))")

    // Then calculate the final bone matrices for each mesh
    for mesh in scene.meshes {
      if mesh.numberOfBones > 0 {
        logger.trace("Processing mesh with \(mesh.numberOfBones) bones")
        for (boneIndex, bone) in mesh.bones.enumerated() {
          guard let boneName = bone.name else { continue }

          // Get the current animated transform for this bone
          let currentTransform = nodeTransforms[boneName] ?? mat4(1)

          // Convert Assimp offset matrix to GLMath mat4
          let offsetMatrix = convertAssimpMatrix(bone.offsetMatrix)

          // The final bone matrix is: currentTransform * offsetMatrix
          let finalBoneMatrix = currentTransform * offsetMatrix

          // Store with bone index as key for GPU access
          boneTransforms["\(boneIndex)"] = finalBoneMatrix

          logger.trace(
            "Bone \(boneIndex) (\(boneName)): current=\(currentTransform != mat4(1)), final=\(finalBoneMatrix)")
        }
      }
    }

    return boneTransforms
  }

  private func calculateBoneTransformsRecursive(
    node: Node,
    parentTransform: mat4,
    boneTransforms: inout [String: mat4]
  ) {
    // Get the node's local transform
    let nodeTransform = convertAssimpMatrix(node.transformation)

    // Get animated transform if available
    let animatedTransform = nodeTransforms[node.name ?? ""] ?? mat4(1)

    // Calculate global transform
    let globalTransform = parentTransform * nodeTransform * animatedTransform

    // Store the transform if this is a bone
    if let nodeName = node.name, !nodeName.isEmpty {
      boneTransforms[nodeName] = globalTransform
    }

    // Process children
    for child in node.children {
      calculateBoneTransformsRecursive(
        node: child,
        parentTransform: globalTransform,
        boneTransforms: &boneTransforms
      )
    }
  }

  /// Convert Assimp matrix to GLMath mat4
  private func convertAssimpMatrix(_ matrix: Assimp.Matrix4x4) -> mat4 {
    let row1 = vec4(Float(matrix.a1), Float(matrix.b1), Float(matrix.c1), Float(matrix.d1))
    let row2 = vec4(Float(matrix.a2), Float(matrix.b2), Float(matrix.c2), Float(matrix.d2))
    let row3 = vec4(Float(matrix.a3), Float(matrix.b3), Float(matrix.c3), Float(matrix.d3))
    let row4 = vec4(Float(matrix.a4), Float(matrix.b4), Float(matrix.c4), Float(matrix.d4))
    return mat4(row1, row2, row3, row4)
  }

  private func updateNodeTransforms() {
    guard let animation = animation else { return }

    // Clear previous transforms
    nodeTransforms.removeAll()

    // Process each animation channel
    for channel in animation.channels {
      guard let nodeName = channel.nodeName else { continue }

      let transform = calculateNodeTransform(for: channel, at: currentTime)
      nodeTransforms[nodeName] = transform
    }

  }

  private func calculateNodeTransform(for channel: NodeAnimation, at time: Double) -> mat4 {
    // Get interpolated position
    let position = interpolatePosition(channel: channel, time: time)

    // Get interpolated rotation
    let rotation = interpolateRotation(channel: channel, time: time)

    // Get interpolated scale
    let scale = interpolateScale(channel: channel, time: time)

    // Build transformation matrix
    let translationMatrix = GLMath.translate(mat4(1), position)
    let rotationMatrix = quaternionToMatrix(rotation)
    let scaleMatrix = GLMath.scale(mat4(1), scale)

    return translationMatrix * rotationMatrix * scaleMatrix
  }

  private func interpolatePosition(channel: NodeAnimation, time: Double) -> vec3 {
    let keys = channel.positionKeys
    guard !keys.isEmpty else { return vec3(0) }

    if keys.count == 1 {
      return vec3(Float(keys[0].value.x), Float(keys[0].value.y), Float(keys[0].value.z))
    }

    // Find the two keys to interpolate between
    for i in 0..<keys.count - 1 {
      if time >= keys[i].time && time <= keys[i + 1].time {
        let t1 = keys[i].time
        let t2 = keys[i + 1].time
        let factor = Float((time - t1) / (t2 - t1))

        let v1 = vec3(Float(keys[i].value.x), Float(keys[i].value.y), Float(keys[i].value.z))
        let v2 = vec3(Float(keys[i + 1].value.x), Float(keys[i + 1].value.y), Float(keys[i + 1].value.z))

        return v1 + (v2 - v1) * factor
      }
    }

    // Return last key if time is beyond animation
    let lastKey = keys.last!
    return vec3(Float(lastKey.value.x), Float(lastKey.value.y), Float(lastKey.value.z))
  }

  private func interpolateRotation(channel: NodeAnimation, time: Double) -> Quaternion<Float> {
    let keys = channel.rotationKeys
    guard !keys.isEmpty else { return Quaternion<Float>(1, 0, 0, 0) }

    if keys.count == 1 {
      let q = keys[0].value
      return Quaternion<Float>(q.w, q.x, q.y, q.z)
    }

    // Find the two keys to interpolate between
    for i in 0..<keys.count - 1 {
      if time >= keys[i].time && time <= keys[i + 1].time {
        let t1 = keys[i].time
        let t2 = keys[i + 1].time
        let factor = Float((time - t1) / (t2 - t1))

        let q1 = Quaternion<Float>(keys[i].value.w, keys[i].value.x, keys[i].value.y, keys[i].value.z)
        let q2 = Quaternion<Float>(keys[i + 1].value.w, keys[i + 1].value.x, keys[i + 1].value.y, keys[i + 1].value.z)

        return slerp(q1, q2, factor)
      }
    }

    // Return last key if time is beyond animation
    let lastKey = keys.last!
    let q = lastKey.value
    return Quaternion<Float>(q.w, q.x, q.y, q.z)
  }

  private func interpolateScale(channel: NodeAnimation, time: Double) -> vec3 {
    let keys = channel.scalingKeys
    guard !keys.isEmpty else { return vec3(1) }

    if keys.count == 1 {
      return vec3(Float(keys[0].value.x), Float(keys[0].value.y), Float(keys[0].value.z))
    }

    // Find the two keys to interpolate between
    for i in 0..<keys.count - 1 {
      if time >= keys[i].time && time <= keys[i + 1].time {
        let t1 = keys[i].time
        let t2 = keys[i + 1].time
        let factor = Float((time - t1) / (t2 - t1))

        let v1 = vec3(Float(keys[i].value.x), Float(keys[i].value.y), Float(keys[i].value.z))
        let v2 = vec3(Float(keys[i + 1].value.x), Float(keys[i + 1].value.y), Float(keys[i + 1].value.z))

        return v1 + (v2 - v1) * factor
      }
    }

    // Return last key if time is beyond animation
    let lastKey = keys.last!
    return vec3(Float(lastKey.value.x), Float(lastKey.value.y), Float(lastKey.value.z))
  }

  // Spherical linear interpolation for quaternions
  private func slerp(_ q1: Quaternion<Float>, _ q2: Quaternion<Float>, _ t: Float) -> Quaternion<Float> {
    let dot = q1.x * q2.x + q1.y * q2.y + q1.z * q2.z + q1.w * q2.w

    // If the dot product is negative, slerp won't take the shorter path
    let q2Adjusted = dot < 0 ? Quaternion<Float>(-q2.x, -q2.y, -q2.z, -q2.w) : q2
    let dotAdjusted = abs(dot)

    // If the inputs are too close for comfort, linearly interpolate
    if dotAdjusted > 0.9995 {
      let result = Quaternion<Float>(
        q1.x + t * (q2Adjusted.x - q1.x),
        q1.y + t * (q2Adjusted.y - q1.y),
        q1.z + t * (q2Adjusted.z - q1.z),
        q1.w + t * (q2Adjusted.w - q1.w)
      )
      return normalize(result)
    }

    // Calculate the angle between the quaternions
    let theta = acos(dotAdjusted)
    let sinTheta = sin(theta)
    let factor1 = sin((1 - t) * theta) / sinTheta
    let factor2 = sin(t * theta) / sinTheta

    return Quaternion<Float>(
      factor1 * q1.x + factor2 * q2Adjusted.x,
      factor1 * q1.y + factor2 * q2Adjusted.y,
      factor1 * q1.z + factor2 * q2Adjusted.z,
      factor1 * q1.w + factor2 * q2Adjusted.w
    )
  }

  // Normalize a quaternion
  private func normalize(_ q: Quaternion<Float>) -> Quaternion<Float> {
    let length = sqrt(q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w)
    if length == 0 {
      return Quaternion<Float>(0, 0, 0, 1)
    }
    return Quaternion<Float>(q.x / length, q.y / length, q.z / length, q.w / length)
  }

  // Convert a quaternion to a 4x4 rotation matrix
  private func quaternionToMatrix(_ q: Quaternion<Float>) -> mat4 {
    let x = q.x
    let y = q.y
    let z = q.z
    let w = q.w

    let x2 = x + x
    let y2 = y + y
    let z2 = z + z

    let xx = x * x2
    let xy = x * y2
    let xz = x * z2
    let yy = y * y2
    let yz = y * z2
    let zz = z * z2
    let wx = w * x2
    let wy = w * y2
    let wz = w * z2

    return mat4(
      1 - (yy + zz), xy + wz, xz - wy, 0,
      xy - wz, 1 - (xx + zz), yz + wx, 0,
      xz + wy, yz - wx, 1 - (xx + yy), 0,
      0, 0, 0, 1
    )
  }
}
