/// A class that can play Animations from our scene data
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
    self.nodeTransforms.removeAll()
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
  /// Following LearnOpenGL tutorial: https://learnopengl.com/Guest-Articles/2020/Skeletal-Animation
  ///
  /// The standard approach:
  /// 1. Calculate global transforms for all bones in current animated pose
  /// 2. Calculate global inverse transform (inverse of root node's global transform)
  /// 3. Final bone matrix = GlobalInverseTransform * currentGlobalTransform * offsetMatrix
  ///    (where offsetMatrix is the inverse bind pose transform)
  func calculateBoneTransforms(sceneData: Scene) -> [String: mat4] {
    var boneTransforms: [String: mat4] = [:]

    // Step 1: Calculate global transforms for all bones in the CURRENT animated pose
    var globalAnimatedTransforms: [String: mat4] = [:]
    calculateGlobalNodeTransforms(
      node: sceneData.rootNode,
      parentTransform: mat4(1),
      globalTransforms: &globalAnimatedTransforms,
      depth: 0
    )

    // Step 2: Calculate global inverse transform (inverse of root node's global transform)
    // This accounts for any root-level transformations in the model
    let rootGlobalTransform = globalAnimatedTransforms[sceneData.rootNode.name] ?? sceneData.rootNode.transformation
    let globalInverseTransform = inverse(rootGlobalTransform)

    // Step 3: Calculate final bone matrices for each mesh
    // The bone transform should transform vertices from bone space (bind pose) to mesh space (current pose)
    //
    // The offsetMatrix transforms: mesh space (bind pose) -> bone space (bind pose)
    // To go the other way: bone space (bind pose) -> mesh space (bind pose), we need inverse(offsetMatrix)
    // Then to go from bind pose to current pose: currentGlobalTransform
    // So: currentGlobalTransform * inverse(offsetMatrix)
    for mesh in sceneData.meshes {
      if mesh.numberOfBones > 0 {
        for (boneIndex, bone) in mesh.bones.enumerated() {
          guard let boneName = bone.name else { continue }

          // Get global transform in current animated pose
          let currentGlobalTransform = globalAnimatedTransforms[boneName] ?? mat4(1)

          // Get offset matrix (transforms from mesh space to bone space in bind pose)
          let offsetMatrix = bone.offsetMatrix

          // Try: currentGlobalTransform * inverse(offsetMatrix)
          // This should transform: bone space (bind) -> mesh space (bind) -> mesh space (current)
          let finalBoneMatrix = currentGlobalTransform * inverse(offsetMatrix)

          // Store with bone index as key for GPU access
          boneTransforms["\(boneIndex)"] = finalBoneMatrix
        }
      }
    }

    return boneTransforms
  }

  /// Calculate global transforms for all nodes by traversing the hierarchy
  private func calculateGlobalNodeTransforms(
    node: Node,
    parentTransform: mat4,
    globalTransforms: inout [String: mat4],
    depth: Int = 0
  ) {
    // Get the node's bind pose transform from the scene hierarchy
    let bindPoseTransform = node.transformation

    // Determine the local transform for this node:
    // 1. If it has animation in the current animation, use that
    // 2. Otherwise, use the bind pose transform from the scene hierarchy
    let localTransform: mat4
    if let animatedTransform = nodeTransforms[node.name] {
      // This node is animated in the current animation
      localTransform = animatedTransform
    } else {
      // Use bind pose from scene hierarchy
      localTransform = bindPoseTransform
    }

    // Calculate global transform: parentGlobalTransform * localTransform
    // This builds the hierarchy from root to leaf
    let globalTransform = parentTransform * localTransform

    // Store the global transform for this node
    if !node.name.isEmpty {
      globalTransforms[node.name] = globalTransform
    }

    // Recursively process children
    for child in node.children {
      calculateGlobalNodeTransforms(
        node: child,
        parentTransform: globalTransform,
        globalTransforms: &globalTransforms,
        depth: depth + 1
      )
    }
  }

  /// Convert Assimp matrix to GLMath mat4

  private func updateNodeTransforms() {
    guard let animation = animation else { return }

    // Clear previous transforms
    nodeTransforms.removeAll()

    // Process each animation channel
    for channel in animation.channels {
      let nodeName = channel.nodeName

      let transform = calculateNodeTransform(for: channel, at: currentTime)
      nodeTransforms[nodeName] = transform
    }

    logger.trace(
      "Updated \(nodeTransforms.count) node transforms for animation '\(animation.name ?? "unnamed")' at time \(currentTime)"
    )
  }

  private func calculateNodeTransform(for channel: AnimationChannel, at time: Double) -> mat4 {
    // Get interpolated position
    let position = interpolatePosition(channel: channel, time: time)

    // Get interpolated rotation
    let rotation = interpolateRotation(channel: channel, time: time)

    // Get interpolated scale
    let scale = interpolateScale(channel: channel, time: time)

    // Build transformation matrix
    // Order: Scale -> Rotate -> Translate (SRT order)
    // This is the standard order for local transforms
    let scaleMatrix = GLMath.scale(mat4(1), scale)
    let rotationMatrix = quaternionToMatrix(rotation)
    let translationMatrix = GLMath.translate(mat4(1), position)

    // Matrix multiplication order: T * R * S
    // This means: first scale, then rotate, then translate
    return translationMatrix * rotationMatrix * scaleMatrix
  }

  private func interpolatePosition(channel: AnimationChannel, time: Double) -> vec3 {
    let keys = channel.positionKeys
    guard !keys.isEmpty else { return vec3(0) }

    if keys.count == 1 {
      return keys[0].value
    }

    // Find the two keys to interpolate between
    for i in 0..<keys.count - 1 {
      if time >= keys[i].time && time <= keys[i + 1].time {
        let t1 = keys[i].time
        let t2 = keys[i + 1].time
        let factor = Float((time - t1) / (t2 - t1))

        let v1 = keys[i].value
        let v2 = keys[i + 1].value

        return v1 + (v2 - v1) * factor
      }
    }

    // Return last key if time is beyond animation
    return keys.last!.value
  }

  private func interpolateRotation(channel: AnimationChannel, time: Double) -> Quaternion<Float> {
    let keys = channel.rotationKeys
    guard !keys.isEmpty else { return Quaternion<Float>(1, 0, 0, 0) }

    if keys.count == 1 {
      return keys[0].value
    }

    // Find the two keys to interpolate between
    for i in 0..<keys.count - 1 {
      if time >= keys[i].time && time <= keys[i + 1].time {
        let t1 = keys[i].time
        let t2 = keys[i + 1].time
        let factor = Float((time - t1) / (t2 - t1))

        let q1 = keys[i].value
        let q2 = keys[i + 1].value

        return slerp(q1, q2, factor)
      }
    }

    // Return last key if time is beyond animation
    return keys.last!.value
  }

  private func interpolateScale(channel: AnimationChannel, time: Double) -> vec3 {
    let keys = channel.scalingKeys
    guard !keys.isEmpty else { return vec3(1) }

    if keys.count == 1 {
      return keys[0].value
    }

    // Find the two keys to interpolate between
    for i in 0..<keys.count - 1 {
      if time >= keys[i].time && time <= keys[i + 1].time {
        let t1 = keys[i].time
        let t2 = keys[i + 1].time
        let factor = Float((time - t1) / (t2 - t1))

        let v1 = keys[i].value
        let v2 = keys[i + 1].value

        return v1 + (v2 - v1) * factor
      }
    }

    // Return last key if time is beyond animation
    return keys.last!.value
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
