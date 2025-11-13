import Foundation
import GLFW
import GL
import Theora
import Ogg
import COgg

/// Fullscreen video player for OGV files
public final class Movie {
  private var decoder: TheoraDecoder?
  private var oggStream: OggStream?
  private var oggSync: OggSync?
  private var currentFrame: Image?
  private var frameTexture: GLuint = 0
  
  private var fileURL: URL?
  private var fileHandle: FileHandle?
  private var isPlaying = false
  private var currentTime: Double = 0
  private var frameTime: Double = 0
  private var lastUpdateTime: Double = 0
  private var videoInfo: TheoraDecoder.VideoInfo?
  private var fps: Double = 30.0
  private var shouldAutoLoop = true
  private var onLoopCallback: (() -> Void)?
  
  /// Initialize with a movie file path (does bundle lookup like Image/Scene)
  public init(_ filename: String) {
    // Only check Bundle.game
    if let url = Bundle.game.url(forResource: filename, withExtension: "ogv") {
      fileURL = url
    }
  }
  
  /// Set callback to be called when movie loops (reaches end)
  public func onLoop(_ callback: @escaping () -> Void) {
    onLoopCallback = callback
  }
  
  /// Enable or disable automatic looping
  public func setAutoLoop(_ enabled: Bool) {
    shouldAutoLoop = enabled
  }
  
  /// Start playback
  public func play() throws {
    guard let url = fileURL else {
      return  // Silently fail if file not found
    }
    
    // Open file
    fileHandle = try FileHandle(forReadingFrom: url)
    
    // Initialize Ogg sync for reading pages
    oggSync = try OggSync()
    
    // Initialize Theora decoder
    decoder = TheoraDecoder()
    
    // Read and parse headers
    var headersParsed = 0
    while headersParsed < 3 {
      // Read a page from file
      guard let page = try readPage() else {
        break  // End of file
      }
      
      // Add page to Ogg stream
      if oggStream == nil {
        oggStream = try OggStream(serialNumber: page.serialNumber)
      }
      _ = try oggStream?.addPage(page)
      
      // Extract packet and parse header
      if let packet = try oggStream?.extractPacket() {
        let moreHeaders = try decoder?.parseHeader(packet: packet) ?? false
        if !moreHeaders {
          headersParsed = 3
        } else {
          headersParsed += 1
        }
      }
    }
    
    // Initialize decoder
    try decoder?.initialize()
    
    // Get video info for FPS calculation
    if let decoder = decoder {
      videoInfo = decoder.getVideoInfo()
      if let info = videoInfo, info.fpsDenominator > 0 {
        fps = Double(info.fpsNumerator) / Double(info.fpsDenominator)
      }
      frameTime = 1.0 / fps
    }
    
    isPlaying = true
    lastUpdateTime = GLFWSession.currentTime
  }
  
  /// Update playback (call each frame)
  public func update(deltaTime: Double) {
    guard isPlaying, let decoder = decoder, let oggStream = oggStream else { return }
    
    let currentTime = GLFWSession.currentTime
    let elapsed = currentTime - lastUpdateTime
    
    // Decode frames based on video FPS
    if elapsed >= frameTime {
      // Try to extract a packet from the stream
      var decodedFrame = false
      
      // First, try to get a packet from the stream
      if let packet = try? oggStream.extractPacket() {
        _ = try? decoder.decodePacket(packet)
        if let frame = try? decoder.getFrame() {
          updateFrameTexture(frame: frame)
          decodedFrame = true
        }
      }
      
      // If no packet available, read more pages from file
      while !decodedFrame {
        // Keep reading pages until we get one or hit EOF
        guard let page = try? readPage() else {
          // End of file
          if shouldAutoLoop {
            stop()
            try? play()
          } else {
            stop()
            onLoopCallback?()
          }
          return
        }
        
        _ = try? oggStream.addPage(page)
        
        // Try to extract packet after adding page
        if let packet = try? oggStream.extractPacket() {
          _ = try? decoder.decodePacket(packet)
          if let frame = try? decoder.getFrame() {
            updateFrameTexture(frame: frame)
            decodedFrame = true
          }
        }
        // If still no packet, continue reading pages
      }
      
      lastUpdateTime = currentTime
    }
  }
  
