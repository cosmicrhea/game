import AppKit
import CoreVideo
import Metal
import MetalKit
import QuartzCore

public final class MTLRenderer: Renderer {
  private let device: MTLDevice
  private let commandQueue: MTLCommandQueue
  private let imagePipelineState: MTLRenderPipelineState
  private let pathPipelineState: MTLRenderPipelineState
  private let gradientPipelineState: MTLRenderPipelineState
  private let textureCache: CVMetalTextureCache

  // Metal layer and drawable management
  private let metalLayer: CAMetalLayer
  private var currentDrawable: CAMetalDrawable?

  private var currentViewportSize: Size = Size(0, 0)
  private var coordinateSpaceSize: Size = DESIGN_RESOLUTION
  private var currentScale: Float = 1.0

  public var viewportSize: Size {
    // Return coordinate space size (used for UI coordinates and orthographic matrix)
    // This may differ from the actual Metal viewport when VIEWPORT_SCALING is enabled
    return coordinateSpaceSize
  }

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
    self.gradientPipelineState = try Self.createGradientPipelineState(device: device)

    // Create vertex buffers with larger sizes to handle complex scenes
    self.imageVertexBuffer = device.makeBuffer(length: 4096 * 16, options: [])  // 4096 vertices * 16 bytes per vertex
    self.pathVertexBuffer = device.makeBuffer(length: 4096 * 8, options: [])  // 4096 vertices * 8 bytes per vertex
    self.imageIndexBuffer = device.makeBuffer(length: 4096 * 4, options: [])  // 4096 indices * 4 bytes per index
    self.pathIndexBuffer = device.makeBuffer(length: 4096 * 4, options: [])  // 4096 indices * 4 bytes per index
  }

  public func beginFrame(windowSize: Size) {
    // Store window size for actual Metal viewport
    currentViewportSize = windowSize

    // Coordinate space size is set separately via setCoordinateSpaceSize
    // Default to window size if not explicitly set
    if coordinateSpaceSize == DESIGN_RESOLUTION && windowSize != DESIGN_RESOLUTION {
      coordinateSpaceSize = windowSize
    }

    // Get next drawable from the layer
    guard let drawable = metalLayer.nextDrawable() else {
      logger.error("MTLRenderer: Failed to get next drawable")
      return
    }
    self.currentDrawable = drawable

    // Create command buffer for this frame
    guard let commandBuffer = commandQueue.makeCommandBuffer() else {
      logger.error("MTLRenderer: Failed to create command buffer")
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
      logger.error("MTLRenderer: Failed to create render command encoder")
      return
    }
    self.currentRenderEncoder = renderEncoder

    // Set Metal viewport to full window size
    let viewport = MTLViewport(
      originX: 0, originY: 0,
      width: Double(currentViewportSize.width), height: Double(currentViewportSize.height),
      znear: 0.0, zfar: 1.0
    )
    renderEncoder.setViewport(viewport)
  }

  /// Sets the coordinate space size used for UI coordinates and orthographic matrix.
  /// This may differ from the actual Metal viewport when VIEWPORT_SCALING is enabled.
  func setCoordinateSpaceSize(_ size: Size) {
    coordinateSpaceSize = size
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
      logger.error("MTLRenderer: No content view found")
      return
    }

    // Set the Metal layer as the content view's layer
    contentView.wantsLayer = true
    contentView.layer = metalLayer

    // Update layer frame to match content view bounds
    metalLayer.frame = contentView.bounds

    logger.trace("MTLRenderer: Metal layer attached to window")
  }

  public func drawImage(
    textureID: UInt64,
    in rect: Rect,
    tint: Color?,
    strokeWidth: Float,
    strokeColor: Color?
  ) {
    guard let renderEncoder = currentRenderEncoder,
      let vertexBuffer = imageVertexBuffer,
      let indexBuffer = imageIndexBuffer
    else {
      logger.warning("MTLRenderer.drawImage: No active render encoder or buffers")
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
      logger.error(
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
    let mvp = createOrthographicMatrix(viewportSize: coordinateSpaceSize)

    // For now, we'll use a placeholder texture since we don't have texture management yet
    // TODO: Implement proper texture management
    logger.trace("MTLRenderer.drawImage: textureID=\(textureID), rect=\(rect), tint=\(tint != nil ? "Color" : "nil")")

    // Draw stroke outline if specified
    if strokeWidth > 0, let strokeColor = strokeColor {
      var strokeUniforms = ImageUniforms(
        mvp: mvp,
        tint: SIMD4<Float>(strokeColor.red, strokeColor.green, strokeColor.blue, strokeColor.alpha)
      )

      renderEncoder.setFragmentBytes(&strokeUniforms, length: MemoryLayout<ImageUniforms>.size, index: 0)

      // Draw image at multiple offsets to create outline effect
      let offsets: [(Float, Float)] = [
        (-strokeWidth, 0), (strokeWidth, 0),
        (0, -strokeWidth), (0, strokeWidth),
        (-strokeWidth, -strokeWidth), (strokeWidth, strokeWidth),
        (-strokeWidth, strokeWidth), (strokeWidth, -strokeWidth),
      ]

      for (offsetX, offsetY) in offsets {
        var offsetVertices = vertices
        for i in stride(from: 0, to: offsetVertices.count, by: 4) {
          offsetVertices[i] += offsetX
          offsetVertices[i + 1] += offsetY
        }

        let offsetVertexData = vertexBuffer.contents().bindMemory(to: Float.self, capacity: offsetVertices.count)
        offsetVertexData.initialize(from: offsetVertices, count: offsetVertices.count)

        renderEncoder.drawIndexedPrimitives(
          type: .triangle,
          indexCount: indices.count,
          indexType: .uint32,
          indexBuffer: indexBuffer,
          indexBufferOffset: 0
        )
      }
    }

    // Draw fill
    let tintColor = tint ?? .white
    var fillUniforms = ImageUniforms(
      mvp: mvp,
      tint: SIMD4<Float>(tintColor.red, tintColor.green, tintColor.blue, tintColor.alpha)
    )

    let fillVertexData = vertexBuffer.contents().bindMemory(to: Float.self, capacity: vertices.count)
    fillVertexData.initialize(from: vertices, count: vertices.count)

    renderEncoder.setFragmentBytes(&fillUniforms, length: MemoryLayout<ImageUniforms>.size, index: 0)

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
    tint: Color?,
    strokeWidth: Float,
    strokeColor: Color?
  ) {
    guard let renderEncoder = currentRenderEncoder,
      let vertexBuffer = imageVertexBuffer,
      let indexBuffer = imageIndexBuffer
    else {
      logger.warning("MTLRenderer.drawImageRegion: No active render encoder or buffers")
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
    var mvp = createOrthographicMatrix(viewportSize: currentViewportSize)

    // For now, we'll use a placeholder texture since we don't have texture management yet
    // TODO: Implement proper texture management
    logger.trace(
      "MTLRenderer.drawImageRegion: textureID=\(textureID), rect=\(rect), uv=\(uv), tint=\(tint != nil ? "Color" : "nil")"
    )

    // Draw stroke outline if specified
    if strokeWidth > 0, let strokeColor = strokeColor {
      var strokeUniforms = ImageUniforms(
        mvp: mvp,
        tint: SIMD4<Float>(strokeColor.red, strokeColor.green, strokeColor.blue, strokeColor.alpha)
      )

      renderEncoder.setVertexBytes(&mvp, length: MemoryLayout<float4x4>.size, index: 0)
      renderEncoder.setFragmentBytes(&strokeUniforms, length: MemoryLayout<ImageUniforms>.size, index: 0)

      // Draw image at multiple offsets to create outline effect
      let offsets: [(Float, Float)] = [
        (-strokeWidth, 0), (strokeWidth, 0),
        (0, -strokeWidth), (0, strokeWidth),
        (-strokeWidth, -strokeWidth), (strokeWidth, strokeWidth),
        (-strokeWidth, strokeWidth), (strokeWidth, -strokeWidth),
      ]

      for (offsetX, offsetY) in offsets {
        var offsetVertices = vertices
        for i in stride(from: 0, to: offsetVertices.count, by: 4) {
          offsetVertices[i] += offsetX
          offsetVertices[i + 1] += offsetY
        }

        let offsetVertexData = vertexBuffer.contents().bindMemory(to: Float.self, capacity: offsetVertices.count)
        offsetVertexData.initialize(from: offsetVertices, count: offsetVertices.count)

        renderEncoder.drawIndexedPrimitives(
          type: .triangle,
          indexCount: indices.count,
          indexType: .uint32,
          indexBuffer: indexBuffer,
          indexBufferOffset: 0
        )
      }
    }

    // Draw fill
    let tintColor = tint ?? .white
    var fillUniforms = ImageUniforms(
      mvp: mvp,
      tint: SIMD4<Float>(tintColor.red, tintColor.green, tintColor.blue, tintColor.alpha)
    )

    let fillVertexData = vertexBuffer.contents().bindMemory(to: Float.self, capacity: vertices.count)
    fillVertexData.initialize(from: vertices, count: vertices.count)

    renderEncoder.setVertexBytes(&mvp, length: MemoryLayout<float4x4>.size, index: 0)
    renderEncoder.setFragmentBytes(&fillUniforms, length: MemoryLayout<ImageUniforms>.size, index: 0)

    // Draw the quad
    renderEncoder.drawIndexedPrimitives(
      type: .triangle,
      indexCount: indices.count,
      indexType: .uint32,
      indexBuffer: indexBuffer,
      indexBufferOffset: 0
    )
  }

  public func drawImageTransformed(
    textureID: UInt64,
    in rect: Rect,
    rotation: Float,
    scale: Point,
    tint: Color?,
    strokeWidth: Float,
    strokeColor: Color?
  ) {
    guard let renderEncoder = currentRenderEncoder,
      let vertexBuffer = imageVertexBuffer,
      let indexBuffer = imageIndexBuffer
    else {
      logger.warning("MTLRenderer.drawImageTransformed: No active render encoder or buffers")
      return
    }

    let x = rect.origin.x
    let y = rect.origin.y
    let w = rect.size.width
    let h = rect.size.height

    // Compute rotated quad around center
    let cx = x + w * 0.5
    let cy = y + h * 0.5
    let hw = (w * scale.x) * 0.5
    let hh = (h * scale.y) * 0.5
    let c = cos(rotation)
    let s = sin(rotation)

    func rot(_ px: Float, _ py: Float) -> (Float, Float) {
      let rx = px * c - py * s
      let ry = px * s + py * c
      return (cx + rx, cy + ry)
    }

    let bl = rot(-hw, -hh)
    let br = rot(hw, -hh)
    let tr = rot(hw, hh)
    let tl = rot(-hw, hh)

    let vertices: [Float] = [
      bl.0, bl.1, 0, 0,
      br.0, br.1, 1, 0,
      tr.0, tr.1, 1, 1,
      tl.0, tl.1, 0, 1,
    ]
    let indices: [UInt32] = [0, 1, 2, 2, 3, 0]

    // Check buffer capacity
    let maxVertices = vertexBuffer.length / MemoryLayout<Float>.size
    let maxIndices = indexBuffer.length / MemoryLayout<UInt32>.size
    guard vertices.count <= maxVertices && indices.count <= maxIndices else { return }

    let vertexData = vertexBuffer.contents().bindMemory(to: Float.self, capacity: vertices.count)
    vertexData.initialize(from: vertices, count: vertices.count)
    let indexData = indexBuffer.contents().bindMemory(to: UInt32.self, capacity: indices.count)
    indexData.initialize(from: indices, count: indices.count)

    renderEncoder.setRenderPipelineState(imagePipelineState)
    renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

    var mvp = createOrthographicMatrix(viewportSize: currentViewportSize)

    // TODO: bind real texture by textureID when texture binding is implemented
    logger.trace("MTLRenderer.drawImageTransformed: textureID=\(textureID), rotation=\(rotation)")

    // Draw stroke outline if specified
    if strokeWidth > 0, let strokeColor = strokeColor {
      // Rotate offset vectors for transformed images
      let offsets: [(Float, Float)] = [
        (-strokeWidth, 0), (strokeWidth, 0),
        (0, -strokeWidth), (0, strokeWidth),
        (-strokeWidth, -strokeWidth), (strokeWidth, strokeWidth),
        (-strokeWidth, strokeWidth), (strokeWidth, -strokeWidth),
      ]

      // Rotate offset vectors
      let c = cos(rotation)
      let s = sin(rotation)
      func rotOffset(_ offsetX: Float, _ offsetY: Float) -> (Float, Float) {
        let rx = offsetX * c - offsetY * s
        let ry = offsetX * s + offsetY * c
        return (rx, ry)
      }

      var strokeUniforms = ImageUniforms(
        mvp: mvp,
        tint: SIMD4<Float>(strokeColor.red, strokeColor.green, strokeColor.blue, strokeColor.alpha)
      )

      renderEncoder.setVertexBytes(&mvp, length: MemoryLayout<float4x4>.size, index: 0)
      renderEncoder.setFragmentBytes(&strokeUniforms, length: MemoryLayout<ImageUniforms>.size, index: 0)

      for (offsetX, offsetY) in offsets {
        let (rotX, rotY) = rotOffset(offsetX, offsetY)
        var offsetVertices = vertices
        for i in stride(from: 0, to: offsetVertices.count, by: 4) {
          offsetVertices[i] += rotX
          offsetVertices[i + 1] += rotY
        }

        let offsetVertexData = vertexBuffer.contents().bindMemory(to: Float.self, capacity: offsetVertices.count)
        offsetVertexData.initialize(from: offsetVertices, count: offsetVertices.count)

        renderEncoder.drawIndexedPrimitives(
          type: .triangle, indexCount: indices.count, indexType: .uint32, indexBuffer: indexBuffer,
          indexBufferOffset: 0)
      }
    }

    // Draw fill
    let tintColor = tint ?? .white
    var fillUniforms = ImageUniforms(
      mvp: mvp,
      tint: SIMD4<Float>(tintColor.red, tintColor.green, tintColor.blue, tintColor.alpha)
    )

    let fillVertexData = vertexBuffer.contents().bindMemory(to: Float.self, capacity: vertices.count)
    fillVertexData.initialize(from: vertices, count: vertices.count)

    renderEncoder.setVertexBytes(&mvp, length: MemoryLayout<float4x4>.size, index: 0)
    renderEncoder.setFragmentBytes(&fillUniforms, length: MemoryLayout<ImageUniforms>.size, index: 0)

    renderEncoder.drawIndexedPrimitives(
      type: .triangle, indexCount: indices.count, indexType: .uint32, indexBuffer: indexBuffer, indexBufferOffset: 0)
  }

  public func setClipRect(_ rect: Rect?) {
    // TODO: Implement Metal scissor rect
    logger.trace("MTLRenderer.setClipRect: \(rect != nil ? "Rect" : "nil")")
  }

  public func setWireframeMode(_ enabled: Bool) {
    // TODO: Implement Metal wireframe mode
    logger.trace("MTLRenderer.setWireframeMode: \(enabled)")
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

  // MARK: - Gradient Drawing

  public func drawLinearGradient(_ gradient: Gradient, in rect: Rect, angle: Float) {
    // TODO: Implement Metal gradient rendering
    // For now, fall back to solid color (first color stop)
    if let firstColor = gradient.colorStops.first?.color {
      var path = BezierPath()
      path.addRect(rect)
      drawPath(path, color: firstColor)
    }
  }

  public func drawLinearGradient(_ gradient: Gradient, in path: BezierPath, angle: Float) {
    // TODO: Implement Metal gradient rendering
    // For now, fall back to solid color (first color stop)
    if let firstColor = gradient.colorStops.first?.color {
      drawPath(path, color: firstColor)
    }
  }

  public func drawRadialGradient(_ gradient: Gradient, in rect: Rect, center: Point) {
    // TODO: Implement Metal gradient rendering
    // For now, fall back to solid color (first color stop)
    if let firstColor = gradient.colorStops.first?.color {
      var path = BezierPath()
      path.addRect(rect)
      drawPath(path, color: firstColor)
    }
  }

  public func drawRadialGradient(_ gradient: Gradient, in path: BezierPath, center: Point) {
    // TODO: Implement Metal gradient rendering
    // For now, fall back to solid color (first color stop)
    if let firstColor = gradient.colorStops.first?.color {
      drawPath(path, color: firstColor)
    }
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
      logger.warning("MTLRenderer.drawTriangles: No active render encoder or buffers")
      return
    }

    // Check buffer capacity
    let maxVertices = vertexBuffer.length / MemoryLayout<Float>.size
    let maxIndices = indexBuffer.length / MemoryLayout<UInt32>.size

    guard vertices.count <= maxVertices && indices.count <= maxIndices else {
      logger.error(
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
    let mvp = createOrthographicMatrix(viewportSize: coordinateSpaceSize)

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
    anchor: AnchorPoint,
    textAlignment: TextAlignment
  ) {
    // TODO: Implement Metal text rendering
    // For now, this is a stub that does nothing
    // In a full implementation, this would:
    // 1. ~~Create a ModularTextRenderer for the default style~~
    // 2. Convert AttributedString to legacy AttributedText
    // 3. Use Metal shaders to render the text
  }

  // MARK: - UI Context

  /// Execute a block with UI rendering state (no depth testing, blending enabled)
  public func withUIContext<T>(_ block: () throws -> T) rethrows -> T {
    // For Metal, we don't need to change state as much as OpenGL
    // Metal handles blending and depth testing through render pipeline state
    // This is a placeholder implementation that just executes the block
    return try block()
  }

  // MARK: - Framebuffer Objects (FBO) - Stub Implementation

  public func createFramebuffer(size: Size, scale: Float) -> UInt64 {
    // TODO: Implement Metal framebuffer objects
    // For now, return a dummy ID
    return 0
  }

  public func destroyFramebuffer(_ framebufferID: UInt64) {
    // TODO: Implement Metal framebuffer cleanup
  }

  public func beginFramebuffer(_ framebufferID: UInt64) {
    // TODO: Implement Metal framebuffer binding
  }

  public func endFramebuffer() {
    // TODO: Implement Metal framebuffer unbinding
  }

  public func getFramebufferTextureID(_ framebufferID: UInt64) -> UInt64? {
    // TODO: Implement Metal framebuffer texture ID retrieval
    return nil
  }

  public func drawFramebuffer(
    _ framebufferID: UInt64,
    in rect: Rect,
    transform: Transform2D?,
    alpha: Float
  ) {
    // TODO: Implement Metal framebuffer drawing
    // For now, this is a no-op
  }

  private static func createGradientPipelineState(device: MTLDevice) throws -> MTLRenderPipelineState {
    // Create library from source code
    let shaderSource = """
      #include <metal_stdlib>
      using namespace metal;

      struct GradientVertex {
          float2 position [[attribute(0)]];
          float2 gradientCoord [[attribute(1)]];
      };

      struct GradientVertexOut {
          float4 position [[position]];
          float2 gradientCoord;
      };

      struct GradientUniforms {
          float4x4 mvp;
          int gradientType; // 0 = linear, 1 = radial
          float2 gradientStart; // For linear: start point, for radial: center point
          float2 gradientEnd; // For linear: end point, for radial: radius vector
          int numColorStops;
          float4 colorStops[16]; // RGBA values
          float colorLocations[16]; // Location values (0.0 to 1.0)
      };

      vertex GradientVertexOut gradientVertex(GradientVertex in [[stage_in]],
                                            constant GradientUniforms& uniforms [[buffer(0)]]) {
          GradientVertexOut out;
          out.position = uniforms.mvp * float4(in.position, 0.0, 1.0);
          out.gradientCoord = in.gradientCoord;
          return out;
      }

      fragment float4 gradientFragment(GradientVertexOut in [[stage_in]],
                                     constant GradientUniforms& uniforms [[buffer(0)]]) {
          float2 uv = in.gradientCoord;
          
          if (uniforms.gradientType == 0) {
              // Linear gradient
              float2 gradientDir = uniforms.gradientEnd - uniforms.gradientStart;
              float gradientLength = length(gradientDir);
              
              if (gradientLength == 0.0) {
                  return uniforms.colorStops[0];
              }
              
              float2 normalizedDir = gradientDir / gradientLength;
              float2 toPoint = uv - uniforms.gradientStart;
              float t = dot(toPoint, normalizedDir) / gradientLength;
              
              // Clamp t to [0, 1]
              t = clamp(t, 0.0, 1.0);
              
              // Find the two color stops that bracket t
              for (int i = 0; i < uniforms.numColorStops - 1; i++) {
                  if (t >= uniforms.colorLocations[i] && t <= uniforms.colorLocations[i + 1]) {
                      float localT = (t - uniforms.colorLocations[i]) / (uniforms.colorLocations[i + 1] - uniforms.colorLocations[i]);
                      return mix(uniforms.colorStops[i], uniforms.colorStops[i + 1], localT);
                  }
              }
              
              // Handle edge cases
              if (t <= uniforms.colorLocations[0]) {
                  return uniforms.colorStops[0];
              } else {
                  return uniforms.colorStops[uniforms.numColorStops - 1];
              }
          } else {
              // Radial gradient
              float2 center = uniforms.gradientStart;
              float2 radiusVec = uniforms.gradientEnd;
              float maxRadius = length(radiusVec);
              
              if (maxRadius == 0.0) {
                  return uniforms.colorStops[0];
              }
              
              float distance = length(uv - center);
              float t = distance / maxRadius;
              
              // Clamp t to [0, 1]
              t = clamp(t, 0.0, 1.0);
              
              // Find the two color stops that bracket t
              for (int i = 0; i < uniforms.numColorStops - 1; i++) {
                  if (t >= uniforms.colorLocations[i] && t <= uniforms.colorLocations[i + 1]) {
                      float localT = (t - uniforms.colorLocations[i]) / (uniforms.colorLocations[i + 1] - uniforms.colorLocations[i]);
                      return mix(uniforms.colorStops[i], uniforms.colorStops[i + 1], localT);
                  }
              }
              
              // Handle edge cases
              if (t <= uniforms.colorLocations[0]) {
                  return uniforms.colorStops[0];
              } else {
                  return uniforms.colorStops[uniforms.numColorStops - 1];
              }
          }
      }
      """

    let library = try device.makeLibrary(source: shaderSource, options: nil)
    let vertexFunction = library.makeFunction(name: "gradientVertex")!
    let fragmentFunction = library.makeFunction(name: "gradientFragment")!

    let pipelineDescriptor = MTLRenderPipelineDescriptor()
    pipelineDescriptor.vertexFunction = vertexFunction
    pipelineDescriptor.fragmentFunction = fragmentFunction
    pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

    return try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
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

struct GradientUniforms {
  var mvp: matrix_float4x4
  var gradientType: Int32
  var gradientStart: SIMD2<Float>
  var gradientEnd: SIMD2<Float>
  var numColorStops: Int32
  var colorStops:
    (
      SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
      SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>
    )
  var colorLocations:
    (Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float)
}

// MARK: - Errors

public enum MTLRendererError: Error {
  case noMetalDevice
  case textureCacheCreationFailed
  case shaderCompilationFailed
}
