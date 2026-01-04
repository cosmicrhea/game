import GLTF

/// TODO: docs
public struct Material {
  public struct TextureInfo {
    public let path: String
    public let wrapS: GLTFWrapMode
    public let wrapT: GLTFWrapMode
    public let texCoord: Int
    public let samplerIndex: Int?

    public init(
      path: String,
      wrapS: GLTFWrapMode,
      wrapT: GLTFWrapMode,
      texCoord: Int = 0,
      samplerIndex: Int? = nil
    ) {
      self.path = path
      self.wrapS = wrapS
      self.wrapT = wrapT
      self.texCoord = texCoord
      self.samplerIndex = samplerIndex
    }
  }

  public let name: String?
  public let materialIndex: Int

  // PBR properties
  public let baseColor: vec3
  public let metallic: Float
  public let roughness: Float
  public let emissive: vec3
  public let opacity: Float

  // Alpha mode for transparency handling
  public let alphaMode: GLTFAlphaMode
  public let alphaCutoff: Float

  // Double-sided rendering (for hair cards like eyebrows/eyelashes)
  public let isDoubleSided: Bool

  // Depth bias role for explicit render ordering (no name-based heuristics)
  public enum DepthBiasRole {
    case none      // No depth bias (face, body, clothes)
    case eye       // Eyes: must pass depth test, render after face or use small negative offset
    case hairRoot  // Hair roots: small offset to fix hairline black fringe
  }
  public let depthBiasRole: DepthBiasRole

  // Texture paths (can be embedded texture references like "*0" or file paths)
  public let diffuseTexture: TextureInfo?
  public let normalTexture: TextureInfo?
  public let roughnessTexture: TextureInfo?
  public let metallicTexture: TextureInfo?
  public let aoTexture: TextureInfo?

  public init(
    name: String? = nil,
    materialIndex: Int = 0,
    baseColor: vec3 = vec3(0.8, 0.8, 0.8),
    metallic: Float = 0.0,
    roughness: Float = 0.5,
    emissive: vec3 = vec3(0, 0, 0),
    opacity: Float = 1.0,
    alphaMode: GLTFAlphaMode = .opaque,
    alphaCutoff: Float = 0.5,
    isDoubleSided: Bool = false,
    depthBiasRole: DepthBiasRole = .none,
    diffuseTexture: TextureInfo? = nil,
    normalTexture: TextureInfo? = nil,
    roughnessTexture: TextureInfo? = nil,
    metallicTexture: TextureInfo? = nil,
    aoTexture: TextureInfo? = nil
  ) {
    self.name = name
    self.materialIndex = materialIndex
    self.baseColor = baseColor
    self.metallic = metallic
    self.roughness = roughness
    self.emissive = emissive
    self.opacity = opacity
    self.alphaMode = alphaMode
    self.alphaCutoff = alphaCutoff
    self.isDoubleSided = isDoubleSided
    self.depthBiasRole = depthBiasRole
    self.diffuseTexture = diffuseTexture
    self.normalTexture = normalTexture
    self.roughnessTexture = roughnessTexture
    self.metallicTexture = metallicTexture
    self.aoTexture = aoTexture
  }
}
