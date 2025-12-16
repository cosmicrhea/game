import Assimp
import Foundation
import GLMath

/// Format-agnostic scene node that works with both Assimp and GLTF
/// Provides persistent state (like isHidden) and builds the entire tree upfront
public final class Node {
  public let name: String
  public let transformation: mat4
  public let meshes: [Int]  // Indices into scene.meshes
  public let children: [Node]
  public var isHidden: Bool = false

  /// Weak reference to parent (set during tree construction for world transform calculation)
  weak var parent: Node?

  // Optional: Store Assimp node for backward compatibility (only if created from Assimp)
  internal var _assimpNode: Assimp.Node?

  // Optional: Store parsed GLTF metadata (only if created from GLTF)
  internal var _gltfMetadata: NodeMetadata?

  // Backward compatibility: Access Assimp node if available
  public var assimpNode: Assimp.Node? {
    return _assimpNode
  }

  // Unified metadata access - works for both Assimp and GLTF
  public var metadata: NodeMetadata? {
    // Prefer GLTF metadata if available, otherwise fall back to Assimp
    if let gltfMetadata = _gltfMetadata {
      return gltfMetadata
    }
    // Convert Assimp metadata to unified format
    if let assimpMetadata = _assimpNode?.metadata {
      return NodeMetadata(from: assimpMetadata)
    }
    return nil
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

  /// Initialize from Assimp.Node (for backward compatibility)
  convenience init(_ assimpNode: Assimp.Node) {
    let transformation = assimpNode.transformation.mat4Representation
    let meshes = assimpNode.meshes
    let children = assimpNode.children.map { Node($0) }

    self.init(
      name: assimpNode.name ?? "",
      transformation: transformation,
      meshes: meshes,
      children: children
    )

    // Store Assimp node for backward compatibility
    self._assimpNode = assimpNode
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

/// Unified metadata system that works with both Assimp and GLTF
/// Provides a dictionary-like interface similar to Assimp.SceneMetadata
public struct NodeMetadata {
  private let _metadata: [String: MetadataEntry]

  public var numberOfProperties: Int {
    _metadata.count
  }

  public var metadata: [String: MetadataEntry] {
    _metadata
  }

  /// Initialize from Assimp metadata
  init(from assimpMetadata: Assimp.SceneMetadata) {
    var dict: [String: MetadataEntry] = [:]
    for (key, entry) in assimpMetadata.metadata {
      switch entry {
      case .bool(let value):
        dict[key] = .bool(value)
      case .int32(let value):
        dict[key] = .int(Int(value))
      case .uint64(let value):
        dict[key] = .int(Int(value))
      case .float(let value):
        dict[key] = .float(value)
      case .double(let value):
        dict[key] = .float(Float(value))
      case .string(let value):
        dict[key] = .string(value)
      case .vec3(let vec):
        dict[key] = .vec3((vec.x, vec.y, vec.z))
      case .metadata:
        // Nested metadata not supported in unified format
        break
      @unknown default:
        // Ignore unknown entry types
        break
      }
    }
    self._metadata = dict
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
