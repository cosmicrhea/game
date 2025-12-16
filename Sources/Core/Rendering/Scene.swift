import Assimp
import GLTF

/// Import hint types for scene nodes.
public enum ImportHint: String, CaseIterable {
  case action
  case area
  case camera
  case cameraTrigger
  case collision
  case door
  case entry
  case enemy
  case floor
  case footsteps
  case foreground
  case ledge
  case ledgeHigh
  case ledgeLow
  case mapMarker
  case pickup
  case sparkle
  case trigger
  case waypoint

  /// Returns the PascalCase name with @ prefix (e.g., "@CameraTrigger").
  var prefix: String {
    "@\(rawValue.prefix(1).uppercased())\(rawValue.dropFirst())"
  }
}

/// Our own Scene type - independent of Assimp or GLTF
/// This represents the loaded scene data with all game logic
public final class Scene {
  public let filePath: String
  public let meshes: [Mesh]
  public let materials: [Material]
  public let animations: [Animation]
  public let rootNode: Node

  // Embedded textures (for GLB files)
  public let embeddedTextures: [EmbeddedTexture]

  // Optional: Store Assimp scene for backward compatibility (only if created from Assimp)
  internal var _assimpScene: Assimp.Scene?

  // Optional: Store GLTF document to keep buffer data alive during initialization
  // This prevents buffer data from being freed by cgltf_free() while we're still reading it
  internal var _gltfDocument: GLTFDocument?

  // Mapping from camera node base name to Camera object (for GLTF scenes)
  // In GLTF, camera objects can have different names than their nodes, so we need this mapping
  internal var _cameraNodeToCamera: [String: Camera] = [:]

  // Backward compatibility: Access Assimp scene if available
  public var assimpScene: Assimp.Scene? {
    return _assimpScene
  }

  // Our own cameras (from GLTF or Assimp)
  public let cameras: [Camera]

  // Backward compatibility: Access Assimp lights if available
  public var lights: [Assimp.Light] {
    return _assimpScene?.lights ?? []
  }

  // Game-specific: Hint-based node collections
  public private(set) var actionNodes: [Node] = []
  public private(set) var areaNodes: [Node] = []
  public private(set) var cameraNodes: [Node] = []
  public private(set) var cameraTriggerNodes: [Node] = []
  public private(set) var collisionNodes: [Node] = []
  public private(set) var doorNodes: [Node] = []
  public private(set) var entryNodes: [Node] = []
  public private(set) var enemyNodes: [Node] = []
  public private(set) var floorNodes: [Node] = []
  public private(set) var footstepsNodes: [Node] = []
  public private(set) var foregroundNodes: [Node] = []
  public private(set) var ledgeNodes: [Node] = []
  public private(set) var mapMarkerNodes: [Node] = []
  public private(set) var pickupNodes: [Node] = []
  public private(set) var sparkleNodes: [Node] = []
  public private(set) var triggerNodes: [Node] = []
  public private(set) var waypointNodes: [Node] = []

  public init(
    filePath: String,
    rootNode: Node,
    meshes: [Mesh],
    materials: [Material],
    cameras: [Camera] = [],
    animations: [Animation] = [],
    embeddedTextures: [EmbeddedTexture] = []
  ) {
    self.filePath = filePath
    self.rootNode = rootNode
    self.meshes = meshes
    self.materials = materials
    self.cameras = cameras
    self.animations = animations
    self.embeddedTextures = embeddedTextures

    // Collect all hint nodes
    collectAllHintNodes(from: rootNode)
  }

