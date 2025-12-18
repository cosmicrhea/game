/// TODO: docs
public struct Material {
  public let name: String?
  public let materialIndex: Int

  // PBR properties
  public let baseColor: vec3
  public let metallic: Float
  public let roughness: Float
  public let emissive: vec3
  public let opacity: Float

  // Texture paths (can be embedded texture references like "*0" or file paths)
  public let diffuseTexturePath: String?
  public let normalTexturePath: String?
  public let roughnessTexturePath: String?
  public let metallicTexturePath: String?
  public let aoTexturePath: String?

  public init(
    name: String? = nil,
    materialIndex: Int = 0,
    baseColor: vec3 = vec3(0.8, 0.8, 0.8),
    metallic: Float = 0.0,
    roughness: Float = 0.5,
    emissive: vec3 = vec3(0, 0, 0),
    opacity: Float = 1.0,
    diffuseTexturePath: String? = nil,
    normalTexturePath: String? = nil,
    roughnessTexturePath: String? = nil,
    metallicTexturePath: String? = nil,
    aoTexturePath: String? = nil
  ) {
    self.name = name
    self.materialIndex = materialIndex
    self.baseColor = baseColor
    self.metallic = metallic
    self.roughness = roughness
    self.emissive = emissive
    self.opacity = opacity
    self.diffuseTexturePath = diffuseTexturePath
    self.normalTexturePath = normalTexturePath
    self.roughnessTexturePath = roughnessTexturePath
    self.metallicTexturePath = metallicTexturePath
    self.aoTexturePath = aoTexturePath
  }
}
