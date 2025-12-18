import Foundation

/// Manages camera syncing, triggers, and script overrides
@MainActor
public final class CameraSystem {
  // MARK: - State

  public private(set) var camera: Camera?
  public private(set) var cameraNode: Node?
  public private(set) var cameraWorldTransform: mat4 = mat4(1)

  // Debug camera override mode - when enabled, camera triggers are ignored
  private(set) var isDebugCameraOverrideMode: Bool = false

  private struct CameraStateSnapshot {
    let cameraNodeName: String?
    let prerenderedCameraName: String?
    let selectedCamera: String
  }

  // Script-driven camera overrides (used when scene scripts request closeups)
  private var scriptCameraOverrideStack: [CameraStateSnapshot] = []

  /// Whether a script-driven closeup is currently active (blocks player movement/inventory)
  public var isInCloseup: Bool {
    return !scriptCameraOverrideStack.isEmpty
  }

  private var isCameraOverrideActive: Bool {
    return isDebugCameraOverrideMode || isInCloseup
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

  /// Extract a Float value from node metadata
  private func extractFloatFromMetadata(_ node: Node, key: String) -> Float? {
    guard let metadata = node.metadata,
      let entry = metadata.metadata[key]
    else {
      return nil
    }
    switch entry {
    case .float(let value):
      return value
    case .int(let value):
      return Float(value)
    case .bool, .string, .vec3:
      return nil
    }
  }

  /// Print all metadata for a camera node (for debugging)
  /// Note: Node doesn't have metadata - this is a placeholder for future implementation
  private func printCameraNodeMetadata(_ node: Node) {
    // TODO: Add metadata support to Node if needed
    if let metadata = node.metadata {
      logger.trace("📋 Camera node '\(node.name)' has \(metadata.numberOfProperties) metadata properties")
    } else {
      logger.trace("📋 Camera node '\(node.name)' (metadata not yet supported for Node)")
    }
  }

  /// Syncs `camera`, its node/world transform and prerender near/far from the given camera name.
  func syncActiveCamera(name nodeName: String) {
    guard let scene else { return }

    // Extract base name to find camera node
    let baseName = Scene.extractBaseName(from: nodeName)

    // Find camera node by base name
    if let node = scene.cameraNode(named: baseName) {
      cameraNode = node
      cameraWorldTransform = node.calculateWorldTransform()
      logger.trace("✅ Active camera node: \(node.name)")
      // Debug: Print camera transform
      let cameraPos = vec3(cameraWorldTransform[3].x, cameraWorldTransform[3].y, cameraWorldTransform[3].z)
      logger.trace("📷 Camera world transform position: \(cameraPos)")
      // Print all metadata for debugging
      printCameraNodeMetadata(node)
    } else {
      logger.warning("⚠️ Camera node not found: \(nodeName)")
      cameraNode = nil
      cameraWorldTransform = mat4(1)
    }

    // Find camera struct by base name using scene.camera(named:)
    if let cam = scene.camera(named: baseName) {
      camera = cam
      // Sync projection and mist params

      // Check for mist_start custom property from camera node metadata
      let nearValue: Float
      if let cameraNode, let mistStart = extractFloatFromMetadata(cameraNode, key: "mist_start") {
        nearValue = mistStart
        logger.trace("🌫️ Using mist_start from camera node metadata: \(mistStart)")
      } else {
        nearValue = cam.clipPlaneNear
      }
      prerenderedEnvironment?.near = nearValue

      // Check for mist_depth custom property from camera node metadata
      let farValue: Float
      if let cameraNode, let mistDepth = extractFloatFromMetadata(cameraNode, key: "mist_depth") {
        farValue = mistDepth
        logger.trace("🌫️ Using mist_depth from camera node metadata: \(mistDepth)")
      } else {
        farValue = cam.clipPlaneFar
      }
      prerenderedEnvironment?.far = farValue

      // If Blender mist settings are known, keep defaults (0.1 / 25.0) or adjust here
      logger.trace(
        "✅ Active camera params near=\(nearValue) far=\(farValue) fov=\(cam.horizontalFOV) aspect=\(cam.aspect)"
      )
    } else {
      logger.warning("⚠️ Camera struct not found for name: \(nodeName) (baseName: \(baseName))")
      camera = nil
    }
  }

  // MARK: - Camera Triggers

  /// Handle camera trigger activation
  func handleCameraTrigger(
    cameraName: String,
    currentAreaName: String?
  ) {
    // Ignore camera triggers when a manual or scripted override is active
    if isCameraOverrideActive {
      let reason = isDebugCameraOverrideMode ? "debug camera override mode" : "script camera override"
      logger.trace("📷 Camera trigger '\(cameraName)' ignored: \(reason) is active")
      return
    }

    guard let scene = self.scene else { return }

    // Extract area from camera name using Scene's extractBaseName
    // Examples: "@CameraTrigger hallway_1" -> "hallway_1" -> "hallway", "@CameraTrigger Entry 1" -> "Entry 1"
    let baseName = Scene.extractBaseName(from: cameraName)
    let triggerArea: String
    if baseName.hasPrefix("Entry ") {
      // Entry areas keep the full name (e.g., "Entry 1")
      triggerArea = baseName
    } else {
      // Named areas: remove trailing "_1", "_2", etc. (e.g., "hallway_1" -> "hallway")
      if let lastUnderscoreIndex = baseName.lastIndex(of: "_") {
        let beforeUnderscore = String(baseName[..<lastUnderscoreIndex])
        // Check if after underscore is just a number
        let afterUnderscore = String(baseName[baseName.index(after: lastUnderscoreIndex)...])
        if afterUnderscore.allSatisfy({ $0.isNumber }) {
          triggerArea = beforeUnderscore
        } else {
          // Not a numbered camera, use full name
          triggerArea = baseName
        }
      } else {
        // No underscore, use full name
        triggerArea = baseName
      }
    }

    // Check if player is in the correct area
    let currentArea = currentAreaName
    let currentAreaDescription = currentArea ?? "unknown"
    let normalizedCurrentArea = currentArea.map(Scene.normalizedAreaIdentifier)
    let normalizedTriggerArea = Scene.normalizedAreaIdentifier(triggerArea)
    let triggerHasNamedArea = normalizedTriggerArea.rangeOfCharacter(from: .letters) != nil

    if triggerHasNamedArea,
      let normalizedCurrentArea,
      normalizedCurrentArea != normalizedTriggerArea
    {
      logger.trace(
        "📷 Camera trigger '\(cameraName)' ignored: player is in area '\(currentAreaDescription)', trigger requires '\(triggerArea)'"
      )
      return
    }

    // Switch 3D camera using scene.cameraTriggerNode(named:) or scene.cameraNode(named:)
    if let cameraTriggerNode = scene.cameraTriggerNode(named: baseName) {
      syncActiveCamera(name: cameraTriggerNode.name)
    } else if let cameraNode = scene.cameraNode(named: baseName) {
      syncActiveCamera(name: cameraNode.name)
    } else {
      // Fallback: construct name (shouldn't happen with proper @Camera format)
      let cameraNodeName = "@Camera \(baseName)"
      syncActiveCamera(name: cameraNodeName)
    }

    // Switch prerendered environment camera (e.g., "hallway_1" -> "hallway_1")
    try? prerenderedEnvironment?.switchToCamera(baseName)
    selectedCamera = prerenderedEnvironment?.getCurrentCameraName() ?? baseName

    // Update MainLoop area tracking: only named triggers define areas
    if let mainLoop = MainLoop.shared {
      if triggerHasNamedArea {
        mainLoop.currentAreaName = normalizedTriggerArea
      } else {
        mainLoop.currentAreaName = nil
      }
      mainLoop.markCameraTriggerSynced()
    }

    logger.trace("📷 Camera trigger activated: switched to camera '\(cameraName)' (area: '\(triggerArea)')")
  }

  // MARK: - Script Camera Overrides

  public func withScriptedCameraOverride<T>(
    on cameraName: String,
    perform: () async throws -> T
  ) async rethrows -> T {
    pushScriptCameraOverride(on: cameraName)
    defer { popScriptCameraOverride() }
    return try await perform()
  }

  public func withScriptedCameraOverride<T>(
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
    guard let scene = self.scene else { return nil }

    let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    // Extract base name using Scene's extractBaseName (handles @Camera and @CameraTrigger formats)
    let baseName = Scene.extractBaseName(from: trimmed)

    // Try to find camera node by base name
    if let cameraNode = scene.cameraNode(named: baseName) {
      return (cameraNode.name, baseName)
    }

    // Fallback: construct name (shouldn't happen with proper @Camera format)
    return ("@Camera \(baseName)", baseName)
  }

  // MARK: - Debug Camera Override

  public func setDebugCameraOverrideMode(_ enabled: Bool) {
    isDebugCameraOverrideMode = enabled
  }

  public func cycleToNextCamera() {
    prerenderedEnvironment?.cycleToNextCamera()
    selectedCamera = prerenderedEnvironment?.getCurrentCameraName() ?? selectedCamera
    // Sync to corresponding camera object using scene.cameraNode(named:)
    if let scene = self.scene, let cameraNode = scene.cameraNode(named: selectedCamera) {
      syncActiveCamera(name: cameraNode.name)
    } else {
      // Fallback: construct name (shouldn't happen with proper @Camera format)
      syncActiveCamera(name: "@Camera \(selectedCamera)")
    }
  }

  public func cycleToPreviousCamera() {
    prerenderedEnvironment?.cycleToPreviousCamera()
    selectedCamera = prerenderedEnvironment?.getCurrentCameraName() ?? selectedCamera
    // Sync to corresponding camera object using scene.cameraNode(named:)
    if let scene = self.scene, let cameraNode = scene.cameraNode(named: selectedCamera) {
      syncActiveCamera(name: cameraNode.name)
    } else {
      // Fallback: construct name (shouldn't happen with proper @Camera format)
      syncActiveCamera(name: "@Camera \(selectedCamera)")
    }
  }

  public func switchToDebugCamera() {
    prerenderedEnvironment?.switchToDebugCamera()
    selectedCamera = prerenderedEnvironment?.getCurrentCameraName() ?? selectedCamera
    // Sync to corresponding camera object using scene.cameraNode(named:)
    if let scene = self.scene, let cameraNode = scene.cameraNode(named: selectedCamera) {
      syncActiveCamera(name: cameraNode.name)
    } else {
      // Fallback: construct name (shouldn't happen with proper @Camera format)
      syncActiveCamera(name: "@Camera \(selectedCamera)")
    }
  }
}