  private func collectAllHintNodes(from root: Node) {
    func collectNodes(withHint hint: ImportHint, from rootNode: Node) -> [Node] {
      var nodes: [Node] = []
      func traverse(_ node: Node) {
        // Check if name contains hint prefix as a complete word
        let prefix = hint.prefix
        let name = node.name

        // Check all occurrences of the prefix in the name
        var searchStartIndex = name.startIndex
        while let range = name.range(of: prefix, range: searchStartIndex..<name.endIndex) {
          let beforePrefix = name[..<range.lowerBound]
          let afterPrefix = name[range.upperBound...]

          // Check if prefix is a complete word:
          // - Before prefix: start of string or space
          // - After prefix: end of string or space
          let isAtStart = beforePrefix.isEmpty
          let isAfterSpace = !beforePrefix.isEmpty && beforePrefix.last == " "
          let isAtEnd = afterPrefix.isEmpty
          let isBeforeSpace = !afterPrefix.isEmpty && afterPrefix.first == " "

          if (isAtStart || isAfterSpace) && (isAtEnd || isBeforeSpace) {
            nodes.append(node)
            break  // Found match, no need to check further occurrences
          }

          // Continue searching from after this occurrence
          searchStartIndex = range.upperBound
        }

        for child in node.children {
          traverse(child)
        }
      }
      traverse(rootNode)
      return nodes
    }

    self.actionNodes = collectNodes(withHint: ImportHint.action, from: root)
    self.areaNodes = collectNodes(withHint: ImportHint.area, from: root)
    self.cameraNodes = collectNodes(withHint: ImportHint.camera, from: root)
    self.cameraTriggerNodes = collectNodes(withHint: ImportHint.cameraTrigger, from: root)
    self.collisionNodes = collectNodes(withHint: ImportHint.collision, from: root)
    self.doorNodes = collectNodes(withHint: ImportHint.door, from: root)
    self.entryNodes = collectNodes(withHint: ImportHint.entry, from: root)
    self.enemyNodes = collectNodes(withHint: ImportHint.enemy, from: root)
    self.floorNodes = collectNodes(withHint: ImportHint.floor, from: root)
    self.footstepsNodes = collectNodes(withHint: ImportHint.footsteps, from: root)
    self.foregroundNodes = collectNodes(withHint: ImportHint.foreground, from: root)
    self.ledgeNodes = collectNodes(withHint: ImportHint.ledge, from: root)
    self.mapMarkerNodes = collectNodes(withHint: ImportHint.mapMarker, from: root)
    self.pickupNodes = collectNodes(withHint: ImportHint.pickup, from: root)
    self.sparkleNodes = collectNodes(withHint: ImportHint.sparkle, from: root)
    self.triggerNodes = collectNodes(withHint: ImportHint.trigger, from: root)
    self.waypointNodes = collectNodes(withHint: ImportHint.waypoint, from: root)
  }

  // MARK: - Import Hint Parsing

  /// Extract all hints from a node name.
  public func parseHints(from nodeName: String) -> [ImportHint] {
    var hints: [ImportHint] = []
    for hint in ImportHint.allCases {
      if nodeName.contains(hint.prefix) {
        hints.append(hint)
      }
    }
    return hints
  }

  /// Check if a node has a specific hint.
  public func hasHint(_ node: Node, hint: ImportHint) -> Bool {
    node.name.contains(hint.prefix)
  }

  /// Traverse all nodes in the scene tree, calling the closure for each node.
  public func traverseNodes(_ closure: (Node) -> Void) {
    func traverse(_ node: Node) {
      closure(node)
      for child in node.children {
        traverse(child)
      }
    }
    traverse(rootNode)
  }

