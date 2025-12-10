import Assimp
import CJolt
import Foundation
import Jolt
import Logging

/// Manages the physics system, collision bodies, and physics-related operations
@MainActor
public final class PhysicsWorld {
  // MARK: - Core Physics System

  private let physicsSystem: PhysicsSystem
  private let jobSystem: JobSystemThreadPool

  // Store filter objects so they stay alive (PhysicsSystem only keeps references)
  private let broadPhaseLayerInterface: BroadPhaseLayerInterfaceTable
  private let objectLayerPairFilter: ObjectLayerPairFilterTable
  private let objectVsBroadPhaseLayerFilter: ObjectVsBroadPhaseLayerFilterTable

  // MARK: - Debug Renderer

  private var debugRenderer: DebugRenderer?
  private var debugRendererImplementation: DebugRendererImplementation?

  // MARK: - Body Tracking

  // Tracking all physics body IDs for the current scene (so we can clear them when loading a new scene)
  private var collisionBodyIDs: [BodyID] = []
  // Mapping from collision body IDs to their node names (for debugging)
  private(set) var collisionBodyNames: [BodyID: String] = [:]
  // Mapping from action body IDs to their node names
  private(set) var actionBodyNames: [BodyID: String] = [:]
  // Mapping from trigger body IDs to their node names
  private(set) var triggerBodyNames: [BodyID: String] = [:]

  // Flag to track if physics system is ready for updates
  private(set) var isReady: Bool = false

  // MARK: - Contact Listener

  // Contact listener for sensor body contacts
  private var sensorBodyContactListener: SensorBodyContactListener?

  /// Get current sensor body contacts (for InteractionSystem)
  public func getSensorBodyContacts(sensorBodyID: BodyID) -> Set<BodyID> {
    return sensorBodyContactListener?.getContacts(for: sensorBodyID) ?? []
  }

  /// Register a body name for debugging (unified lookup across all body types)
  public func registerBodyName(_ bodyID: BodyID, name: String) {
    // Store in the appropriate mapping based on what type it is
    // If it's already in one of the specific mappings, don't overwrite
    if actionBodyNames[bodyID] == nil && triggerBodyNames[bodyID] == nil && collisionBodyNames[bodyID] == nil {
      // Store in collision body names as a catch-all for bodies that don't fit other categories
      collisionBodyNames[bodyID] = name
    }
  }

  /// Get a human-readable name for a body ID (for debugging)
  public func getBodyName(_ bodyID: BodyID) -> String {
    // Check all name mappings
    if let name = actionBodyNames[bodyID] {
      return name
    }
    if let name = triggerBodyNames[bodyID] {
      return name
    }
    if let name = collisionBodyNames[bodyID] {
      return name
    }
    // Fallback: return the body ID as a string
    return "BodyID(\(bodyID))"
  }

  /// Register sensor body for contact tracking
  public func registerSensorBody(_ sensorBodyID: BodyID) {
    if sensorBodyContactListener == nil {
      sensorBodyContactListener = SensorBodyContactListener()
      physicsSystem.setContactListener(sensorBodyContactListener)
    }
    sensorBodyContactListener?.registerSensorBody(sensorBodyID)
  }

  /// Unregister sensor body from contact tracking
  public func unregisterSensorBody(_ sensorBodyID: BodyID) {
    sensorBodyContactListener?.unregisterSensorBody(sensorBodyID)
  }

  // MARK: - Initialization

