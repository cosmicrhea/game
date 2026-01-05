import Foundation
import GLMath

/// Shadow map for rendering shadows from directional lights
public final class ShadowMap {
  private var shadowFBO: GLuint = 0
  private var shadowDepthTexture: GLuint = 0
  private let resolution: Int
  
  public init(resolution: Int = 2048) {
    self.resolution = resolution
    createShadowMap()
  }
  
  deinit {
    destroyShadowMap()
  }
  
  private func createShadowMap() {
    // Create framebuffer
    glGenFramebuffers(1, &shadowFBO)
    glBindFramebuffer(GL_FRAMEBUFFER, shadowFBO)
    
    // Create depth texture
    glGenTextures(1, &shadowDepthTexture)
    glBindTexture(GL_TEXTURE_2D, shadowDepthTexture)
    glTexImage2D(
      GL_TEXTURE_2D, 0, GL_DEPTH_COMPONENT,
      GLsizei(resolution), GLsizei(resolution),
      0, GL_DEPTH_COMPONENT, GL_FLOAT, nil
    )
    // Don't use GL_TEXTURE_COMPARE_MODE - we do manual PCF in the shader
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_BORDER)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_BORDER)
    
    // Set border color to white (areas outside shadow map are lit)
    let borderColor: [Float] = [1.0, 1.0, 1.0, 1.0]
    glTexParameterfv(GL_TEXTURE_2D, GL_TEXTURE_BORDER_COLOR, borderColor)
    
    // Attach depth texture to framebuffer
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_TEXTURE_2D, shadowDepthTexture, 0)
    
    // No color buffer needed for shadow map
    glDrawBuffer(GL_NONE)
    glReadBuffer(GL_NONE)
    
    // Check completeness
    let status = glCheckFramebufferStatus(GL_FRAMEBUFFER)
    if status != GL_FRAMEBUFFER_COMPLETE {
      logger.error("Shadow map framebuffer not complete: \(status)")
    }
    
    glBindFramebuffer(GL_FRAMEBUFFER, 0)
  }
  
  private func destroyShadowMap() {
    if shadowFBO != 0 {
      glDeleteFramebuffers(1, &shadowFBO)
      shadowFBO = 0
    }
    if shadowDepthTexture != 0 {
      glDeleteTextures(1, &shadowDepthTexture)
      shadowDepthTexture = 0
    }
  }
  
  public func bindForWriting() {
    glBindFramebuffer(GL_FRAMEBUFFER, shadowFBO)
    glViewport(0, 0, GLsizei(resolution), GLsizei(resolution))
    // Clear depth to far plane (1.0) so unrendered areas are lit
    glClearDepth(1.0)
    glClear(GL_DEPTH_BUFFER_BIT)
  }
  
  public func bindForReading(textureUnit: GLenum = GL_TEXTURE4) {
    glActiveTexture(textureUnit)
    glBindTexture(GL_TEXTURE_2D, shadowDepthTexture)
  }
  
  public func getTextureID() -> GLuint {
    return shadowDepthTexture
  }
  
  /// Calculate light space matrix (orthographic projection from light's view)
  public static func calculateLightSpaceMatrix(
    lightDirection: vec3,
    sceneBounds: (min: vec3, max: vec3),
    shadowDistance: Float = 50.0
  ) -> mat4 {
    // Calculate scene center and size
    let center = (sceneBounds.min + sceneBounds.max) * 0.5
    let size = sceneBounds.max - sceneBounds.min
    
    // Create orthographic projection from light's perspective
    let lightDir = normalize(lightDirection)
    let lightPos = center - lightDir * shadowDistance * 0.5
    let worldUp = vec3(0, 1, 0)
    let up = abs(dot(lightDir, worldUp)) > 0.98 ? vec3(0, 0, 1) : worldUp
    let lightView = GLMath.lookAt(
      lightPos,
      center,
      up
    )
    
    // Orthographic projection covering the scene
    let orthoSize = max(size.x, max(size.y, size.z)) * 1.5
    let lightProjection = GLMath.ortho(
      -orthoSize,
      orthoSize,
      -orthoSize,
      orthoSize,
      0.1,
      shadowDistance
    )
    
    return lightProjection * lightView
  }
}
