import Assimp
import Foundation

/// Manages camera syncing, triggers, and script overrides
@MainActor
public final class CameraSystem {
  // MARK: - State

  private var camera: Assimp.Camera?
  private var cameraNode: Node?
  private(set) var cameraWorldTransform: mat4 = mat4(1)

  // Debug camera override mode - when enabled, camera triggers are ignored
  private(set) var isDebugCameraOverrideMode: Bool = false

  private struct CameraStateSnapshot {
    let cameraNodeName: String?
    let prerenderedCameraName: String?
    let selectedCamera: String
  }

  // Script-driven camera overrides (used when scene scripts request closeups)
  private var scriptCameraOverrideStack: [CameraStateSnapshot] = []

  private var isCameraOverrideActive: Bool {
    return isDebugCameraOverrideMode || !scriptCameraOverrideStack.isEmpty
  }

  // MARK: - References

  private weak var scene: Scene?
  private weak var prerenderedEnvironment: PrerenderedEnvironment?

  // MARK: - Public Properties

  /// Currently selected camera name (for prerendered environment)
  public var selectedCamera: String = "1" {
    didSet {
      if selectedCamera != oldValue {
        try? prerenderedEnvironment?.switchToCamera(selectedCamera)
      }
    }
  }

  // MARK: - Initialization

  public init() {}

  // MARK: - Setup

  public func setScene(_ scene: Scene?) {
    self.scene = scene
  }

  func setPrerenderedEnvironment(_ environment: PrerenderedEnvironment?) {
    self.prerenderedEnvironment = environment
  }

  // MARK: - Camera Syncing

  /// Syncs `camera`, its node/world transform and prerender near/far from the given camera name
  func syncActiveCamera(name: String) {
    guard let scene = self.scene else { return }
    let nodeName = name
    if let node = scene.rootNode.findNode(named: nodeName) {
      cameraNode = node
      cameraWorldTransform = node.assimpNode.calculateWorldTransform(scene: scene.assimpScene)
      logger.trace("✅ Active camera node: \(nodeName)")
      // Debug: Print camera transform
      let cameraPos = vec3(cameraWorldTransform[3].x, cameraWorldTransform[3].y, cameraWorldTransform[3].z)
      logger.trace("📷 Camera world transform position: \(cameraPos)")
    } else {
      logger.warning("⚠️ Camera node not found: \(nodeName)")
      cameraNode = nil
      cameraWorldTransform = mat4(1)
    }

    if let cam = scene.cameras.first(where: { $0.name == nodeName }) {
      camera = cam
      // Sync projection and mist params
      prerenderedEnvironment?.near = cam.clipPlaneNear
      prerenderedEnvironment?.far = cam.clipPlaneFar
      // If Blender mist settings are known, keep defaults (0.1 / 25.0) or adjust here
      logger.trace(
        "✅ Active camera params near=\(cam.clipPlaneNear) far=\(cam.clipPlaneFar) fov=\(cam.horizontalFOV) aspect=\(cam.aspect)"
      )
    } else {
      logger.warning("⚠️ Camera struct not found for name: \(nodeName)")
      camera = nil
    }
  }

  /// Get the current camera (for rendering)
  func getCamera() -> Assimp.Camera? {
    return camera
  }

  // MARK: - Camera Triggers

  /// Handle camera trigger activation
  func handleCameraTrigger(
    cameraName: String,
    sceneScript: Script?,
    normalizedAreaIdentifier: (String) -> String
  ) {
    // Ignore camera triggers when a manual or scripted override is active
    if isCameraOverrideActive {
      let reason = isDebugCameraOverrideMode ? "debug camera override mode" : "script camera override"
      logger.trace("📷 Camera trigger '\(cameraName)' ignored: \(reason) is active")
      return
    }

    // Extract area from camera name
    // Examples: "hallway_1" -> "hallway", "Entry_1" -> "Entry_1"
    let triggerArea: String
    if cameraName.hasPrefix("Entry_") {
      // Entry areas keep the full name (e.g., "Entry_1")
      triggerArea = cameraName
    } else {
      // Named areas: remove trailing "_1", "_2", etc. (e.g., "hallway_1" -> "hallway")
      if let lastUnderscoreIndex = cameraName.lastIndex(of: "_") {
        let beforeUnderscore = String(cameraName[..<lastUnderscoreIndex])
        // Check if after underscore is just a number
        let afterUnderscore = String(cameraName[cameraName.index(after: lastUnderscoreIndex)...])
        if afterUnderscore.allSatisfy({ $0.isNumber }) {
          triggerArea = beforeUnderscore
        } else {
          // Not a numbered camera, use full name
          triggerArea = cameraName
        }
      } else {
        // No underscore, use full name
        triggerArea = cameraName
      }
    }

    // Check if player is in the correct area
    let currentArea = sceneScript?.currentArea
    let currentAreaDescription = currentArea ?? "unknown"
    let normalizedCurrentArea = currentArea.map(normalizedAreaIdentifier)
    let normalizedTriggerArea = normalizedAreaIdentifier(triggerArea)

    if let normalizedCurrentArea, normalizedCurrentArea != normalizedTriggerArea {
      logger.trace(
        "📷 Camera trigger '\(cameraName)' ignored: player is in area '\(currentAreaDescription)', trigger requires '\(triggerArea)'"
      )
      return
    }

    // Switch 3D camera (e.g., "hallway_1" -> "Camera_hallway_1")
    let cameraNodeName = "Camera_\(cameraName)"
    syncActiveCamera(name: cameraNodeName)

    // Switch prerendered environment camera (e.g., "hallway_1" -> "hallway_1")
    try? prerenderedEnvironment?.switchToCamera(cameraName)
    selectedCamera = prerenderedEnvironment?.getCurrentCameraName() ?? cameraName

    logger.trace("📷 Camera trigger activated: switched to camera '\(cameraName)' (area: '\(triggerArea)')")
  }