  init(renderLoop: RenderLoop) {
    // Initialize Jolt runtime (required before using any Jolt features)
    JoltRuntime.initialize()

    // Set up collision filtering (required for PhysicsSystem)
    // Object layers: 0=collision, 1=action/trigger bodies, 2=sensor box/player
    let numObjectLayers: UInt32 = 3
    let numBroadPhaseLayers: UInt32 = 2  // nonMoving=0, moving=1

    // Create broad phase layer interface
    broadPhaseLayerInterface = BroadPhaseLayerInterfaceTable(
      numObjectLayers: numObjectLayers,
      numBroadPhaseLayers: numBroadPhaseLayers
    )
    // Map object layers to broad phase layers
    broadPhaseLayerInterface.map(objectLayer: 0, to: 0)  // Collision bodies -> nonMoving
    broadPhaseLayerInterface.map(objectLayer: 1, to: 1)  // Action/trigger bodies -> moving
    broadPhaseLayerInterface.map(objectLayer: 2, to: 1)  // Sensor box/player -> moving

    // Create object layer pair filter
    objectLayerPairFilter = ObjectLayerPairFilterTable(numObjectLayers: numObjectLayers)
    // Enable collisions between sensor box (layer 2) and action bodies (layer 1)
    objectLayerPairFilter.enableCollision(1, 2)  // Action bodies <-> Sensor box
    objectLayerPairFilter.enableCollision(2, 1)  // Sensor box <-> Action bodies (symmetric)
    // Enable other necessary collisions
    objectLayerPairFilter.enableCollision(0, 0)  // Collision vs Collision
    objectLayerPairFilter.enableCollision(0, 2)  // Collision vs Sensor box (for character controller)
    objectLayerPairFilter.enableCollision(2, 0)  // Sensor box vs Collision
    objectLayerPairFilter.enableCollision(1, 1)  // Action vs Action (if needed)

    // Create object vs broad phase layer filter
    objectVsBroadPhaseLayerFilter = ObjectVsBroadPhaseLayerFilterTable(
      broadPhaseLayerInterface: broadPhaseLayerInterface,
      numBroadPhaseLayers: numBroadPhaseLayers,
      objectLayerPairFilter: objectLayerPairFilter,
      numObjectLayers: numObjectLayers
    )

    // Create job system for physics updates (required for PhysicsSystem::Update)
    jobSystem = JobSystemThreadPool(
      maxJobs: 1024,
      maxBarriers: 8,
      numThreads: -1  // Auto-detect number of threads
    )

    // Create physics system with proper filters (all three filters are required, cannot be nil)
    physicsSystem = PhysicsSystem(
      maxBodies: 1024,
      numBodyMutexes: 0,
      maxBodyPairs: 1024,
      maxContactConstraints: 1024,
      broadPhaseLayerInterface: broadPhaseLayerInterface,
      objectLayerPairFilter: objectLayerPairFilter,
      objectVsBroadPhaseLayerFilter: objectVsBroadPhaseLayerFilter
    )
    physicsSystem.setGravity(Vec3(x: 0, y: -9.81, z: 0))

    // Initialize debug renderer
    let debugProcs = DebugRendererImplementation()
    debugRenderer = DebugRenderer(procs: debugProcs)
    debugRendererImplementation = debugProcs
    if let mainLoop = renderLoop as? MainLoop {
      debugProcs.renderLoop = mainLoop
    }

    // Create ground plane immediately (doesn't depend on scene)
    createGroundPlane()
  }

  // MARK: - Physics System Delegation

  /// Get the underlying physics system (for CharacterVirtual.update())
  public func getPhysicsSystem() -> PhysicsSystem {
    return physicsSystem
  }

  public func bodyInterface() -> BodyInterface {
    return physicsSystem.bodyInterface()
  }

  public func update(deltaTime: Float, collisionSteps: Int = 1) {
    physicsSystem.update(deltaTime: deltaTime, collisionSteps: collisionSteps, jobSystem: jobSystem)
  }

  public func setGravity(_ value: Vec3) {
    physicsSystem.setGravity(value)
  }

  public func getGravity() -> Vec3 {
    return physicsSystem.getGravity()
  }

  public func optimizeBroadPhase() {
    physicsSystem.optimizeBroadPhase()
  }

  public func drawBodies(debugRenderer: DebugRenderer) {
    physicsSystem.drawBodies(debugRenderer: debugRenderer)
  }

  public func collideShapeAll(
    shape: Shape,
    scale: Vec3,
    baseOffset: inout RVec3,
    objectLayerFilter: ObjectLayerFilter? = nil
  ) -> [CollideShapeResult] {
    return physicsSystem.collideShapeAll(
      shape: shape,
      scale: scale,
      baseOffset: &baseOffset,
      objectLayerFilter: objectLayerFilter
    )
  }

  /// Collide shape with explicit transform
  public func collideShapeAll(
    shape: Shape,
    scale: Vec3,
    centerOfMassTransform: RMat44,
    baseOffset: inout RVec3,
    objectLayerFilter: ObjectLayerFilter? = nil
  ) -> [CollideShapeResult] {
    return physicsSystem.collideShapeAll(
      shape: shape,
      scale: scale,
      centerOfMassTransform: centerOfMassTransform.cValue,
      baseOffset: &baseOffset,
      objectLayerFilter: objectLayerFilter
    )
  }