  /// Extract the base name from a node name, removing all hint prefixes.
  public static func extractBaseName(from nodeName: String) -> String {
    var baseName = nodeName
    // Remove all hint prefixes, starting with longest (most specific) first
    let sortedHints = ImportHint.allCases.sorted { $0.prefix.count > $1.prefix.count }
    for hint in sortedHints {
      baseName = baseName.replacingOccurrences(of: hint.prefix, with: "")
    }
    // Trim whitespace
    return baseName.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Normalize entries/camera identifiers so area comparisons stay consistent.
  public static func normalizedAreaIdentifier(_ name: String) -> String {
    guard !name.isEmpty else { return name }

    // Extract base name using static extractBaseName (handles @Entry format)
    var identifier = extractBaseName(from: name)

    // Remove numeric suffix if present (e.g., "hallway_2" -> "hallway")
    if let underscoreIndex = identifier.lastIndex(of: "_") {
      let suffixStart = identifier.index(after: underscoreIndex)
      if suffixStart < identifier.endIndex {
        let suffix = identifier[suffixStart...]
        if suffix.allSatisfy({ $0.isNumber }) {
          identifier = String(identifier[..<underscoreIndex])
        }
      }
    }

    return identifier
  }

  // MARK: - Convenience Methods

  /// Find an action node by base name
  public func actionNode(named baseName: String) -> Node? {
    actionNodes.first { $0.baseName == baseName }
  }

  /// Find an area node by base name
  public func areaNode(named baseName: String) -> Node? {
    areaNodes.first { $0.baseName == baseName }
  }

  /// Find a camera node by base name (e.g., "0" finds "@Camera 0")
  public func cameraNode(named baseName: String) -> Node? {
    cameraNodes.first { $0.baseName == baseName }
  }

  /// Find a camera trigger node by base name
  public func cameraTriggerNode(named baseName: String) -> Node? {
    cameraTriggerNodes.first { $0.baseName == baseName }
  }

  /// Find a door node by base name
  public func doorNode(named baseName: String) -> Node? {
    doorNodes.first { $0.baseName == baseName }
  }

  /// Find an entry node by base name (e.g., "1" finds "@Entry 1")
  public func entryNode(named baseName: String) -> Node? {
    entryNodes.first { $0.baseName == baseName }
  }

  /// Find an enemy node by base name
  public func enemyNode(named baseName: String) -> Node? {
    enemyNodes.first { $0.baseName == baseName }
  }

  /// Find a floor node by base name
  public func floorNode(named baseName: String) -> Node? {
    floorNodes.first { $0.baseName == baseName }
  }

  /// Find a footsteps node by base name
  public func footstepsNode(named baseName: String) -> Node? {
    footstepsNodes.first { $0.baseName == baseName }
  }

  /// Find a ledge node by base name
  public func ledgeNode(named baseName: String) -> Node? {
    ledgeNodes.first { $0.baseName == baseName }
  }

  /// Find a map marker node by base name
  public func mapMarkerNode(named baseName: String) -> Node? {
    mapMarkerNodes.first { $0.baseName == baseName }
  }

  /// Find a pickup node by base name
  public func pickupNode(named baseName: String) -> Node? {
    pickupNodes.first { $0.baseName == baseName }
  }

  /// Find a sparkle node by base name
  public func sparkleNode(named baseName: String) -> Node? {
    sparkleNodes.first { $0.baseName == baseName }
  }

  /// Find a trigger node by base name
  public func triggerNode(named baseName: String) -> Node? {
    triggerNodes.first { $0.baseName == baseName }
  }

  /// Find a waypoint node by base name
  public func waypointNode(named baseName: String) -> Node? {
    waypointNodes.first { $0.baseName == baseName }
  }

  /// Find a camera by base name (e.g., "0" finds "@Camera 0")
  /// Returns the Camera if available
  /// For GLTF scenes, uses the mapping from camera node to Camera object
  /// For Assimp scenes, matches by name
  public func camera(named baseName: String) -> Camera? {
    guard let cameraNode = cameraNode(named: baseName) else {
      return nil
    }

    // For GLTF scenes, use the mapping (camera objects can have different names than nodes)
    if let camera = _cameraNodeToCamera[baseName] {
      return camera
    }

    // Fallback for Assimp: try to match by camera node name first, then by base name
    return cameras.first(where: { $0.name == cameraNode.name })
      ?? cameras.first(where: { $0.name == baseName })
  }

  // MARK: - Debug Description

  /// Generate a human-readable debug description of all game-related nodes
  public var debugDescription: String {
    var lines: [String] = []
    lines.append("=== Scene Game Nodes ===")
    lines.append("")

    // Group nodes by hint type
    let hintGroups: [(ImportHint, [Node])] = [
      (.action, actionNodes),
      (.area, areaNodes),
      (.camera, cameraNodes),
      (.cameraTrigger, cameraTriggerNodes),
      (.collision, collisionNodes),
      (.door, doorNodes),
      (.entry, entryNodes),
      (.enemy, enemyNodes),
      (.floor, floorNodes),
      (.footsteps, footstepsNodes),
      (.foreground, foregroundNodes),
      (.ledge, ledgeNodes),
      (.mapMarker, mapMarkerNodes),
      (.pickup, pickupNodes),
      (.sparkle, sparkleNodes),
      (.trigger, triggerNodes),
      (.waypoint, waypointNodes),
    ]

    for (hint, nodes) in hintGroups {
      guard !nodes.isEmpty else { continue }
      lines.append("\(hint.prefix) (\(nodes.count)):")
      for node in nodes.sorted(by: { $0.name < $1.name }) {
        let baseName = node.baseName
        if baseName.isEmpty || baseName == node.name {
          lines.append("  - \(node.name)")
        } else {
          lines.append("  - \(node.name) → baseName: \"\(baseName)\"")
        }
      }
      lines.append("")
    }

    // Also list all cameras from the scene
    if !cameras.isEmpty {
      lines.append("Camera Objects (\(cameras.count)):")
      for camera in cameras.sorted(by: { ($0.name ?? "") < ($1.name ?? "") }) {
        lines.append("  - \(camera.name ?? "<unnamed>")")
      }
      lines.append("")
    }

    return lines.joined(separator: "\n")
  }
}

/// Embedded texture data (for GLB files)
public struct EmbeddedTexture {
  public let index: Int  // Index in the embedded texture array (e.g., "*0" -> index 0)
  public let data: Data
  public let width: Int
  public let height: Int
  public let formatHint: String?  // e.g., "png", "jpg", "webp"

  public init(index: Int, data: Data, width: Int, height: Int, formatHint: String? = nil) {
    self.index = index
    self.data = data
    self.width = width
    self.height = height
    self.formatHint = formatHint
  }
}