  // MARK: - Script Camera Overrides

  public func withScriptCameraOverride<T>(
    on cameraName: String,
    perform: () async throws -> T
  ) async rethrows -> T {
    pushScriptCameraOverride(on: cameraName)
    defer { popScriptCameraOverride() }
    return try await perform()
  }

  public func withScriptCameraOverride<T>(
    on cameraName: String,
    perform: () throws -> T
  ) rethrows -> T {
    pushScriptCameraOverride(on: cameraName)
    defer { popScriptCameraOverride() }
    return try perform()
  }

  private func pushScriptCameraOverride(on cameraName: String) {
    let state = CameraStateSnapshot(
      cameraNodeName: cameraNode?.name,
      prerenderedCameraName: prerenderedEnvironment?.getCurrentCameraName(),
      selectedCamera: selectedCamera
    )
    scriptCameraOverrideStack.append(state)
    applyScriptCameraOverride(cameraName: cameraName)
  }

  private func popScriptCameraOverride() {
    guard let previousState = scriptCameraOverrideStack.popLast() else { return }

    if let previousNodeName = previousState.cameraNodeName {
      syncActiveCamera(name: previousNodeName)
    }

    if let previousPrerenderedCamera = previousState.prerenderedCameraName {
      try? prerenderedEnvironment?.switchToCamera(previousPrerenderedCamera)
      selectedCamera = prerenderedEnvironment?.getCurrentCameraName() ?? previousPrerenderedCamera
    } else {
      selectedCamera = previousState.selectedCamera
    }
  }

  private func applyScriptCameraOverride(cameraName rawName: String) {
    guard let (nodeName, environmentName) = resolveCameraNames(from: rawName) else {
      logger.warning("⚠️ Script camera override ignored: invalid camera name '\(rawName)'")
      return
    }

    syncActiveCamera(name: nodeName)

    try? prerenderedEnvironment?.switchToCamera(environmentName)
    selectedCamera = prerenderedEnvironment?.getCurrentCameraName() ?? environmentName

    logger.trace("🎬 Script camera override active: node='\(nodeName)', prerendered='\(environmentName)'")
  }

  private func resolveCameraNames(from rawName: String) -> (nodeName: String, environmentName: String)? {
    let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    var normalized = trimmed
    if normalized.hasPrefix("CameraTrigger_") {
      normalized = String(normalized.dropFirst("CameraTrigger_".count))
    }

    if normalized.hasPrefix("Camera_") {
      let suffix = String(normalized.dropFirst("Camera_".count))
      guard !suffix.isEmpty else { return nil }
      return (normalized, suffix)
    }

    return ("Camera_\(normalized)", normalized)
  }

  // MARK: - Debug Camera Override

  public func setDebugCameraOverrideMode(_ enabled: Bool) {
    isDebugCameraOverrideMode = enabled
  }

  public func cycleToNextCamera() {
    prerenderedEnvironment?.cycleToNextCamera()
    selectedCamera = prerenderedEnvironment?.getCurrentCameraName() ?? selectedCamera
    // Sync to corresponding Assimp camera (e.g., "1" -> "Camera_1", "stove.001" -> "Camera_stove.001")
    syncActiveCamera(name: "Camera_\(selectedCamera)")
  }

  public func cycleToPreviousCamera() {
    prerenderedEnvironment?.cycleToPreviousCamera()
    selectedCamera = prerenderedEnvironment?.getCurrentCameraName() ?? selectedCamera
    // Sync to corresponding Assimp camera (e.g., "1" -> "Camera_1", "stove.001" -> "Camera_stove.001")
    syncActiveCamera(name: "Camera_\(selectedCamera)")
  }

  public func switchToDebugCamera() {
    prerenderedEnvironment?.switchToDebugCamera()
    selectedCamera = prerenderedEnvironment?.getCurrentCameraName() ?? selectedCamera
    // Sync to corresponding Assimp camera (e.g., "1" -> "Camera_1", "stove.001" -> "Camera_stove.001")
    syncActiveCamera(name: "Camera_\(selectedCamera)")
  }
}