  /// Cast shape (sweep shape from start transform along direction)
  public func castShapeAll(
    shape: Shape,
    worldTransform: RMat44,
    direction: Vec3,
    baseOffset: inout RVec3
  ) -> [ShapeCastResult] {
    return physicsSystem.castShapeAll(
      shape: shape,
      worldTransform: worldTransform.cValue,
      direction: direction,
      baseOffset: &baseOffset
    )
  }

  // MARK: - Debug Renderer Access

  public func getDebugRenderer() -> DebugRenderer? {
    return debugRenderer
  }

  public func getDebugRendererImplementation() -> DebugRendererImplementation? {
    return debugRendererImplementation
  }

  public func nextFrame() {
    debugRenderer?.nextFrame()
  }

  // MARK: - Body Management

  /// Get collision body name for debugging
  public func getCollisionBodyName(bodyID: BodyID) -> String? {
    return collisionBodyNames[bodyID]
  }

  /// Clear all physics bodies from the previous scene
  public func clearAllBodies() {
    let bodyInterface = physicsSystem.bodyInterface()

    // Remove all collision bodies
    for bodyID in collisionBodyIDs {
      bodyInterface.removeAndDestroyBody(bodyID)
    }
    collisionBodyIDs.removeAll()
    collisionBodyNames.removeAll()

    // Remove all action bodies
    for bodyID in actionBodyNames.keys {
      bodyInterface.removeAndDestroyBody(bodyID)
    }
    actionBodyNames.removeAll()

    // Remove all trigger bodies
    for bodyID in triggerBodyNames.keys {
      bodyInterface.removeAndDestroyBody(bodyID)
    }
    triggerBodyNames.removeAll()
  }

  /// Load collision bodies from scene
  public func loadCollisionBodies(scene: Scene) {
    let bodyInterface = physicsSystem.bodyInterface()

    // Object layer 0 for collision bodies
    let collisionLayer: ObjectLayer = 0

    // Use scene.collisionNodes instead of manual traversal
    for node in scene.collisionNodes {
      let name = node.name
      let worldTransform = node.assimpNode.calculateWorldTransform(scene: scene.assimpScene)

      // Get mesh from this node
      if node.numberOfMeshes > 0 {
        let meshIndex = node.meshes[0]
        if meshIndex < scene.meshes.count {
          let mesh = scene.meshes[Int(meshIndex)]

          // Extract triangles from mesh and transform them to world space (includes scale/rotation/translation)
          // We transform to world space because the visual meshes are rendered with world transforms
          let triangles = extractTrianglesFromMesh(mesh: mesh, transform: worldTransform)

          guard !triangles.isEmpty else { continue }

          // Create mesh shape from triangles (already in world space, no body transform needed)
          let meshShape = MeshShape(triangles: triangles)

          // Position is at origin since triangles are already in world space
          let position = vec3(0, 0, 0)

          // Rotation is identity since triangles are already in world space
          let rotation = Quat.identity

          // Create body settings
          let bodySettings = BodyCreationSettings(
            shape: meshShape,
            position: RVec3(x: position.x, y: position.y, z: position.z),
            rotation: rotation,
            motionType: .static,
            objectLayer: collisionLayer
          )

          // Create and add body to physics system
          let bodyID = bodyInterface.createAndAddBody(settings: bodySettings, activation: .dontActivate)
          if bodyID != 0 {
            collisionBodyIDs.append(bodyID)
            collisionBodyNames[bodyID] = name
            logger.trace("✅ Created collision body ID: \(bodyID) for node '\(name)'")
          } else {
            logger.error("❌ Failed to create collision body for node '\(name)'")
          }
        }
      }
    }
  }

