import Assimp
import CJolt
import Foundation
import Jolt

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
  // Mapping from action body IDs to their node names
  private(set) var actionBodyNames: [BodyID: String] = [:]
  // Mapping from trigger body IDs to their node names
  private(set) var triggerBodyNames: [BodyID: String] = [:]

  // Flag to track if physics system is ready for updates
  private(set) var isReady: Bool = false

  // MARK: - Initialization

  init(renderLoop: RenderLoop) {
    // Initialize Jolt runtime (required before using any Jolt features)
    JoltRuntime.initialize()

    // Set up collision filtering (required for PhysicsSystem)
    // Note: Object layers are 0-indexed, so numObjectLayers: 3 means we can use layers 0, 1, 2
    let numObjectLayers: UInt32 = 3  // 0=unused, 1=static, 2=dynamic
    let numBroadPhaseLayers: UInt32 = 2  // Keep it simple - 2 broad phase layers

    // Create broad phase layer interface
    broadPhaseLayerInterface = BroadPhaseLayerInterfaceTable(
      numObjectLayers: numObjectLayers,
      numBroadPhaseLayers: numBroadPhaseLayers
    )
    // Map all object layers to the first broad phase layer (simple setup)
    broadPhaseLayerInterface.map(objectLayer: 1, to: 0)  // Static objects
    broadPhaseLayerInterface.map(objectLayer: 2, to: 0)  // Dynamic objects (if we add them)

    // Create object layer pair filter (allows all collisions)
    objectLayerPairFilter = ObjectLayerPairFilterTable(numObjectLayers: numObjectLayers)
    // Enable collisions between all layers
    objectLayerPairFilter.enableCollision(1, 1)  // Static vs Static
    objectLayerPairFilter.enableCollision(1, 2)  // Static vs Dynamic
    objectLayerPairFilter.enableCollision(2, 2)  // Dynamic vs Dynamic

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

    // Create physics system with proper filters
    physicsSystem = PhysicsSystem(
      maxBodies: 1024,
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
    baseOffset: inout RVec3
  ) -> [JPH_CollideShapeResult] {
    return physicsSystem.collideShapeAll(shape: shape, scale: scale, baseOffset: &baseOffset)
  }

  // MARK: - Debug Renderer Access

  public func getDebugRenderer() -> DebugRenderer? {
    return debugRenderer
  }

  public func nextFrame() {
    debugRenderer?.nextFrame()
  }

  // MARK: - Body Management

  /// Clear all physics bodies from the previous scene
  public func clearAllBodies() {
    let bodyInterface = physicsSystem.bodyInterface()

    // Remove all collision bodies
    for bodyID in collisionBodyIDs {
      bodyInterface.removeAndDestroyBody(bodyID)
    }
    collisionBodyIDs.removeAll()

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

    // Simple object layer for static collision bodies
    let staticLayer: ObjectLayer = 1

    func traverse(_ node: Node) {
      if let name = node.name, name.contains("-col") {
        let worldTransform = node.assimpNode.calculateWorldTransform(scene: scene.assimpScene)

        // Get mesh from this node
        if node.numberOfMeshes > 0 {
          let meshIndex = node.meshes[0]
          if meshIndex < scene.meshes.count {
            let mesh = scene.meshes[Int(meshIndex)]

            // Extract triangles from mesh and transform them to world space (includes scale/rotation/translation)
            // We transform to world space because the visual meshes are rendered with world transforms
            let triangles = extractTrianglesFromMesh(mesh: mesh, transform: worldTransform)

            guard !triangles.isEmpty else { return }

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
              objectLayer: staticLayer
            )

            // Create and add body to physics system
            let bodyID = bodyInterface.createAndAddBody(settings: bodySettings, activation: .dontActivate)
            if bodyID != 0 {
              collisionBodyIDs.append(bodyID)
              logger.trace("✅ Created collision body ID: \(bodyID) for node '\(name)'")
            } else {
              logger.error("❌ Failed to create collision body for node '\(name)'")
            }
          }
        }
      }
      for child in node.children { traverse(child) }
    }
    traverse(scene.rootNode)
  }

  /// Load action bodies from scene
  public func loadActionBodies(scene: Scene) {
    let bodyInterface = physicsSystem.bodyInterface()

    // Simple object layer for static action bodies (same as collision bodies)
    let staticLayer: ObjectLayer = 1

    func traverse(_ node: Node) {
      if let name = node.name, name.contains("-action") {
        let worldTransform = node.assimpNode.calculateWorldTransform(scene: scene.assimpScene)

        // Get mesh from this node
        if node.numberOfMeshes > 0 {
          let meshIndex = node.meshes[0]
          if meshIndex < scene.meshes.count {
            let mesh = scene.meshes[Int(meshIndex)]

            // Extract triangles from mesh and transform them to world space
            let triangles = extractTrianglesFromMesh(mesh: mesh, transform: worldTransform)

            guard !triangles.isEmpty else { return }

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
              objectLayer: staticLayer
            )
            bodySettings.isSensor = true  // Make it a sensor/trigger

            // Create and add body to physics system
            let bodyID = bodyInterface.createAndAddBody(settings: bodySettings, activation: .dontActivate)
            if bodyID != 0 {
              // Store mapping from body ID to node name
              actionBodyNames[bodyID] = name
              logger.trace("✅ Created action trigger body ID: \(bodyID) for node '\(name)'")
            } else {
              logger.error("❌ Failed to create action trigger body for node '\(name)'")
            }
          }
        }
      }
      for child in node.children { traverse(child) }
    }
    traverse(scene.rootNode)
  }

  /// Load trigger bodies from scene
  public func loadTriggerBodies(scene: Scene) {
    let bodyInterface = physicsSystem.bodyInterface()

    // Simple object layer for static trigger bodies (same as collision bodies)
    let staticLayer: ObjectLayer = 1

    func traverse(_ node: Node) {
      if let name = node.name, name.contains("-trigger") || name.hasPrefix("CameraTrigger_") {
        let worldTransform = node.assimpNode.calculateWorldTransform(scene: scene.assimpScene)

        // Get mesh from this node
        if node.numberOfMeshes > 0 {
          let meshIndex = node.meshes[0]
          if meshIndex < scene.meshes.count {
            let mesh = scene.meshes[Int(meshIndex)]

            // Extract triangles from mesh and transform them to world space
            let triangles = extractTrianglesFromMesh(mesh: mesh, transform: worldTransform)

            guard !triangles.isEmpty else { return }

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
              objectLayer: staticLayer
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
      for child in node.children { traverse(child) }
    }
    traverse(scene.rootNode)
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
    let groundLayer: ObjectLayer = 1  // Static layer
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
}
