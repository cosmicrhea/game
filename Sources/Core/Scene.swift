import Assimp

/// Wrapper around Assimp.Scene that provides our own Node tree
public final class Scene {
  internal let assimpScene: Assimp.Scene

  // Our own Node tree (built upfront)
  public let rootNode: Node
  
  // Delegate to Assimp.Scene
  public var meshes: [Assimp.Mesh] { assimpScene.meshes }
  public var materials: [Assimp.Material] { assimpScene.materials }
  public var cameras: [Assimp.Camera] { assimpScene.cameras }
  public var lights: [Assimp.Light] { assimpScene.lights }
  public var textures: [Assimp.Texture] { assimpScene.textures }
  public var animations: [Assimp.Animation] { assimpScene.animations }
  public var filePath: String { assimpScene.filePath }
  public var numberOfMeshes: Int { assimpScene.numberOfMeshes }
  public var numberOfMaterials: Int { assimpScene.numberOfMaterials }
  public var numberOfCameras: Int { assimpScene.numberOfCameras }
  public var numberOfLights: Int { assimpScene.numberOfLights }
  public var numberOfTextures: Int { assimpScene.numberOfTextures }
  public var numberOfAnimations: Int { assimpScene.numberOfAnimations }
  public var hasMeshes: Bool { assimpScene.hasMeshes }
  public var hasMaterials: Bool { assimpScene.hasMaterials }
  public var hasCameras: Bool { assimpScene.hasCameras }
  public var hasLights: Bool { assimpScene.hasLights }
  public var hasTextures: Bool { assimpScene.hasTextures }
  public var hasAnimations: Bool { assimpScene.hasAnimations }
  public var flags: Assimp.Scene.Flags { assimpScene.flags }
    
  init(_ assimpScene: Assimp.Scene) {
    self.assimpScene = assimpScene
    // Build our own Node tree upfront
    self.rootNode = Node(assimpScene.rootNode)
  }
  
  /// Load a scene from a file
  public convenience init(file filePath: String, flags: Assimp.PostProcessStep = []) throws {
    let assimpScene = try Assimp.Scene(file: filePath, flags: flags)
    self.init(assimpScene)
  }
  
  /// Load a scene from a file with progress callback
  public convenience init(
    file filePath: String,
    flags: Assimp.PostProcessStep = [],
    progress: @escaping (Float) -> Bool
  ) throws {
    let assimpScene = try Assimp.Scene(file: filePath, flags: flags, progress: progress)
    self.init(assimpScene)
  }
  
  /// Get transform matrix for a mesh (delegates to Assimp.Scene extension)
  func getTransformMatrix(for mesh: Assimp.Mesh) -> mat4 {
    return assimpScene.getTransformMatrix(for: mesh)
  }
}