  /// Load action bodies from scene (includes both @Action and @Door nodes)
  public func loadActionBodies(scene: Scene) {
    let bodyInterface = physicsSystem.bodyInterface()

    // TEMPORARY TEST: Move action bodies to layer 0 to test if layer filtering is the issue
    // Object layer 1 for action/trigger bodies (separate from collision bodies)
    let actionLayer: ObjectLayer = 0  // TEMP: Changed from 1 to 0 for testing

    // Use scene.actionNodes and scene.doorNodes (treat doors as actions for interaction)
    let allActionNodes = scene.actionNodes + scene.doorNodes
    logger.debug(
      "📋 Loading action bodies from \(allActionNodes.count) nodes (\(scene.actionNodes.count) actions, \(scene.doorNodes.count) doors)"
    )
    for node in allActionNodes {
      let name = node.name
      let worldTransform = node.assimpNode.calculateWorldTransform(scene: scene.assimpScene)

      // Get mesh from this node
      if node.numberOfMeshes > 0 {
        let meshIndex = node.meshes[0]
        if meshIndex < scene.meshes.count {
          let mesh = scene.meshes[Int(meshIndex)]

          // Transform triangles to world space using the full world transform
          // This preserves exact geometry without decomposition errors
          let triangles = extractTrianglesFromMesh(mesh: mesh, transform: worldTransform)

          guard !triangles.isEmpty else { continue }

          // Calculate centroid of all triangles for body position
          var totalX: Float = 0
          var totalY: Float = 0
          var totalZ: Float = 0
          var vertexCount: Int = 0
          for triangle in triangles {
            totalX += triangle.v1.x + triangle.v2.x + triangle.v3.x
            totalY += triangle.v1.y + triangle.v2.y + triangle.v3.y
            totalZ += triangle.v1.z + triangle.v2.z + triangle.v3.z
            vertexCount += 3
          }
          guard vertexCount > 0 else { continue }
          let centroid = vec3(
            totalX / Float(vertexCount),
            totalY / Float(vertexCount),
            totalZ / Float(vertexCount)
          )

          // Offset triangles so body can be at centroid
          let offsetTriangles = triangles.map { triangle in
            Triangle(
              v1: Vec3(x: triangle.v1.x - centroid.x, y: triangle.v1.y - centroid.y, z: triangle.v1.z - centroid.z),
              v2: Vec3(x: triangle.v2.x - centroid.x, y: triangle.v2.y - centroid.y, z: triangle.v2.z - centroid.z),
              v3: Vec3(x: triangle.v3.x - centroid.x, y: triangle.v3.y - centroid.y, z: triangle.v3.z - centroid.z),
              materialIndex: triangle.materialIndex
            )
          }

          // Create mesh shape from offset triangles (body will be at centroid)
          let meshShape = MeshShape(triangles: offsetTriangles)

          // Body position is at centroid, rotation is identity (already baked into triangles)
          let position = centroid
          let rotation = Quat.identity

          // Create body settings - make it a sensor so it can be detected and easier to spot in debug
          let bodySettings = BodyCreationSettings(
            shape: meshShape,
            position: RVec3(x: position.x, y: position.y, z: position.z),
            rotation: rotation,
            motionType: .static,
            objectLayer: actionLayer
          )
          bodySettings.isSensor = true  // Make it a sensor (also makes it easier to spot in debug visualization)

          // Create and add body to physics system
          let bodyID = bodyInterface.createAndAddBody(settings: bodySettings, activation: .dontActivate)
          if bodyID != 0 {
            // Store mapping from body ID to node name
            actionBodyNames[bodyID] = name
            logger.debug("✅ Created action trigger body ID: \(bodyID) for node '\(name)'")
          } else {
            logger.error("❌ Failed to create action trigger body for node '\(name)'")
          }
        } else {
          logger.debug("⚠️ Action node '\(name)' has invalid mesh index")
        }
      } else {
        logger.debug("⚠️ Action node '\(name)' has no meshes")
      }
    }
    logger.debug("📋 Total action bodies created: \(actionBodyNames.count)")
  }

  /// Load trigger bodies from scene
  public func loadTriggerBodies(scene: Scene) {
    let bodyInterface = physicsSystem.bodyInterface()

    // Object layer 1 for trigger bodies (same as action bodies)
    let triggerLayer: ObjectLayer = 1

    // Use scene.triggerNodes and scene.cameraTriggerNodes instead of manual traversal
    let allTriggerNodes = scene.triggerNodes + scene.cameraTriggerNodes

    for node in allTriggerNodes {
      let name = node.name
      let worldTransform = node.assimpNode.calculateWorldTransform(scene: scene.assimpScene)

      // Get mesh from this node
      if node.numberOfMeshes > 0 {
        let meshIndex = node.meshes[0]
        if meshIndex < scene.meshes.count {
          let mesh = scene.meshes[Int(meshIndex)]

          // Extract triangles from mesh and transform them to world space
          let triangles = extractTrianglesFromMesh(mesh: mesh, transform: worldTransform)

          guard !triangles.isEmpty else { continue }

          // Create mesh shape from triangles (already in world space)
          let meshShape = MeshShape(triangles: triangles)

          // Position is at origin since triangles are already in world space
          let position = vec3(0, 0, 0)
          let rotation = Quat.identity

          // Create body settings - mark as sensor so it doesn't collide but triggers
          let bodySettings = BodyCreationSettings(
            shape: meshShape,
            position: RVec3(x: position.x, y: position.y, z: position.z),
            rotation: rotation,
            motionType: .static,
            objectLayer: triggerLayer
          )
          bodySettings.isSensor = true  // Make it a sensor/trigger

          // Create and add body to physics system
          let bodyID = bodyInterface.createAndAddBody(settings: bodySettings, activation: .dontActivate)
          if bodyID != 0 {
            // Store mapping from body ID to node name
            triggerBodyNames[bodyID] = name
            logger.trace("✅ Created trigger body ID: \(bodyID) for node '\(name)'")
          } else {
            logger.error("❌ Failed to create trigger body for node '\(name)'")
          }
        }
      }
    }
  }

