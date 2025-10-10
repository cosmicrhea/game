import AppKit
import CoreVideo
import Foundation
import Metal
import MetalKit
import QuartzCore

public final class MTLRenderer: Renderer {
  private let device: MTLDevice
  private let commandQueue: MTLCommandQueue
  private let imagePipelineState: MTLRenderPipelineState
  private let pathPipelineState: MTLRenderPipelineState
  private let textureCache: CVMetalTextureCache

  // Metal layer and drawable management
  private let metalLayer: CAMetalLayer
  private var currentDrawable: CAMetalDrawable?

  private var currentViewportSize: Size = Size(0, 0)
  private var currentScale: Float = 1.0

  // Metal rendering state
  private var currentCommandBuffer: MTLCommandBuffer?
  private var currentRenderPassDescriptor: MTLRenderPassDescriptor?
  private var currentRenderEncoder: MTLRenderCommandEncoder?

  // Clear color state
  private var clearColor: Color = Color(red: 0.2, green: 0.1, blue: 0.1, alpha: 1.0)

  // Vertex buffers for rendering
  private var imageVertexBuffer: MTLBuffer?
  private var pathVertexBuffer: MTLBuffer?
  private var imageIndexBuffer: MTLBuffer?
  private var pathIndexBuffer: MTLBuffer?

