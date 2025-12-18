import Foundation
import GLMath

/// Scene node for GLTF scenes
/// Provides persistent state (like isHidden) and builds the entire tree upfront
public final class Node {
  public let name: String
  public let transformation: mat4
  public let meshes: [Int]  // Indices into scene.meshes
  public let children: [Node]
  public var isHidden: Bool = false

  /// Weak reference to parent (set during tree construction for world transform calculation)
  weak var parent: Node?

  // Optional: Store parsed GLTF metadata
  internal var _gltfMetadata: NodeMetadata?

  // Metadata access from GLTF
  public var metadata: NodeMetadata? {
    return _gltfMetadata
  }

  /// The base name of the node, with all hint prefixes removed
  public var baseName: String {
    Scene.extractBaseName(from: name)
  }

  /// Number of meshes (for compatibility)
  public var numberOfMeshes: Int { meshes.count }

  /// Number of children (for compatibility)
  public var numberOfChildren: Int { children.count }

  public init(
    name: String,
    transformation: mat4 = mat4(1),
    meshes: [Int] = [],
    children: [Node] = []
  ) {
    self.name = name
    self.transformation = transformation
    self.meshes = meshes
    self.children = children

    // Set parent references for children
    for child in children {
      child.parent = self
    }
  }

  /// Find a node by name in the hierarchy
  public func findNode(named nodeName: String) -> Node? {
    if name == nodeName {
      return self
    }
    for child in children {
      if let found = child.findNode(named: nodeName) {
        return found
      }
    }
    return nil
  }

  /// Calculate world transform by traversing up the hierarchy
  public func calculateWorldTransform() -> mat4 {
    var transform = transformation
    var currentNode: Node? = self

    while let parent = currentNode?.parent {
      transform = parent.transformation * transform
      currentNode = parent
    }

    return transform
  }
}

extension Node: CustomDebugStringConvertible {
  private func debugDescription(level: Int) -> String {
    let indent = String(repeating: "  ", count: level)
    let nameStr = name.isEmpty ? "<no name>" : name
    let header =
      "\(indent)<Node '\(nameStr)' meshes:\(meshes) children:\(numberOfChildren) hidden:\(isHidden) metadata:\(metadata?.numberOfProperties ?? 0)>"

    if children.isEmpty {
      return header
    } else {
      let childDescriptions =
        children
        .map { $0.debugDescription(level: level + 1) }
        .joined(separator: "\n")

      return "\(header)\n\(childDescriptions)"
    }
  }

  public var debugDescription: String {
    debugDescription(level: 0)
  }
}

/// Metadata system for GLTF scenes
/// Provides a dictionary-like interface for node metadata
public struct NodeMetadata {
  private let _metadata: [String: MetadataEntry]

  public var numberOfProperties: Int {
    _metadata.count
  }

  public var metadata: [String: MetadataEntry] {
    _metadata
  }

  /// Initialize from GLTF JSON extras
  init?(from gltfExtrasJSON: String) {
    guard let data = gltfExtrasJSON.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return nil
    }

    var dict: [String: MetadataEntry] = [:]
    for (key, value) in json {
      if let boolValue = value as? Bool {
        dict[key] = .bool(boolValue)
      } else if let intValue = value as? Int {
        dict[key] = .int(intValue)
      } else if let doubleValue = value as? Double {
        dict[key] = .float(Float(doubleValue))
      } else if let floatValue = value as? Float {
        dict[key] = .float(floatValue)
      } else if let stringValue = value as? String {
        dict[key] = .string(stringValue)
      } else if let arrayValue = value as? [Any], arrayValue.count == 3,
        let x = arrayValue[0] as? Double,
        let y = arrayValue[1] as? Double,
        let z = arrayValue[2] as? Double
      {
        dict[key] = .vec3((Float(x), Float(y), Float(z)))
      }
    }
    self._metadata = dict
  }
}

/// Unified metadata entry type
public enum MetadataEntry {
  case bool(Bool)
  case int(Int)
  case float(Float)
  case string(String)
  case vec3((Float, Float, Float))
}