  /// Create ground plane
  public func createGroundPlane() {
    let bodyInterface = physicsSystem.bodyInterface()

    // Use a large BoxShape instead of PlaneShape for better reliability
    // PlaneShape can have issues with collision detection when the character moves away from the origin
    // A large flat box is more reliable and still very efficient
    let groundHalfExtent = Vec3(x: 500.0, y: 0.5, z: 500.0)  // Very large flat box
    let groundShape = BoxShape(halfExtent: groundHalfExtent)

    // Position at y = -0.5 so top surface is at y = 0
    let groundPosition = RVec3(x: 0, y: -0.5, z: 0)
    let groundRotation = Quat.identity

    // Create body settings
    let groundLayer: ObjectLayer = 0  // Collision layer (same as other collision bodies)
    let bodySettings = BodyCreationSettings(
      shape: groundShape,
      position: groundPosition,
      rotation: groundRotation,
      motionType: .static,
      objectLayer: groundLayer
    )

    // Create and add ground body
    let groundBodyID = bodyInterface.createAndAddBody(settings: bodySettings, activation: .dontActivate)
    if groundBodyID != 0 {
      collisionBodyNames[groundBodyID] = "Ground Plane"
      logger.trace("✅ Created ground plane body ID: \(groundBodyID)")
    } else {
      logger.error("❌ Failed to create ground plane")
    }
  }

  /// Mark physics system as ready for updates
  public func setReady(_ ready: Bool) {
    isReady = ready
  }

  // MARK: - Helper Methods

  private func extractTrianglesFromMesh(mesh: Assimp.Mesh, transform: mat4) -> [Triangle] {
    guard mesh.numberOfVertices > 0, mesh.numberOfFaces > 0 else { return [] }

    let vertices = mesh.vertices
    var triangles: [Triangle] = []

    // Extract faces (triangles) and transform them to world space
    for face in mesh.faces {
      guard face.numberOfIndices == 3 else { continue }  // Only process triangles

      let i1 = Int(face.indices[0])
      let i2 = Int(face.indices[1])
      let i3 = Int(face.indices[2])

      guard i1 < mesh.numberOfVertices, i2 < mesh.numberOfVertices, i3 < mesh.numberOfVertices else {
        continue
      }

      // Get vertex positions in local space
      let v1Local = vec3(
        Float(vertices[i1 * 3 + 0]),
        Float(vertices[i1 * 3 + 1]),
        Float(vertices[i1 * 3 + 2])
      )
      let v2Local = vec3(
        Float(vertices[i2 * 3 + 0]),
        Float(vertices[i2 * 3 + 1]),
        Float(vertices[i2 * 3 + 2])
      )
      let v3Local = vec3(
        Float(vertices[i3 * 3 + 0]),
        Float(vertices[i3 * 3 + 1]),
        Float(vertices[i3 * 3 + 2])
      )

      // Transform to world space (includes scale, rotation, translation)
      let v1World = transform * vec4(v1Local.x, v1Local.y, v1Local.z, 1.0)
      let v2World = transform * vec4(v2Local.x, v2Local.y, v2Local.z, 1.0)
      let v3World = transform * vec4(v3Local.x, v3Local.y, v3Local.z, 1.0)

      triangles.append(
        Triangle(
          v1: Vec3(x: v1World.x, y: v1World.y, z: v1World.z),
          v2: Vec3(x: v2World.x, y: v2World.y, z: v2World.z),
          v3: Vec3(x: v3World.x, y: v3World.y, z: v3World.z),
          materialIndex: 0
        ))
    }

    return triangles
  }

