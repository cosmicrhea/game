//final class PhysicsDemo: RenderLoop {
//  private var window: Window?
//  private var camera = FreeCamera()
//
//  // Physics world
//  private var physicsBodies: [PhysicsBody] = []
//
//  // Rendering
//  private let program = try! GLProgram("Common/basic 2")
//  private let sphereRenderer: SphereRenderer
//  private let planeRenderer: PlaneRenderer
//  private let determination = … // FIXME
//  private let inputPrompts: InputPromptsRenderer
//
//  // Demo state
//  private var timeSinceLastSphere: Float = 0.0
//  private let sphereSpawnInterval: Float = 1.0
//  private var sphereCount: Int = 0
//  private let maxSpheres: Int = 20
//
//  // Physics constants
//  private let gravity: Float = -9.81
//  private let groundY: Float = -2.0
//
//  init() {
//    self.sphereRenderer = SphereRenderer()
//    self.planeRenderer = PlaneRenderer()
//    self.inputPrompts = InputPromptsRenderer()
//  }
//
//  @MainActor func onAttach(window: Window) {
//    self.window = window
//    setupPhysics()
//  }
//
//  @MainActor func onDetach(window: Window) {
//    self.window = nil
//    physicsBodies.removeAll()
//  }
//
//  @MainActor func onMouseMove(window: Window, x: Double, y: Double) -> Bool {
//    guard window.isFocused else { return false }
//    camera.processMousePosition(Float(x), Float(y))
//    GLScreenEffect.mousePosition = (Float(x), Float(y))
//    return false
//  }
//
//  @MainActor func onScroll(window: Window, xOffset: Double, yOffset: Double) -> Bool {
//    camera.processMouseScroll(Float(yOffset))
//    return false
//  }
//
//  @MainActor func onKey(
//    window: Window, key: Keyboard.Key, scancode: Int32, state: ButtonState, mods: Keyboard.Modifier
//  ) -> Bool {
//    guard state == .pressed else { return false }
//
//    switch key {
//    case .space:
//      spawnSphere()
//      return true
//    case .r:
//      resetDemo()
//      return true
//    default:
//      return false
//    }
//  }
//
//  @MainActor func update(deltaTime: Float) {
//    if let w = window {
//      camera.processKeyboardState(w.keyboard, deltaTime)
//    }
//
//    // Update physics simulation
//    updatePhysics(deltaTime: deltaTime)
//
//    // Auto-spawn spheres
//    timeSinceLastSphere += deltaTime
//    if timeSinceLastSphere >= sphereSpawnInterval && sphereCount < maxSpheres {
//      spawnSphere()
//      timeSinceLastSphere = 0.0
//    }
//  }
//
//  @MainActor func draw() {
//    // Matrices
//    let projection = GLMath.perspective(camera.zoom, 1, 0.001, 1000.0)
//    let view = camera.getViewMatrix()
//
//    program.use()
//    program.setMat4("projection", value: projection)
//    program.setMat4("view", value: view)
//
//    // Draw ground plane
//    var groundTransform = mat4(1)
//    groundTransform = GLMath.translate(groundTransform, vec3(0, groundY, 0))
//    program.setMat4("model", value: groundTransform)
//    program.setVec3("color", value: (0.3, 0.6, 0.3))
//    planeRenderer.draw()
//
//    // Draw physics bodies
//    for body in physicsBodies {
//      if !body.isStatic {
//        let transform = body.getTransform()
//        program.setMat4("model", value: transform)
//        program.setVec3("color", value: (body.color.x, body.color.y, body.color.z))
//        sphereRenderer.draw()
//      }
//    }
//
//    // UI
//    drawUI()
//  }
//
//  private func setupPhysics() {
//    // Create ground plane (static)
//    let groundBody = PhysicsBody(
//      type: .static,
//      shape: .plane(normal: vec3(0, 1, 0)),
//      position: vec3(0, groundY, 0),
//      color: vec3(0.3, 0.6, 0.3)
//    )
//    physicsBodies.append(groundBody)
//  }
//
//  private func spawnSphere() {
//    guard sphereCount < maxSpheres else { return }
//
//    let x = Float.random(in: -3...3)
//    let y = Float.random(in: 5...10)
//    let z = Float.random(in: -3...3)
//
//    let colors: [vec3] = [
//      vec3(1.0, 0.2, 0.2),  // Red
//      vec3(0.2, 0.2, 1.0),  // Blue
//      vec3(1.0, 1.0, 0.2),  // Yellow
//      vec3(0.2, 1.0, 0.2),  // Green
//      vec3(1.0, 0.2, 1.0),  // Magenta
//      vec3(0.2, 1.0, 1.0),  // Cyan
//    ]
//
//    let color = colors.randomElement() ?? vec3(1.0, 1.0, 1.0)
//    let radius = Float.random(in: 0.3...0.8)
//
//    let sphereBody = PhysicsBody(
//      type: .dynamic,
//      shape: .sphere(radius: radius),
//      position: vec3(x, y, z),
//      color: color
//    )
//
//    physicsBodies.append(sphereBody)
//    sphereCount += 1
//  }
//
//  private func resetDemo() {
//    physicsBodies.removeAll { body in
//      if body.isStatic {
//        return false  // Keep ground plane
//      } else {
//        return true
//      }
//    }
//    sphereCount = 0
//    timeSinceLastSphere = 0.0
//  }
//
//  private func updatePhysics(deltaTime: Float) {
//    // Update all dynamic bodies
//    for body in physicsBodies {
//      if body.type == .dynamic {
//        // Apply gravity
//        body.velocity.y += gravity * deltaTime
//
//        // Update position
//        body.position += body.velocity * deltaTime
//
//        // Simple ground collision
//        if case .sphere(let radius) = body.shape {
//          if body.position.y - radius <= groundY {
//            body.position.y = groundY + radius
//            body.velocity.y *= -0.7  // Bounce with energy loss
//            body.velocity.x *= 0.99  // Friction
//            body.velocity.z *= 0.99  // Friction
//          }
//        }
//
//        // Remove spheres that fall too far
//        if body.position.y < -20 {
//          if let index = physicsBodies.firstIndex(where: { $0 === body }) {
//            physicsBodies.remove(at: index)
//            sphereCount -= 1
//          }
//        }
//      }
//    }
//
//    // Handle sphere-to-sphere collisions
//    handleSphereCollisions()
//  }
//
//  private func handleSphereCollisions() {
//    let dynamicBodies = physicsBodies.filter { $0.type == .dynamic }
//
//    for i in 0..<dynamicBodies.count {
//      for j in (i + 1)..<dynamicBodies.count {
//        let body1 = dynamicBodies[i]
//        let body2 = dynamicBodies[j]
//
//        // Check if both are spheres
//        if case .sphere(let radius1) = body1.shape,
//          case .sphere(let radius2) = body2.shape
//        {
//
//          let distance = length(body1.position - body2.position)
//          let minDistance = radius1 + radius2
//
//          // Collision detected
//          if distance < minDistance && distance > 0 {
//            // Calculate collision normal
//            let collisionNormal = normalize(body2.position - body1.position)
//
//            // Separate spheres
//            let overlap = minDistance - distance
//            let separation = collisionNormal * (overlap * 0.5)
//            body1.position -= separation
//            body2.position += separation
//
//            // Calculate relative velocity
//            let relativeVelocity = body2.velocity - body1.velocity
//            let velocityAlongNormal = dot(relativeVelocity, collisionNormal)
//
//            // Don't resolve if velocities are separating
//            if velocityAlongNormal > 0 {
//              continue
//            }
//
//            // Calculate restitution (bounciness)
//            let restitution: Float = 0.8
//
//            // Calculate impulse scalar
//            let impulseScalar = -(1 + restitution) * velocityAlongNormal
//            let impulse = collisionNormal * impulseScalar
//
//            // Apply impulse
//            body1.velocity += impulse
//            body2.velocity -= impulse
//
//            // Add some damping to prevent infinite bouncing
//            body1.velocity *= 0.99
//            body2.velocity *= 0.99
//          }
//        }
//      }
//    }
//  }
//
//  @MainActor private func drawUI() {
//    // Debug info
//    let debugText = String(
//      format: "Physics Demo - Spheres: %d/%d | FPS: %.1f",
//      sphereCount, maxSpheres, 1.0 / (deltaTime > 0 ? deltaTime : 0.016)
//    )
//    determination.draw(
//      debugText,
//      at: (24, Float(HEIGHT) - 24),
//      windowSize: (Int32(WIDTH), Int32(HEIGHT)),
//      alignment: .topLeft
//    )
//
//    // Instructions
//    let instructions = "SPACE: Spawn sphere | R: Reset | Mouse: Look | Scroll: Zoom"
//    determination.draw(
//      instructions,
//      at: (24, 24),
//      windowSize: (Int32(WIDTH), Int32(HEIGHT)),
//      alignment: .bottomLeft
//    )
//  }
//}
//
//// MARK: - Physics Body
//
//class PhysicsBody {
//  enum BodyType {
//    case `static`
//    case dynamic
//  }
//
//  enum Shape {
//    case sphere(radius: Float)
//    case plane(normal: vec3)
//  }
//
//  let type: BodyType
//  let shape: Shape
//  var position: vec3
//  var velocity: vec3
//  var rotation: mat4
//  let color: vec3
//
//  init(type: BodyType, shape: Shape, position: vec3, color: vec3) {
//    self.type = type
//    self.shape = shape
//    self.position = position
//    self.velocity = vec3(0, 0, 0)
//    self.rotation = mat4(1)
//    self.color = color
//  }
//
//  var isStatic: Bool {
//    return type == .static
//  }
//
//  func getTransform() -> mat4 {
//    let translation = GLMath.translate(mat4(1), position)
//    let rotationMatrix = rotation
//    return translation * rotationMatrix
//  }
//}
//
//// MARK: - Sphere Renderer
//
//final class SphereRenderer {
//  private var vertexBuffer: GLuint = 0
//  private var vertexArray: GLuint = 0
//  private var indexBuffer: GLuint = 0
//  private var indexCount: Int = 0
//
//  init() {
//    generateSphereGeometry()
//  }
//
//  deinit {
//    if vertexBuffer != 0 {
//      var b = vertexBuffer
//      glDeleteBuffers(1, &b)
//    }
//    if vertexArray != 0 {
//      var a = vertexArray
//      glDeleteVertexArrays(1, &a)
//    }
//    if indexBuffer != 0 {
//      var b = indexBuffer
//      glDeleteBuffers(1, &b)
//    }
//  }
//
//  private func generateSphereGeometry() {
//    let segments = 32
//    let rings = 16
//
//    var vertices: [Float] = []
//    var indices: [UInt32] = []
//
//    // Generate vertices
//    for ring in 0...rings {
//      let v = Float(ring) / Float(rings)
//      let phi = v * Float.pi
//
//      for segment in 0...segments {
//        let u = Float(segment) / Float(segments)
//        let theta = u * 2.0 * Float.pi
//
//        let x = sin(phi) * cos(theta)
//        let y = cos(phi)
//        let z = sin(phi) * sin(theta)
//
//        vertices.append(x)
//        vertices.append(y)
//        vertices.append(z)
//      }
//    }
//
//    // Generate indices
//    for ring in 0..<rings {
//      for segment in 0..<segments {
//        let current = UInt32(ring * (segments + 1) + segment)
//        let next = UInt32(current + UInt32(segments + 1))
//
//        // First triangle
//        indices.append(current)
//        indices.append(next)
//        indices.append(current + 1)
//
//        // Second triangle
//        indices.append(current + 1)
//        indices.append(next)
//        indices.append(next + 1)
//      }
//    }
//
//    indexCount = indices.count
//
//    // Upload to GPU
//    glGenVertexArrays(1, &vertexArray)
//    glGenBuffers(1, &vertexBuffer)
//    glGenBuffers(1, &indexBuffer)
//
//    glBindVertexArray(vertexArray)
//
//    glBindBuffer(GL_ARRAY_BUFFER, vertexBuffer)
//    glBufferData(
//      GL_ARRAY_BUFFER,
//      vertices.count * MemoryLayout<Float>.stride,
//      vertices,
//      GL_STATIC_DRAW
//    )
//
//    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, indexBuffer)
//    glBufferData(
//      GL_ELEMENT_ARRAY_BUFFER,
//      indices.count * MemoryLayout<UInt32>.stride,
//      indices,
//      GL_STATIC_DRAW
//    )
//
//    glVertexAttribPointer(
//      index: 0,
//      size: 3,
//      type: GL_FLOAT,
//      normalized: false,
//      stride: GLsizei(3 * MemoryLayout<Float>.stride),
//      pointer: nil
//    )
//    glEnableVertexAttribArray(0)
//
//    glBindVertexArray(0)
//  }
//
//  func draw() {
//    glBindVertexArray(vertexArray)
//    glDrawElements(GL_TRIANGLES, GLsizei(indexCount), GL_UNSIGNED_INT, nil)
//    glBindVertexArray(0)
//  }
//}
//
//// MARK: - Plane Renderer
//
//final class PlaneRenderer {
//  private var vertexBuffer: GLuint = 0
//  private var vertexArray: GLuint = 0
//  private var indexBuffer: GLuint = 0
//  private var indexCount: Int = 0
//
//  init() {
//    let vertices: [Float] = [
//      -10.0, 0.0, -10.0,
//      10.0, 0.0, -10.0,
//      10.0, 0.0, 10.0,
//      -10.0, 0.0, 10.0,
//    ]
//
//    let indices: [UInt32] = [
//      0, 1, 2,
//      0, 2, 3,
//    ]
//
//    indexCount = indices.count
//
//    glGenVertexArrays(1, &vertexArray)
//    glGenBuffers(1, &vertexBuffer)
//    glGenBuffers(1, &indexBuffer)
//
//    glBindVertexArray(vertexArray)
//
//    glBindBuffer(GL_ARRAY_BUFFER, vertexBuffer)
//    glBufferData(
//      GL_ARRAY_BUFFER,
//      vertices.count * MemoryLayout<Float>.stride,
//      vertices,
//      GL_STATIC_DRAW
//    )
//
//    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, indexBuffer)
//    glBufferData(
//      GL_ELEMENT_ARRAY_BUFFER,
//      indices.count * MemoryLayout<UInt32>.stride,
//      indices,
//      GL_STATIC_DRAW
//    )
//
//    glVertexAttribPointer(
//      index: 0,
//      size: 3,
//      type: GL_FLOAT,
//      normalized: false,
//      stride: GLsizei(3 * MemoryLayout<Float>.stride),
//      pointer: nil
//    )
//    glEnableVertexAttribArray(0)
//
//    glBindVertexArray(0)
//  }
//
//  deinit {
//    if vertexBuffer != 0 {
//      var b = vertexBuffer
//      glDeleteBuffers(1, &b)
//    }
//    if vertexArray != 0 {
//      var a = vertexArray
//      glDeleteVertexArrays(1, &a)
//    }
//    if indexBuffer != 0 {
//      var b = indexBuffer
//      glDeleteBuffers(1, &b)
//    }
//  }
//
//  func draw() {
//    glBindVertexArray(vertexArray)
//    glDrawElements(GL_TRIANGLES, GLsizei(indexCount), GL_UNSIGNED_INT, nil)
//    glBindVertexArray(0)
//  }
//}
