import Assimp

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

/// Wrapper around Assimp.Scene that provides our own Node tree
public final class Scene {
  internal let assimpScene: Assimp.Scene

  // Our own Node tree (built upfront)
  public let rootNode: Node

  // Delegate to Assimp.Scene
  public var meshes: [Assimp.Mesh] { assimpScene.meshes }
  public var materials: [Assimp.Material] { assimpScene.materials }
  public var cameras: [Assimp.Camera] { assimpScene.cameras }
  public var lights: [Assimp.Light] { assimpScene.lights }
  public var textures: [Assimp.Texture] { assimpScene.textures }
  public var animations: [Assimp.Animation] { assimpScene.animations }
  public var filePath: String { assimpScene.filePath }
  public var numberOfMeshes: Int { assimpScene.numberOfMeshes }
  public var numberOfMaterials: Int { assimpScene.numberOfMaterials }
  public var numberOfCameras: Int { assimpScene.numberOfCameras }
  public var numberOfLights: Int { assimpScene.numberOfLights }
  public var numberOfTextures: Int { assimpScene.numberOfTextures }
  public var numberOfAnimations: Int { assimpScene.numberOfAnimations }
  public var hasMeshes: Bool { assimpScene.hasMeshes }
  public var hasMaterials: Bool { assimpScene.hasMaterials }
  public var hasCameras: Bool { assimpScene.hasCameras }
  public var hasLights: Bool { assimpScene.hasLights }
  public var hasTextures: Bool { assimpScene.hasTextures }
  public var hasAnimations: Bool { assimpScene.hasAnimations }
  public var flags: Assimp.Scene.Flags { assimpScene.flags }

  init(_ assimpScene: Assimp.Scene) {
    self.assimpScene = assimpScene

    // Build our own Node tree upfront
    let root = Node(assimpScene.rootNode)
    self.rootNode = root

    // Eagerly load all hint collections
    // logger.measure("Collected nodes") {
    collectAllHintNodes(from: root)
    // }
  }

  private func collectAllHintNodes(from root: Node) {
    func collectNodes(withHint hint: ImportHint, from rootNode: Node) -> [Node] {
      var nodes: [Node] = []
      func traverse(_ node: Node) {
        // Check if name contains hint prefix as a complete word
        // This allows nodes like "@Area @Collision Foo" to match both hints
        // and prevents "@CameraTrigger" from matching "@Camera"
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

    self.actionNodes = collectNodes(withHint: .action, from: root)
    self.areaNodes = collectNodes(withHint: .area, from: root)
    self.cameraNodes = collectNodes(withHint: .camera, from: root)
    self.cameraTriggerNodes = collectNodes(withHint: .cameraTrigger, from: root)
    self.collisionNodes = collectNodes(withHint: .collision, from: root)
    self.doorNodes = collectNodes(withHint: .door, from: root)
    self.entryNodes = collectNodes(withHint: .entry, from: root)
    self.enemyNodes = collectNodes(withHint: .enemy, from: root)
    self.floorNodes = collectNodes(withHint: .floor, from: root)
    self.footstepsNodes = collectNodes(withHint: .footsteps, from: root)
    self.foregroundNodes = collectNodes(withHint: .foreground, from: root)
    self.ledgeNodes = collectNodes(withHint: .ledge, from: root)
    self.mapMarkerNodes = collectNodes(withHint: .mapMarker, from: root)
    self.pickupNodes = collectNodes(withHint: .pickup, from: root)
    self.sparkleNodes = collectNodes(withHint: .sparkle, from: root)
    self.triggerNodes = collectNodes(withHint: .trigger, from: root)
    self.waypointNodes = collectNodes(withHint: .waypoint, from: root)
  }

  /// Load a scene from a file
  public convenience init(file filePath: String, flags: Assimp.PostProcessStep = []) throws {
    let assimpScene = try Assimp.Scene(file: filePath, flags: flags)
    self.init(assimpScene)
  }

  /// Load a scene from a file with progress callback.
  public convenience init(
    file filePath: String,
    flags: Assimp.PostProcessStep = [],
    progress: @escaping (Float) -> Bool
  ) throws {
    let assimpScene = try Assimp.Scene(file: filePath, flags: flags, progress: progress)
    self.init(assimpScene)
  }

  /// Get transform matrix for a mesh (delegates to Assimp.Scene extension).
  func getTransformMatrix(for mesh: Assimp.Mesh) -> mat4 {
    return assimpScene.getTransformMatrix(for: mesh)
  }

  // MARK: - Import Hint Parsing

  /// Extract all hints from a node name.
  /// - Parameter nodeName: The node name to parse.
  /// - Returns: Array of ImportHint values found in the name.
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
  /// - Parameters:
  ///   - node: The node to check.
  ///   - hint: The hint to look for.
  /// - Returns: True if the node name contains the hint prefix.
  public func hasHint(_ node: Node, hint: ImportHint) -> Bool {
    node.name.contains(hint.prefix)
  }

  /// Traverse all nodes in the scene tree, calling the closure for each node.
  /// - Parameter closure: Closure called for each node during traversal.
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
  /// - Parameter nodeName: The node name to extract base name from.
  /// - Returns: The base name without any hint prefixes.
  public static func extractBaseName(from nodeName: String) -> String {
    var baseName = nodeName
    // Remove all hint prefixes, starting with longest (most specific) first
    // This ensures "@CameraTrigger" is removed before "@Camera"
    let sortedHints = ImportHint.allCases.sorted { $0.prefix.count > $1.prefix.count }
    for hint in sortedHints {
      baseName = baseName.replacingOccurrences(of: hint.prefix, with: "")
    }
    // Trim whitespace
    return baseName.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Normalize entries/camera identifiers so area comparisons stay consistent.
  /// - "@Entry 1" -> "1"
  /// - "@Entry hallway" -> "hallway"
  /// - "hallway_2" -> "hallway"
  /// - "hallway" -> "hallway"
  /// - "1" -> "1"
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

  // MARK: - Hint-Based Node Collections

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

  // MARK: - Convenience Methods

  /// Find a camera by base name (e.g., "0" finds "@Camera 0")
  public func camera(named baseName: String) -> Assimp.Camera? {
    guard let cameraNode = cameraNode(named: baseName) else {
      return nil
    }
    return cameras.first(where: { $0.name == cameraNode.name })
  }

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

    // Also list all cameras from Assimp
    if !cameras.isEmpty {
      lines.append("Assimp Cameras (\(cameras.count)):")
      for camera in cameras.sorted(by: { ($0.name ?? "") < ($1.name ?? "") }) {
        lines.append("  - \(camera.name ?? "<unnamed>")")
      }
      lines.append("")
    }

    return lines.joined(separator: "\n")
  }
}