  /// Extract rotation quaternion from a 4x4 transformation matrix
  /// Handles matrices with scale by normalizing the rotation matrix columns
  private func extractRotationFromMatrix(_ matrix: mat4) -> Quat {
    // Extract upper 3x3 rotation matrix columns
    var col0 = vec3(matrix[0].x, matrix[0].y, matrix[0].z)
    var col1 = vec3(matrix[1].x, matrix[1].y, matrix[1].z)
    var col2 = vec3(matrix[2].x, matrix[2].y, matrix[2].z)

    // Remove scale by normalizing columns (Gram-Schmidt orthonormalization)
    let len0 = length(col0)
    guard len0 > 0.0001 else { return Quat.identity }
    col0 = col0 / len0

    // Orthogonalize col1 against col0
    let dot01 = dot(col1, col0)
    col1 = col1 - col0 * dot01
    let len1 = length(col1)
    guard len1 > 0.0001 else { return Quat.identity }
    col1 = col1 / len1

    // Orthogonalize col2 against col0 and col1, then normalize
    let dot02 = dot(col2, col0)
    let dot12 = dot(col2, col1)
    col2 = col2 - col0 * dot02 - col1 * dot12
    let len2 = length(col2)
    guard len2 > 0.0001 else { return Quat.identity }
    col2 = col2 / len2

    // Verify and correct handedness if needed
    // For a right-handed coordinate system: cross(col0, col1) should point in same direction as col2
    let cross01 = cross(col0, col1)
    let determinant = dot(cross01, col2)

    // If determinant is significantly negative, we have a reflection (left-handed system)
    // For pure rotations, we want right-handed (determinant ≈ +1)
    // Only flip if we detect a clear reflection (determinant < -0.1 to avoid numerical noise)
    if determinant < -0.1 {
      col2 = -col2
    }

    // Now extract from normalized rotation matrix
    let m00 = col0.x
    let m01 = col0.y
    let m02 = col0.z
    let m10 = col1.x
    let m11 = col1.y
    let m12 = col1.z
    let m20 = col2.x
    let m21 = col2.y
    let m22 = col2.z

    // Convert rotation matrix to quaternion
    let trace = m00 + m11 + m22
    var qw: Float, qx: Float, qy: Float, qz: Float

    if trace > 0 {
      let s = sqrt(trace + 1.0) * 2  // s = 4 * qw
      qw = 0.25 * s
      qx = (m21 - m12) / s
      qy = (m02 - m20) / s
      qz = (m10 - m01) / s
    } else if (m00 > m11) && (m00 > m22) {
      let s = sqrt(1.0 + m00 - m11 - m22) * 2  // s = 4 * qx
      qw = (m21 - m12) / s
      qx = 0.25 * s
      qy = (m01 + m10) / s
      qz = (m02 + m20) / s
    } else if m11 > m22 {
      let s = sqrt(1.0 + m11 - m00 - m22) * 2  // s = 4 * qy
      qw = (m02 - m20) / s
      qx = (m01 + m10) / s
      qy = 0.25 * s
      qz = (m12 + m21) / s
    } else {
      let s = sqrt(1.0 + m22 - m00 - m11) * 2  // s = 4 * qz
      qw = (m10 - m01) / s
      qx = (m02 + m20) / s
      qy = (m12 + m21) / s
      qz = 0.25 * s
    }

    // Normalize the quaternion (required by Jolt - quaternions must be normalized)
    let length = sqrt(qx * qx + qy * qy + qz * qz + qw * qw)
    guard length > 0.0001 else {
      // If length is too small, return identity quaternion
      return Quat.identity
    }
    let invLength = 1.0 / length
    return Quat(x: qx * invLength, y: qy * invLength, z: qz * invLength, w: qw * invLength)
  }

  /// Extract scale from a 4x4 transformation matrix
  private func extractScaleFromMatrix(_ matrix: mat4) -> vec3 {
    // Extract scale from matrix columns (length of each column before normalization)
    let col0 = vec3(matrix[0].x, matrix[0].y, matrix[0].z)
    let col1 = vec3(matrix[1].x, matrix[1].y, matrix[1].z)
    let col2 = vec3(matrix[2].x, matrix[2].y, matrix[2].z)

    // Scale is the length of each column (before orthonormalization)
    return vec3(length(col0), length(col1), length(col2))
  }
}