  /// Draw fullscreen (call in UI context)
  public func draw() {
    guard isPlaying, let frame = currentFrame else { return }
    let screenSize = Engine.viewportSize
    frame.draw(in: Rect(x: 0, y: 0, width: screenSize.width, height: screenSize.height))
  }
  
  /// Stop playback
  public func stop() {
    isPlaying = false
    decoder = nil
    oggStream = nil
    oggSync = nil
    fileHandle?.closeFile()
    fileHandle = nil
    currentFrame = nil
    
    if frameTexture != 0 {
      glDeleteTextures(1, &frameTexture)
      frameTexture = 0
    }
  }
  
  // MARK: - Private Helpers
  
  private func readPage() throws -> OggPage? {
    guard let sync = oggSync, let handle = fileHandle else { return nil }
    
    // Keep reading until we get a complete page or hit EOF
    while true {
      // Try to extract a page from already buffered data first
      if let page = try? sync.extractPage() {
        return page
      }
      
      // No page available, read more data
      let chunkSize = 4096
      let data = handle.readData(ofLength: chunkSize)
      
      guard !data.isEmpty else { return nil }  // EOF
      
      // Add data to sync
      let buffer = try sync.getBuffer(size: data.count)
      guard let bufferPtr = buffer else { return nil }
      _ = data.withUnsafeBytes { dataBytes in
        memcpy(bufferPtr, dataBytes.baseAddress!, data.count)
      }
      try sync.wrote(bytesWritten: data.count)
      
      // Try to extract a page after adding data
      if let page = try? sync.extractPage() {
        return page
      }
      
      // No page yet, continue reading
    }
  }
  
  private func updateFrameTexture(frame: TheoraDecoder.YCbCrFrame) {
    // Convert Y'CbCr to RGB
    let width = frame.yWidth
    let height = frame.yHeight
    
    var rgbPixels = [UInt8](repeating: 0, count: width * height * 4)
    
    // Simple Y'CbCr to RGB conversion (ITU-R BT.601)
    for y in 0..<height {
      for x in 0..<width {
        let yIdx = y * frame.yStride + x
        let cbIdx = (y / 2) * frame.cbStride + (x / 2)
        let crIdx = (y / 2) * frame.crStride + (x / 2)
        
        let Y = Int(frame.y[yIdx])
        let Cb = Int(frame.cb[cbIdx]) - 128
        let Cr = Int(frame.cr[crIdx]) - 128
        
        // Convert to RGB
        let R = max(0, min(255, Y + Int(1.402 * Double(Cr))))
        let G = max(0, min(255, Y - Int(0.344 * Double(Cb)) - Int(0.714 * Double(Cr))))
        let B = max(0, min(255, Y + Int(1.772 * Double(Cb))))
        
        let rgbIdx = (y * width + x) * 4
        rgbPixels[rgbIdx] = UInt8(R)
        rgbPixels[rgbIdx + 1] = UInt8(G)
        rgbPixels[rgbIdx + 2] = UInt8(B)
        rgbPixels[rgbIdx + 3] = 255
      }
    }
    
    // Upload to texture
    if frameTexture == 0 {
      glGenTextures(1, &frameTexture)
      glBindTexture(GL_TEXTURE_2D, frameTexture)
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)
    }
    
    glBindTexture(GL_TEXTURE_2D, frameTexture)
    rgbPixels.withUnsafeBytes { bytes in
      glTexImage2D(
        GL_TEXTURE_2D, 0, GL_RGBA,
        GLsizei(width), GLsizei(height),
        0, GL_RGBA, GL_UNSIGNED_BYTE, bytes.baseAddress
      )
    }
    
    // Create Image from texture
    currentFrame = Image(textureID: UInt64(frameTexture), naturalSize: Size(Float(width), Float(height)))
  }
  
  deinit {
    stop()
  }
}

