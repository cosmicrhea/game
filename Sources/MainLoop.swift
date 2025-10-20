import Assimp
/// The main game loop that handles rendering and input.
final class MainLoop: RenderLoop {

  // Gameplay state
  private var playerPosition: vec3 = vec3(0, 0, 0)
  private var playerRotation: Float = 0.0
  private var moveSpeed: Float = 5.0

  // Camera for gameplay
  private var camera = FixedCamera()

  // Simple pill mesh (we'll create this procedurally)
  private var pillMesh: MeshInstance?

  // Room boundaries
  private let roomSize: Float = 10.0
  private let boxSize: Float = 2.0
  private let boxPosition: vec3 = vec3(3, 0, 3)

  init() {
    setupGameplay()
  }

  private func setupGameplay() {
    // Set up camera to look down at the gameplay area
    camera.target = vec3(0, 0, 0)
    camera.position = vec3(0, 8, 5)

    // Create a simple pill mesh (capsule)
    createPillMesh()
  }

  private func createPillMesh() {
    // Generate a procedural pill mesh
    //let (vertices, indices) = PillMeshGenerator.generatePill(diameter: 1.0, height: 2.0, segments: 16)

    // TODO: Create a proper MeshInstance from the procedural data
    // For now, we'll just store the data and create a simple placeholder
    //print("Generated pill mesh with \(vertices.count / 8) vertices and \(indices.count / 3) triangles")

    // Create a simple box as placeholder until we implement proper procedural mesh loading
    pillMesh = nil  // No mesh for now
  }

  func update(window: Window, deltaTime: Float) {
    // Handle WASD movement
    handleMovement(window.keyboard, deltaTime)

    // Update camera to follow player
    camera.follow(playerPosition)
  }

  private func handleMovement(_ keyboard: Keyboard, _ deltaTime: Float) {
    let moveDistance = moveSpeed * deltaTime

    // WASD movement
    if keyboard.state(of: .w) == .pressed {
      playerPosition.z -= moveDistance
    }
    if keyboard.state(of: .s) == .pressed {
      playerPosition.z += moveDistance
    }
    if keyboard.state(of: .a) == .pressed {
      playerPosition.x -= moveDistance
    }
    if keyboard.state(of: .d) == .pressed {
      playerPosition.x += moveDistance
    }

    // Simple collision with room boundaries
    let halfRoom = roomSize / 2.0
    playerPosition.x = max(-halfRoom, min(halfRoom, playerPosition.x))
    playerPosition.z = max(-halfRoom, min(halfRoom, playerPosition.z))

    // Simple collision with box
    let halfBox = boxSize / 2.0
    let diff = playerPosition - boxPosition
    let diffX = diff.x * diff.x
    let diffY = diff.y * diff.y
    let diffZ = diff.z * diff.z
    let distanceToBox = GLMath.sqrt(diffX + diffY + diffZ)
    if distanceToBox < halfBox + 0.5 {  // 0.5 is player radius
      // Push player away from box
      let direction = diff / distanceToBox
      playerPosition = boxPosition + direction * (halfBox + 0.5)
    }
  }

  func draw() {
    // Clear screen
    glClearColor(0.1, 0.1, 0.1, 1.0)
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT)

    // Set up 3D rendering
    let aspectRatio = Float(Engine.viewportSize.width) / Float(Engine.viewportSize.height)
    let projection = GLMath.perspective(45.0, aspectRatio, 0.1, 100.0)
    let view = camera.getViewMatrix()

    // Draw player pill
    if let pill = pillMesh {
      let modelMatrix = GLMath.translate(mat4(1), playerPosition)
      pill.draw(
        projection: projection,
        view: view,
        modelMatrix: modelMatrix,
        cameraPosition: camera.position,
        lightDirection: vec3(0, -1, 0),
        lightColor: vec3(1, 1, 1),
        lightIntensity: 1.0,
        fillLightDirection: vec3(-0.3, -0.5, -0.2),
        fillLightColor: vec3(0.8, 0.9, 1.0),
        fillLightIntensity: 0.4,
        diffuseOnly: false
      )
//    } else {
//      // TODO: Draw procedural pill mesh directly
//      print("No pill mesh loaded - procedural mesh not yet implemented")
    }

    // Draw room floor (simple quad)
    drawRoom()

    // Draw box obstacle
    drawBox()
  }

  private func drawRoom() {
    // Simple room visualization - just draw the floor
    // TODO: Add proper room mesh
  }

  private func drawBox() {
    // Simple box obstacle
    // TODO: Add proper box mesh
  }
}
