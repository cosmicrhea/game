import Foundation
import GLMath

@Editable final class ParticlesDemo: RenderLoop {
  private var currentEffectIndex: Int = 0
  var currentEmitter: ParticleEmitter?
  private var camera = FreeCamera()
  private var timeSinceLastSpawn: Float = 0.0
  private var autoSpawnInterval: Float = 2.0  // Spawn new effect every 2 seconds
  private var floorMeshInstance: MeshInstance?
  private var showFloor: Bool = true
  private var showControls: Bool = true
  
  private let effects: [ParticleEffect] = [
    // .splash,
    // .smoke,
    .blood,
    // .bubbles,
    .muzzleSmoke,
  ]
  
  // Mutable copy of current effect for editing
  @Editor(displayName: "Current Effect") var currentEffect: ParticleEffect = .blood {
    didSet {
      // Update emitter when effect changes
      if let emitter = currentEmitter {
        emitter.setEffect(currentEffect)
      }
    }
  }
  
  func onAttach(window: Window) {
    // Reset camera
    camera = FreeCamera()
    // Initialize currentEffect from the preset
    currentEffect = effects[currentEffectIndex]
    spawnCurrentEffect()
    // Create floor
    createFloor()
  }
  
  private func createFloor() {
    // Create a 10x10 meter floor subdivided into 1x1 meter rectangles
    let floorSize: Float = 10.0
    let subdivisionSize: Float = 1.0
    let gridSize = Int(floorSize / subdivisionSize)  // 10 subdivisions
    
    var positions: [Float] = []
    var normals: [Float] = []
    var uvs: [Float] = []
    var faces: [Face] = []
    
    // Create grid of vertices (11x11 = 121 vertices)
    let vertexCount = (gridSize + 1) * (gridSize + 1)
    positions.reserveCapacity(vertexCount * 3)
    normals.reserveCapacity(vertexCount * 3)
    uvs.reserveCapacity(vertexCount * 2)
    
    let halfSize = floorSize / 2.0
    
    // Generate vertices
    for z in 0...gridSize {
      for x in 0...gridSize {
        let xPos = Float(x) * subdivisionSize - halfSize
        let zPos = Float(z) * subdivisionSize - halfSize
        
        positions.append(xPos)
        positions.append(0.0)  // Y = 0 (floor level)
        positions.append(zPos)
        
        // Normal pointing up
        normals.append(0.0)
        normals.append(1.0)
        normals.append(0.0)
        
        // UV coordinates (tile the texture per 1x1 square)
        uvs.append(Float(x))
        uvs.append(Float(z))
      }
    }
    
    // Generate faces (2 triangles per square)
    for z in 0..<gridSize {
      for x in 0..<gridSize {
        let topLeft = z * (gridSize + 1) + x
        let topRight = topLeft + 1
        let bottomLeft = (z + 1) * (gridSize + 1) + x
        let bottomRight = bottomLeft + 1
        
        // First triangle
        faces.append(Face(indices: [topLeft, bottomLeft, topRight]))
        // Second triangle
        faces.append(Face(indices: [topRight, bottomLeft, bottomRight]))
      }
    }
    
    // Create mesh
    let floorMesh = Mesh(
      name: "Floor",
      numberOfVertices: vertexCount,
      numberOfFaces: faces.count,
      positions: positions,
      normals: normals,
      uvs: uvs,
      faces: faces
    )
    
    // Create a material with the floor texture
    let floorMaterial = Material(
      name: "Floor",
      materialIndex: 0,
      baseColor: vec3(1.0, 1.0, 1.0),
      diffuseTexture: Material.TextureInfo(
        path: "Debug/prototype_texture_07_dark.png",
        wrapS: .repeat,
        wrapT: .repeat,
        texCoord: 0,
        samplerIndex: nil
      )
    )
    
    // Create a minimal Scene for MeshInstance
    let emptyAnimations: [Animation] = []
    let emptyTextures: [EmbeddedTexture] = []
    let emptyCameras: [Camera] = []
    let emptyLights: [Light] = []
    let rootNode = Node(
      name: "Root",
      transformation: mat4(1),
      meshes: [],
      children: []
    )
    
    let scene = Scene(
      filePath: "ParticlesDemo",
      rootNode: rootNode,
      meshes: [floorMesh],
      materials: [floorMaterial],
      cameras: emptyCameras,
      lights: emptyLights,
      animations: emptyAnimations,
      embeddedTextures: emptyTextures
    )
    
    // Create mesh instance with identity transform (floor at Y=0)
    let meshInstance = MeshInstance(
      sceneData: scene,
      mesh: floorMesh,
      transformMatrix: mat4(1),
      sceneIdentifier: "ParticlesDemo"
    )
    
    // Load textures
    Task {
      await meshInstance.loadTextures()
    }
    
    floorMeshInstance = meshInstance
  }
  
  func onDetach(window: Window) {
    ParticleSystem.shared.clear()
    currentEmitter = nil
  }
  
