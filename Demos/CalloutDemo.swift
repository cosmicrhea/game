import Foundation
import GLFW

final class CalloutDemo: RenderLoop {

  private let calloutRenderer = CalloutRenderer()
  private var isVisible: Bool = true
  private var animationTimer: Float = 0.0

  private var iconEntries: [(name: String, image: ImageRenderer)] = []
  private let leftMargin: Float = 0
  private let topMargin: Float = 180
  private let verticalGap: Float = 16

  @MainActor func onAttach(window: GLFWWindow) {
    // Discover all PNG icons in the bundled resources under UI/Icons
    let fm = FileManager.default
    if let baseURL = Bundle.module.resourceURL?.appendingPathComponent("UI/Icons", isDirectory: true),
      let contents = try? fm.contentsOfDirectory(at: baseURL, includingPropertiesForKeys: nil)
    {
      let pngs = contents.filter { $0.pathExtension.lowercased() == "png" }
      let names = pngs.map { $0.lastPathComponent }.sorted()
      iconEntries = names.map { filename in
        let nameWithoutExt = filename.replacingOccurrences(of: ".png", with: "")
        return (name: nameWithoutExt, image: ImageRenderer("UI/Icons/\(filename)"))
      }
    }
  }

  @MainActor func update(deltaTime: Float) {
    // Update the callout renderer animation
    calloutRenderer.update(deltaTime: deltaTime)
    
    // Auto-toggle visibility every 3 seconds for demo
    animationTimer += deltaTime
    if animationTimer >= 3.0 {
      isVisible.toggle()
      animationTimer = 0.0
    }
  }

  @MainActor func draw() {
    let windowSize = (Int32(WIDTH), Int32(HEIGHT))
    var currentTop = Float(HEIGHT) - topMargin

    for entry in iconEntries {
      // Draw one callout per icon with its filename as the label
      calloutRenderer.draw(
        windowSize: windowSize,
        size: (520, 44),
        position: (leftMargin, currentTop),
        anchor: .topLeft,
        fade: .right,
        icon: entry.image,
        iconName: entry.name,
        label: "Make your way to Kastellet (\(entry.name))",
        visible: isVisible
      )

      currentTop -= (44 + verticalGap)  // Use fixed height since we know it's 44
      if currentTop < 44 { break }  // Stop if we run off-screen
    }
  }
}
