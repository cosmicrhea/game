import Foundation

/// Tracks loading progress for async scene and texture loading
@MainActor
final class LoadingProgress {
  /// List of progress messages to display
  var progressMessages: [String] = []

  /// Whether loading is currently in progress
  var isLoading: Bool = true

  /// Current scene progress (0-1)
  private var sceneProgress: Float = 0.0

  /// Current texture being loaded
  private var currentTexture: Int = 0
  private var totalTextures: Int = 0

  /// Update scene loading progress
  func updateSceneProgress(_ progress: Float) {
    sceneProgress = progress
    updateProgressMessages()
  }

  /// Update texture loading progress
  func updateTextureProgress(current: Int, total: Int, progress: Float) {
    currentTexture = current
    totalTextures = total

    // Add new texture message if this is a new texture
    if current == 1 || (current > 1 && progressMessages.count < current) {
      let message = "Loading texture \(current)/\(total): \(Int(progress * 100))%"
      progressMessages.append(message)
    } else {
      // Update the last message for the current texture
      if !progressMessages.isEmpty {
        let message = "Loading texture \(current)/\(total): \(Int(progress * 100))%"
        progressMessages[progressMessages.count - 1] = message
      }
    }
  }

  /// Update progress messages based on current state
  private func updateProgressMessages() {
    // Update or add scene progress message
    let sceneMessage = "Loading scene: \(Int(sceneProgress * 100))%"
    if progressMessages.isEmpty || !progressMessages[0].hasPrefix("Loading scene:") {
      progressMessages.insert(sceneMessage, at: 0)
    } else {
      progressMessages[0] = sceneMessage
    }
  }

  /// Mark loading as completed
  func markCompleted() {
    isLoading = false
    progressMessages.append("Loading complete")
  }

  /// Reset loading state
  func reset() {
    progressMessages = []
    sceneProgress = 0.0
    currentTexture = 0
    totalTextures = 0
    isLoading = true
  }
}