// MARK: - Sensor Body Contact Listener

/// Contact listener that tracks contacts for sensor bodies
private class SensorBodyContactListener: ContactListener {
  // Track contacts for each sensor body: [sensorBodyID: Set<otherBodyID>]
  private var sensorContacts: [BodyID: Set<BodyID>] = [:]
  private var registeredSensorBodies: Set<BodyID> = []
  private let lock = NSLock()

  func registerSensorBody(_ sensorBodyID: BodyID) {
    lock.lock()
    defer { lock.unlock() }
    registeredSensorBodies.insert(sensorBodyID)
    sensorContacts[sensorBodyID] = []
  }

  func unregisterSensorBody(_ sensorBodyID: BodyID) {
    lock.lock()
    defer { lock.unlock() }
    registeredSensorBodies.remove(sensorBodyID)
    sensorContacts.removeValue(forKey: sensorBodyID)
  }

  func getContacts(for sensorBodyID: BodyID) -> Set<BodyID> {
    lock.lock()
    defer { lock.unlock() }
    return sensorContacts[sensorBodyID] ?? []
  }

  func onContactAdded(body1: Body, body2: Body, manifold: ContactManifold, settings: inout ContactSettings) {
    let body1ID = body1.id
    let body2ID = body2.id

    lock.lock()
    defer { lock.unlock() }

    // Check if body1 is a registered sensor body
    if registeredSensorBodies.contains(body1ID) {
      if sensorContacts[body1ID] == nil {
        sensorContacts[body1ID] = []
      }
      let insertResult = sensorContacts[body1ID]?.insert(body2ID)
      if insertResult?.inserted == true {
        logger.debug(
          "➕ Contact ADDED: sensor \(body1ID) -> body \(body2ID) (manifold points: \(manifold.pointCount), penetration: \(manifold.penetrationDepth))"
        )
      }
    }

    // Check if body2 is a registered sensor body
    if registeredSensorBodies.contains(body2ID) {
      if sensorContacts[body2ID] == nil {
        sensorContacts[body2ID] = []
      }
      let insertResult = sensorContacts[body2ID]?.insert(body1ID)
      if insertResult?.inserted == true {
        logger.debug(
          "➕ Contact ADDED: sensor \(body2ID) -> body \(body1ID) (manifold points: \(manifold.pointCount), penetration: \(manifold.penetrationDepth))"
        )
      }
    }
  }

  func onContactPersisted(body1: Body, body2: Body, manifold: ContactManifold, settings: inout ContactSettings) {
    let body1ID = body1.id
    let body2ID = body2.id

    lock.lock()
    defer { lock.unlock() }

    // Check if body1 is a registered sensor body
    if registeredSensorBodies.contains(body1ID) {
      if sensorContacts[body1ID] == nil {
        sensorContacts[body1ID] = []
      }
      sensorContacts[body1ID]?.insert(body2ID)
      // Note: onContactPersisted is called every frame, so we don't log every time to avoid spam
    }

    // Check if body2 is a registered sensor body
    if registeredSensorBodies.contains(body2ID) {
      if sensorContacts[body2ID] == nil {
        sensorContacts[body2ID] = []
      }
      sensorContacts[body2ID]?.insert(body1ID)
    }
  }

  func onContactRemoved(subShapePair: SubShapeIDPair) {
    lock.lock()
    defer { lock.unlock() }

    let body1ID = subShapePair.body1ID
    let body2ID = subShapePair.body2ID

    // Remove contact from sensor body 1's contacts
    if registeredSensorBodies.contains(body1ID) {
      let hadContact = sensorContacts[body1ID]?.contains(body2ID) ?? false
      sensorContacts[body1ID]?.remove(body2ID)
      if hadContact {
        logger.debug("➖ Contact REMOVED: sensor \(body1ID) -> body \(body2ID)")
      }
    }

    // Remove contact from sensor body 2's contacts
    if registeredSensorBodies.contains(body2ID) {
      let hadContact = sensorContacts[body2ID]?.contains(body1ID) ?? false
      sensorContacts[body2ID]?.remove(body1ID)
      if hadContact {
        logger.debug("➖ Contact REMOVED: sensor \(body2ID) -> body \(body1ID)")
      }
    }
  }
}
