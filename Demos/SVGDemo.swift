import Foundation
import GLFW
import GLMath

/// Demo showcasing SVG loading and rendering capabilities
@MainActor
public struct SVGDemo: RenderLoop {
  private var svgImages: [String: Image] = [:]
  private var imageNames: [String] = []

  public init() {
    loadAllTestIcons()
  }

  /// Load all SVG icons from the test directory
  private mutating func loadAllTestIcons() {
    guard let bundleURL = Bundle.module.url(forResource: "UI/Icons/test", withExtension: nil) else {
      logger.error("SVGDemo: Could not find test icons directory")
      return
    }

    let fileManager = FileManager.default
    do {
      let contents = try fileManager.contentsOfDirectory(at: bundleURL, includingPropertiesForKeys: nil)
      let svgFiles = contents.filter { $0.pathExtension.lowercased() == "svg" }

      for svgURL in svgFiles {
        let relativePath = "UI/Icons/test/\(svgURL.lastPathComponent)"
        if Image.validateSVG(svgPath: relativePath) {
          let image = Image(svgPath: relativePath, pixelScale: 1.0, targetSize: Size(64, 64))
          svgImages[relativePath] = image
          imageNames.append(relativePath)
        }
      }

      logger.info("SVGDemo: Loaded \(imageNames.count) SVG icons from test directory")
    } catch {
      logger.error("SVGDemo: Failed to read test icons directory: \(error)")
    }
  }

  /// Update the demo state
  public mutating func update(deltaTime: Float) {
    // No cycling needed - we'll show all icons in a grid
  }

  /// Render the current SVG demo
  public func draw() {
    guard !imageNames.isEmpty else { return }

    // Multi-size grid layout for test icons
    let screenWidth: Float = 1200.0
    let padding: Float = 16.0
    let sizes: [Float] = [24, 32, 48, 72]

    // Calculate grid layout
    let maxIconsPerRow = Int((screenWidth - padding) / (Float(sizes.max()!) + padding))
    let iconsPerSize = min(imageNames.count, maxIconsPerRow)

    for (sizeIndex, size) in sizes.enumerated() {
      let startY =
        Float(sizeIndex) * (Float(iconsPerSize) * (size + padding) / Float(maxIconsPerRow) + padding * 2) + padding

      for (index, imageName) in imageNames.prefix(iconsPerSize).enumerated() {
        guard let image = svgImages[imageName] else { continue }

        let col = index % maxIconsPerRow
        let x = Float(col) * (size + padding) + padding
        let y = startY

        // Draw the image at the calculated position with white tint
        let rect = Rect(origin: Point(x, y), size: Size(size, size))
        image.draw(in: rect, tint: .white)
      }
    }
  }

  /// Draw information about the current image
  private func drawImageInfo(currentImageName: String, image: Image) {
    // This would typically use a text rendering system
    // For now, just log the information
    logger.debug(
      "SVGDemo: Displaying \(currentImageName) (\(Int(image.naturalSize.width))x\(Int(image.naturalSize.height)))")
  }

  /// Test SVG loading with different methods
  public static func testSVGLoading() {
    logger.info("SVGDemo: Testing SVG loading methods")

    // Test standard SVG loading
    if let testSVGPath = findTestSVG() {
      logger.info("SVGDemo: Testing standard SVG loading")
      let standardImage = Image(svgPath: testSVGPath, pixelScale: 1.0)
      logger.info("SVGDemo: Standard loading result: \(standardImage.naturalSize)")

      // Test tessellation loading
      logger.info("SVGDemo: Testing tessellation SVG loading")
      let tessellatedImage = Image(svgPath: testSVGPath, pixelScale: 1.0, targetSize: Size(64, 64))
      logger.info("SVGDemo: Tessellation loading result: \(tessellatedImage.naturalSize)")

      // Test validation
      let isValid = Image.validateSVG(svgPath: testSVGPath)
      logger.info("SVGDemo: SVG validation result: \(isValid)")
    } else {
      logger.warning("SVGDemo: No test SVG found")
    }
  }

  /// Find a test SVG file to use for testing
  private static func findTestSVG() -> String? {
    let testPaths = [
      "UI/Icons/callouts/chevron.svg",
      "UI/Icons/callouts/info.svg",
      "UI/Icons/callouts/location.svg",
      "UI/Icons/carets/caret-down.svg",
      "UI/Icons/debug/camera.svg",
    ]

    for path in testPaths {
      if Image.validateSVG(svgPath: path) {
        return path
      }
    }

    return nil
  }
}
