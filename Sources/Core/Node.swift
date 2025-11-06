import Assimp

/// Wrapper around Assimp.Node that provides persistent state (like isHidden)
/// and builds the entire tree upfront so findNode() returns the same instances
public final class Node {
  internal let assimpNode: Assimp.Node

  public var isHidden: Bool = false
  
  public let children: [Node]
  
  public var name: String? { assimpNode.name }
  public var transformation: Assimp.Matrix4x4 { assimpNode.transformation }
  public var numberOfMeshes: Int { assimpNode.numberOfMeshes }
  public var numberOfChildren: Int { assimpNode.numberOfChildren }
  public var meshes: [Int] { assimpNode.meshes }
  public var metadata: Assimp.SceneMetadata? { assimpNode.metadata }
  
  init(_ assimpNode: Assimp.Node) {
    self.assimpNode = assimpNode
    // Build our own tree upfront - recursively wrap all children
    self.children = assimpNode.children.map { Node($0) }
  }
  
  /// Find a node by name in our own tree (returns same Node instance each time)
  public func findNode(named nodeName: String) -> Node? {
    // Check if this node matches
    if name == nodeName {
      return self
    }
    
    // Recursively search children in our own tree
    for child in children {
      if let found = child.findNode(named: nodeName) {
        return found
      }
    }
    
    return nil
  }
}

extension Node: CustomDebugStringConvertible {
  private func debugDescription(level: Int) -> String {
    let indent = String(repeating: "  ", count: level)
    let nameStr = name ?? "<no name>"
    let header = "\(indent)<Node '\(nameStr)' meshes:\(meshes) children:\(numberOfChildren) hidden:\(isHidden) metadata:\(metadata?.numberOfProperties ?? 0)>"
    
    if children.isEmpty {
      return header
    } else {
      let childDescriptions = children
        .map { $0.debugDescription(level: level + 1) }
        .joined(separator: "\n")
      
      return "\(header)\n\(childDescriptions)"
    }
  }
  
  public var debugDescription: String {
    debugDescription(level: 0)
  }
}