  public init() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
      throw MTLRendererError.noMetalDevice
    }

    self.device = device
    self.commandQueue = device.makeCommandQueue()!

    // Create Metal layer
    self.metalLayer = CAMetalLayer()
    self.metalLayer.device = device
    self.metalLayer.pixelFormat = .bgra8Unorm
    self.metalLayer.framebufferOnly = true
    self.metalLayer.contentsScale = 1.0

    // Create texture cache
    var textureCache: CVMetalTextureCache?
    let result = CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
    guard result == kCVReturnSuccess, let cache = textureCache else {
      throw MTLRendererError.textureCacheCreationFailed
    }
    self.textureCache = cache

    // Create pipeline states
    self.imagePipelineState = try Self.createImagePipelineState(device: device)
    self.pathPipelineState = try Self.createPathPipelineState(device: device)

    // Create vertex buffers with larger sizes to handle complex scenes
    self.imageVertexBuffer = device.makeBuffer(length: 4096 * 16, options: [])  // 4096 vertices * 16 bytes per vertex
    self.pathVertexBuffer = device.makeBuffer(length: 4096 * 8, options: [])  // 4096 vertices * 8 bytes per vertex
    self.imageIndexBuffer = device.makeBuffer(length: 4096 * 4, options: [])  // 4096 indices * 4 bytes per index
    self.pathIndexBuffer = device.makeBuffer(length: 4096 * 4, options: [])  // 4096 indices * 4 bytes per index
  }

  public func beginFrame(viewportSize: Size, scale: Float) {
    self.currentViewportSize = viewportSize
    self.currentScale = scale

    // Update layer drawable size if needed
    let newSize = CGSize(width: CGFloat(viewportSize.width), height: CGFloat(viewportSize.height))
    if metalLayer.drawableSize != newSize {
      metalLayer.drawableSize = newSize
    }

    // Get next drawable from the layer
    guard let drawable = metalLayer.nextDrawable() else {
      print("MTLRenderer: Failed to get next drawable")
      return
    }
    self.currentDrawable = drawable

    // Create command buffer for this frame
    guard let commandBuffer = commandQueue.makeCommandBuffer() else {
      print("MTLRenderer: Failed to create command buffer")
      return
    }
    self.currentCommandBuffer = commandBuffer

    // Create render pass descriptor with actual texture attachment
    let renderPassDescriptor = MTLRenderPassDescriptor()
    renderPassDescriptor.colorAttachments[0].texture = drawable.texture
    renderPassDescriptor.colorAttachments[0].loadAction = .clear
    renderPassDescriptor.colorAttachments[0].storeAction = .store
    renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(
      red: Double(clearColor.red), green: Double(clearColor.green), blue: Double(clearColor.blue),
      alpha: Double(clearColor.alpha))

    self.currentRenderPassDescriptor = renderPassDescriptor

    // Create render command encoder
    guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
      print("MTLRenderer: Failed to create render command encoder")
      return
    }
    self.currentRenderEncoder = renderEncoder

    // Set viewport
    let viewport = MTLViewport(
      originX: 0, originY: 0,
      width: Double(viewportSize.width), height: Double(viewportSize.height),
      znear: 0.0, zfar: 1.0
    )
    renderEncoder.setViewport(viewport)
  }

  public func endFrame() {
    guard let renderEncoder = currentRenderEncoder,
      let commandBuffer = currentCommandBuffer,
      let drawable = currentDrawable
    else {
      return
    }

    // End encoding
    renderEncoder.endEncoding()

    // Present the drawable
    commandBuffer.present(drawable)

    // Commit the command buffer
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()

    // Clean up
    self.currentRenderEncoder = nil
    self.currentCommandBuffer = nil
    self.currentRenderPassDescriptor = nil
    self.currentDrawable = nil
  }

  // MARK: - Window Integration

  @MainActor
  public func attachToWindow(_ nsWindow: NSWindow) {
    guard let contentView = nsWindow.contentView else {
      print("MTLRenderer: No content view found")
      return
    }

    // Set the Metal layer as the content view's layer
    contentView.wantsLayer = true
    contentView.layer = metalLayer

    // Update layer frame to match content view bounds
    metalLayer.frame = contentView.bounds

    print("MTLRenderer: Metal layer attached to window")
  }

  public func drawImage(
    textureID: UInt64,
    in rect: Rect,
    tint: Color?
  ) {
    guard let renderEncoder = currentRenderEncoder,
      let vertexBuffer = imageVertexBuffer,
      let indexBuffer = imageIndexBuffer
    else {
      print("MTLRenderer.drawImage: No active render encoder or buffers")
      return
    }

    let x = rect.origin.x
    let y = rect.origin.y
    let w = rect.size.width
    let h = rect.size.height

    // Create quad vertices: x, y, u, v
    let vertices: [Float] = [
      x, y, 0, 0,
      x + w, y, 1, 0,
      x + w, y + h, 1, 1,
      x, y + h, 0, 1,
    ]
    let indices: [UInt32] = [0, 1, 2, 2, 3, 0]

    // Check buffer capacity
    let maxVertices = vertexBuffer.length / MemoryLayout<Float>.size
    let maxIndices = indexBuffer.length / MemoryLayout<UInt32>.size

    guard vertices.count <= maxVertices && indices.count <= maxIndices else {
      print(
        "MTLRenderer.drawImage: Buffer overflow - vertices: \(vertices.count)/\(maxVertices), indices: \(indices.count)/\(maxIndices)"
      )
      return
    }

    // Copy vertex data to buffer
    let vertexData = vertexBuffer.contents().bindMemory(to: Float.self, capacity: vertices.count)
    vertexData.initialize(from: vertices, count: vertices.count)

    // Copy index data to buffer
    let indexData = indexBuffer.contents().bindMemory(to: UInt32.self, capacity: indices.count)
    indexData.initialize(from: indices, count: indices.count)

    // Set up rendering state
    renderEncoder.setRenderPipelineState(imagePipelineState)
    renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

    // Create uniforms
    let mvp = createOrthographicMatrix(viewportSize: currentViewportSize)
    let tintColor = tint ?? .white

    var uniforms = ImageUniforms(
      mvp: mvp,
      tint: SIMD4<Float>(tintColor.red, tintColor.green, tintColor.blue, tintColor.alpha)
    )

    renderEncoder.setVertexBytes(&uniforms, length: MemoryLayout<ImageUniforms>.size, index: 0)
    renderEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<ImageUniforms>.size, index: 0)

    // For now, we'll use a placeholder texture since we don't have texture management yet
    // TODO: Implement proper texture management
    print("MTLRenderer.drawImage: textureID=\(textureID), rect=\(rect), tint=\(tint != nil ? "Color" : "nil")")

    // Draw the quad
    renderEncoder.drawIndexedPrimitives(
      type: .triangle,
      indexCount: indices.count,
      indexType: .uint32,
      indexBuffer: indexBuffer,
      indexBufferOffset: 0
    )
  }

  public func drawImageRegion(
    textureID: UInt64,
    in rect: Rect,
    uv: Rect,
    tint: Color?
  ) {
    guard let renderEncoder = currentRenderEncoder,
      let vertexBuffer = imageVertexBuffer,
      let indexBuffer = imageIndexBuffer
    else {
      print("MTLRenderer.drawImageRegion: No active render encoder or buffers")
      return
    }

    let x = rect.origin.x
    let y = rect.origin.y
    let w = rect.size.width
    let h = rect.size.height
    let u0 = uv.origin.x
    let v0 = uv.origin.y
    let u1 = uv.origin.x + uv.size.width
    let v1 = uv.origin.y + uv.size.height

    // Create quad vertices with UV coordinates
    let vertices: [Float] = [
      x, y, u0, v0,
      x + w, y, u1, v0,
      x + w, y + h, u1, v1,
      x, y + h, u0, v1,
    ]
    let indices: [UInt32] = [0, 1, 2, 2, 3, 0]

    // Copy vertex data to buffer
    let vertexData = vertexBuffer.contents().bindMemory(to: Float.self, capacity: vertices.count)
    vertexData.initialize(from: vertices, count: vertices.count)

    // Copy index data to buffer
    let indexData = indexBuffer.contents().bindMemory(to: UInt32.self, capacity: indices.count)
    indexData.initialize(from: indices, count: indices.count)

    // Set up rendering state
    renderEncoder.setRenderPipelineState(imagePipelineState)
    renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

    // Create uniforms
    let mvp = createOrthographicMatrix(viewportSize: currentViewportSize)
    let tintColor = tint ?? .white

    var uniforms = ImageUniforms(
      mvp: mvp,
      tint: SIMD4<Float>(tintColor.red, tintColor.green, tintColor.blue, tintColor.alpha)
    )

    renderEncoder.setVertexBytes(&uniforms, length: MemoryLayout<ImageUniforms>.size, index: 0)
    renderEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<ImageUniforms>.size, index: 0)

    // For now, we'll use a placeholder texture since we don't have texture management yet
    // TODO: Implement proper texture management
    print(
      "MTLRenderer.drawImageRegion: textureID=\(textureID), rect=\(rect), uv=\(uv), tint=\(tint != nil ? "Color" : "nil")"
    )

    // Draw the quad
    renderEncoder.drawIndexedPrimitives(
      type: .triangle,
      indexCount: indices.count,
      indexType: .uint32,
      indexBuffer: indexBuffer,
      indexBufferOffset: 0
    )
  }

  public func setClipRect(_ rect: Rect?) {
    // TODO: Implement Metal scissor rect
    print("MTLRenderer.setClipRect: \(rect != nil ? "Rect" : "nil")")
  }

  public func setWireframeMode(_ enabled: Bool) {
    // TODO: Implement Metal wireframe mode
    print("MTLRenderer.setWireframeMode: \(enabled)")
  }

  public func setClearColor(_ color: Color) {
    clearColor = color
  }

  public func drawPath(_ path: BezierPath, color: Color) {
    let (vertices, indices) = path.tessellate()
    drawTriangles(vertices: vertices, indices: indices, color: color)
  }

  public func drawStroke(_ path: BezierPath, color: Color, lineWidth: Float) {
    let (vertices, indices) = path.generateStrokeGeometry(lineWidth: lineWidth)
    guard !vertices.isEmpty && !indices.isEmpty else { return }

    drawTriangles(vertices: vertices, indices: indices, color: color)
  }

  // MARK: - Private Helpers

  private static func createImagePipelineState(device: MTLDevice) throws -> MTLRenderPipelineState {
    // Create library from source code
    let shaderSource = """
      #include <metal_stdlib>
      using namespace metal;

      struct ImageVertex {
          float2 position [[attribute(0)]];
          float2 uv [[attribute(1)]];
      };

      struct ImageVertexOut {
          float4 position [[position]];
          float2 uv;
      };

      struct ImageUniforms {
          float4x4 mvp;
          float4 tint;
      };

      vertex ImageVertexOut imageVertex(ImageVertex in [[stage_in]],
                                       constant ImageUniforms& uniforms [[buffer(0)]]) {
          ImageVertexOut out;
          out.position = uniforms.mvp * float4(in.position, 0.0, 1.0);
          out.uv = float2(in.uv.x, 1.0 - in.uv.y);
          return out;
      }

      fragment float4 imageFragment(ImageVertexOut in [[stage_in]],
                                   texture2d<float> texture [[texture(0)]],
                                   constant ImageUniforms& uniforms [[buffer(0)]]) {
          constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
          float4 texel = texture.sample(textureSampler, in.uv);
          return texel * uniforms.tint;
      }
      """

    let library = try device.makeLibrary(source: shaderSource, options: nil)

    guard let vertexFunction = library.makeFunction(name: "imageVertex"),
      let fragmentFunction = library.makeFunction(name: "imageFragment")
    else {
      throw MTLRendererError.shaderCompilationFailed
    }

    let pipelineDescriptor = MTLRenderPipelineDescriptor()
    pipelineDescriptor.vertexFunction = vertexFunction
    pipelineDescriptor.fragmentFunction = fragmentFunction
    pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
    pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
    pipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
    pipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
    pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
    pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
    pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
    pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

    // Vertex descriptor
    let vertexDescriptor = MTLVertexDescriptor()
    vertexDescriptor.attributes[0].format = .float2
    vertexDescriptor.attributes[0].offset = 0
    vertexDescriptor.attributes[0].bufferIndex = 0
    vertexDescriptor.attributes[1].format = .float2
    vertexDescriptor.attributes[1].offset = 8
    vertexDescriptor.attributes[1].bufferIndex = 0
    vertexDescriptor.layouts[0].stride = 16
    vertexDescriptor.layouts[0].stepRate = 1
    vertexDescriptor.layouts[0].stepFunction = .perVertex

    pipelineDescriptor.vertexDescriptor = vertexDescriptor

    return try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
  }

  private static func createPathPipelineState(device: MTLDevice) throws -> MTLRenderPipelineState {
    // Create library from source code
    let shaderSource = """
      #include <metal_stdlib>
      using namespace metal;

      struct PathVertex {
          float2 position [[attribute(0)]];
      };

      struct PathVertexOut {
          float4 position [[position]];
      };

      struct PathUniforms {
          float4x4 mvp;
          float4 color;
      };

      vertex PathVertexOut pathVertex(PathVertex in [[stage_in]],
                                     constant PathUniforms& uniforms [[buffer(0)]]) {
          PathVertexOut out;
          out.position = uniforms.mvp * float4(in.position, 0.0, 1.0);
          return out;
      }

      fragment float4 pathFragment(PathVertexOut in [[stage_in]],
                                  constant PathUniforms& uniforms [[buffer(0)]]) {
          return uniforms.color;
      }
      """

    let library = try device.makeLibrary(source: shaderSource, options: nil)

    guard let vertexFunction = library.makeFunction(name: "pathVertex"),
      let fragmentFunction = library.makeFunction(name: "pathFragment")
    else {
      throw MTLRendererError.shaderCompilationFailed
    }

    let pipelineDescriptor = MTLRenderPipelineDescriptor()
    pipelineDescriptor.vertexFunction = vertexFunction
    pipelineDescriptor.fragmentFunction = fragmentFunction
    pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
    pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
    pipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
    pipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
    pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
    pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
    pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
    pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

    // Vertex descriptor for path rendering (position only)
    let vertexDescriptor = MTLVertexDescriptor()
    vertexDescriptor.attributes[0].format = .float2
    vertexDescriptor.attributes[0].offset = 0
    vertexDescriptor.attributes[0].bufferIndex = 0
    vertexDescriptor.layouts[0].stride = 8
    vertexDescriptor.layouts[0].stepRate = 1
    vertexDescriptor.layouts[0].stepFunction = .perVertex

    pipelineDescriptor.vertexDescriptor = vertexDescriptor

    return try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
  }

  private func drawTriangles(vertices: [Float], indices: [UInt32], color: Color) {
    guard !vertices.isEmpty && !indices.isEmpty,
      let renderEncoder = currentRenderEncoder,
      let vertexBuffer = pathVertexBuffer,
      let indexBuffer = pathIndexBuffer
    else {
      print("MTLRenderer.drawTriangles: No active render encoder or buffers")
      return
    }

    // Check buffer capacity
    let maxVertices = vertexBuffer.length / MemoryLayout<Float>.size
    let maxIndices = indexBuffer.length / MemoryLayout<UInt32>.size

    guard vertices.count <= maxVertices && indices.count <= maxIndices else {
      print(
        "MTLRenderer.drawTriangles: Buffer overflow - vertices: \(vertices.count)/\(maxVertices), indices: \(indices.count)/\(maxIndices)"
      )
      return
    }

    // Copy vertex data to buffer
    let vertexData = vertexBuffer.contents().bindMemory(to: Float.self, capacity: vertices.count)
    vertexData.initialize(from: vertices, count: vertices.count)

    // Copy index data to buffer
    let indexData = indexBuffer.contents().bindMemory(to: UInt32.self, capacity: indices.count)
    indexData.initialize(from: indices, count: indices.count)

    // Set up rendering state
    renderEncoder.setRenderPipelineState(pathPipelineState)
    renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

    // Create uniforms
    let mvp = createOrthographicMatrix(viewportSize: currentViewportSize)

    var uniforms = PathUniforms(
      mvp: mvp,
      color: SIMD4<Float>(color.red, color.green, color.blue, color.alpha)
    )

    renderEncoder.setVertexBytes(&uniforms, length: MemoryLayout<PathUniforms>.size, index: 0)
    renderEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<PathUniforms>.size, index: 0)

    // Draw the triangles
    renderEncoder.drawIndexedPrimitives(
      type: .triangle,
      indexCount: indices.count,
      indexType: .uint32,
      indexBuffer: indexBuffer,
      indexBufferOffset: 0
    )
  }

  // MARK: - Helper Functions

  private func createOrthographicMatrix(viewportSize: Size) -> matrix_float4x4 {
    let left: Float = 0
    let right = viewportSize.width
    let bottom: Float = 0
    let top = viewportSize.height
    let near: Float = 0
    let far: Float = 1

    let m00 = 2 / (right - left)
    let m11 = 2 / (top - bottom)
    let m22 = -2 / (far - near)
    let m03 = -(right + left) / (right - left)
    let m13 = -(top + bottom) / (top - bottom)
    let m23 = -(far + near) / (far - near)

    return matrix_float4x4(
      SIMD4<Float>(m00, 0, 0, 0),
      SIMD4<Float>(0, m11, 0, 0),
      SIMD4<Float>(0, 0, m22, 0),
      SIMD4<Float>(m03, m13, m23, 1)
    )
  }

  public func drawText(
    _ attributedString: AttributedString,
    at origin: Point,
    defaultStyle: TextStyle,
    wrapWidth: Float?,
    anchor: TextAnchor,
    alignment: TextAlignment
  ) {
    // TODO: Implement Metal text rendering
    // For now, this is a stub that does nothing
    // In a full implementation, this would:
    // 1. ~~Create a ModularTextRenderer for the default style~~
    // 2. Convert AttributedString to legacy AttributedText
    // 3. Use Metal shaders to render the text
  }

}

// MARK: - Uniform Structures

struct ImageUniforms {
  var mvp: matrix_float4x4
  var tint: SIMD4<Float>
}

struct PathUniforms {
  var mvp: matrix_float4x4
  var color: SIMD4<Float>
}

// MARK: - Errors

public enum MTLRendererError: Error {
  case noMetalDevice
  case textureCacheCreationFailed
  case shaderCompilationFailed
}