  func onMouseMove(window: Window, x: Double, y: Double) {
    guard window.isFocused else { return }
    camera.processMousePosition(Float(x), Float(y))
  }
  
  func onMouseButtonPressed(window: Window, button: Mouse.Button, mods: Keyboard.Modifier) {
    if button == .left {
      camera.startDragging()
    }
  }
  
  func onMouseButtonReleased(window: Window, button: Mouse.Button, mods: Keyboard.Modifier) {
    if button == .left {
      camera.stopDragging()
    }
  }
  
  func onScroll(window: Window, xOffset: Double, yOffset: Double) {
    camera.processMouseScroll(Float(yOffset))
  }
  
  func onKeyPressed(window: Window, key: Keyboard.Key, scancode: Int32, mods: Keyboard.Modifier) {
    switch key {
    case .num1:
      cycleEffect(forward: false)
    case .num3:
      cycleEffect(forward: true)
    case .space:
      spawnCurrentEffect()
    case .r:
      ParticleSystem.shared.clear()
      currentEmitter = nil
    case .f:
      showFloor.toggle()
    case .z:
      showControls.toggle()
    default:
      break
    }
  }
  
  func update(window: Window, deltaTime: Float) {
    // Update camera
    camera.processKeyboardState(window.keyboard, deltaTime)
    
    // Update particle system
    ParticleSystem.shared.update(deltaTime: deltaTime)
    
    // Auto-spawn for continuous effects
    timeSinceLastSpawn += deltaTime
    if timeSinceLastSpawn >= autoSpawnInterval {
      if currentEffect.emissionMode == .continuous {
        // For continuous effects, spawn a new emitter periodically
        spawnCurrentEffect()
      }
      timeSinceLastSpawn = 0.0
    }
  }
  
  func draw() {
    // Set almost white background for better particle visibility
    GraphicsContext.current?.renderer.setClearColor(.gray100)
    
    // Set up 3D rendering
    let aspectRatio = Float(Engine.viewportSize.width) / Float(Engine.viewportSize.height)
    let projection = GLMath.perspective(camera.zoom, aspectRatio, 0.1, 1000.0)
    let view = camera.getViewMatrix()
    let cameraPosition = camera.position
    
    // Render floor with basic lighting (if enabled)
    if showFloor, let floor = floorMeshInstance {
      let lightDirection = normalize(vec3(0.5, 1.0, 0.3))
      let lightColor = vec3(1.0, 1.0, 1.0)
      let fillLightDirection = normalize(vec3(-0.5, 0.5, -0.3))
      let fillLightColor = vec3(0.3, 0.3, 0.4)
      
      floor.draw(
        projection: projection,
        view: view,
        cameraPosition: cameraPosition,
        lightDirection: lightDirection,
        lightColor: lightColor,
        lightIntensity: 1.0,
        fillLightDirection: fillLightDirection,
        fillLightColor: fillLightColor,
        fillLightIntensity: 0.3
      )
    }
    
    // Render particles
    ParticleSystem.shared.render(projection: projection, view: view, cameraPosition: cameraPosition)
    
    // Draw UI (if enabled)
    if showControls {
      drawUI()
    }
  }
  
  private func cycleEffect(forward: Bool) {
    let newIndex: Int
    if forward {
      newIndex = (currentEffectIndex + 1) % effects.count
    } else {
      newIndex = (currentEffectIndex - 1 + effects.count) % effects.count
    }
    
    guard newIndex != currentEffectIndex else { return }
    
    currentEffectIndex = newIndex
    currentEffect = effects[currentEffectIndex]  // Update editable effect
    ParticleSystem.shared.clear()
    currentEmitter = nil
    spawnCurrentEffect()
    UISound.select()
  }
  
  private func spawnCurrentEffect() {
    // Use the editable currentEffect (which may have been modified)
    let effect = currentEffect
    
    // Spawn at a fixed position 1 meter above origin
    let spawnPosition = vec3(0, 1, 0)
    
    let emitter = ParticleSystem.shared.createEmitter(effect: effect, at: spawnPosition)
    currentEmitter = emitter
  }
  
  private func drawUI() {
    let effectName = currentEffect.name
    
    // Draw effect name
    effectName.draw(
      at: Point(20, Float(Engine.viewportSize.height) - 20),
      style: .itemName,
      anchor: .topLeft
    )
    
    // Draw instructions
    let instructions = "1/3: Cycle effect | SPACE: Spawn | R: Clear | F: Toggle floor | Z: Hide controls | Mouse: Look | Scroll: Zoom"
    instructions.draw(
      at: Point(20, 20),
      style: .itemDescription,
      anchor: .bottomLeft
    )
    
    // Draw effect info
    let modeText = currentEffect.emissionMode == .continuous ? "Continuous" : "Burst"
    let infoText = "Mode: \(modeText) | Particles: \(ParticleSystem.shared.getTotalParticleCount())"
    infoText.draw(
      at: Point(20, 60),
      style: .itemDescription,
      anchor: .bottomLeft
    )
  }
}
