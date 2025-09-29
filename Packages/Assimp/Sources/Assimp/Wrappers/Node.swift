//
// AiNode.swift
// SwiftAssimp
//
// Copyright © 2019-2022 Christian Treffs. All rights reserved.
// Licensed under BSD 3-Clause License. See LICENSE file for details.

import CAssimp

public class Node {
    private let nodePtr: UnsafePointer<aiNode>

    init(_ node: aiNode) {
        nodePtr = withUnsafePointer(to: node) { UnsafePointer($0) }
        name = String(node.mName)
        transformation = Matrix4x4(node.mTransformation)
        let numberOfMeshes = Int(node.mNumMeshes)
        self.numberOfMeshes = numberOfMeshes
        let numberOfChildren = Int(node.mNumChildren)
        self.numberOfChildren = numberOfChildren
        meshes = {
            guard numberOfMeshes > 0 else {
                return []
            }

            return (0 ..< numberOfMeshes)
                .compactMap { node.mMeshes[$0] }
                .map { Int($0) }
        }()

        if numberOfChildren > 0 {
            children = UnsafeBufferPointer(start: node.mChildren, count: numberOfChildren).compactMap { Node($0?.pointee) }
        } else {
            children = []
        }

        if let meta = node.mMetaData {
            metadata = AssimpMetadata(meta.pointee)
        } else {
            metadata = nil
        }
    }

  convenience init?(_ node: aiNode?) {
        guard let node = node else {
            return nil
        }
        self.init(node)
    }

    /// The name of the node.
    ///
    /// The name might be empty (length of zero) but all nodes which need to be referenced by either bones or animations are named.
    /// Multiple nodes may have the same name, except for nodes which are referenced by bones (see #aiBone and #aiMesh::mBones).
    /// Their names *must* be unique.
    ///
    /// Cameras and lights reference a specific node by name - if there are multiple nodes with this name, they are assigned to each of them.
    /// There are no limitations with regard to the characters contained in the name string as it is usually taken directly from the source file.
    ///
    /// Implementations should be able to handle tokens such as whitespace, tabs, line feeds, quotation marks, ampersands etc.
    ///
    /// Sometimes assimp introduces new nodes not present in the source file into the hierarchy (usually out of necessity because sometimes the source hierarchy format is simply not compatible).
    ///
    /// Their names are surrounded by
    /// `<>`
    /// e.g.
    /// `<DummyRootNode>`
    public var name: String?

    /// The transformation relative to the node's parent.
    public var transformation: Matrix4x4

    /// Parent node.
    ///
    /// NULL if this node is the root node.
    public var parent: Node? {
        guard let parent = nodePtr.pointee.mParent else {
            return nil
        }
        return Node(parent.pointee)
    }

    /// The number of meshes of this node.
    public var numberOfMeshes: Int

    /// The number of child nodes of this node.
    public var numberOfChildren: Int

    /// The meshes of this node.
    /// Each entry is an index into the mesh list of the #aiScene.
    public var meshes: [Int]

    /// The child nodes of this node.
    ///
    /// NULL if mNumChildren is 0.
    public var children: [Node]

    /// Metadata associated with this node or NULL if there is no metadata.
    /// Whether any metadata is generated depends on the source file format.
    public var metadata: AssimpMetadata?
}

extension Node: CustomDebugStringConvertible {
    private func debugDescription(level: Int) -> String {
        let indent = String(repeating: "  ", count: level)
        let header = "\(indent)<\(type(of: self)) '\(name ?? "")' meshes:\(meshes) children:\(numberOfChildren)>"
        if children.isEmpty {
            return header
        } else {
            let childDescs = children.map { $0.debugDescription(level: level + 1) }.joined(separator: "\n")
            return "\(header)\n\(childDescs)"
        }
    }

    public var debugDescription: String {
        return debugDescription(level: 0)
    }
}

/// Container for holding metadata.
/// Metadata is a key-value store using string keys and values.
public struct AssimpMetadata {
    init(_ meta: aiMetadata) {
        numberOfProperties = Int(meta.mNumProperties)
        keys = UnsafeBufferPointer(start: meta.mKeys, count: numberOfProperties).compactMap(String.init)
        values = UnsafeBufferPointer(start: meta.mValues, count: numberOfProperties).compactMap(Entry.init)
    }

    /// Length of the mKeys and mValues arrays, respectively
    public var numberOfProperties: Int

    /// Arrays of keys, may not be NULL.
    /// Entries in this array may not be NULL as well.
    public var keys: [String]

    /// Arrays of values, may not be NULL.
    /// Entries in this array may be NULL if the corresponding property key has no assigned value.
    public var values: [Entry]

    public var metadata: [String: Entry] {
        [String: Entry](uniqueKeysWithValues: (0 ..< numberOfProperties).map { (keys[$0], values[$0]) })
    }

    public enum Entry {
        case bool(Bool)
        case int32(Int32)
        case uint64(UInt64)
        case float(Float)
        case double(Double)
        case string(String)
        case vec3(AssimpVec3)
        case metadata(AssimpMetadata)

        init?(_ entry: aiMetadataEntry) {
            guard let pData = entry.mData else {
                return nil
            }

            switch entry.mType {
            case AI_BOOL:
                self = .bool(pData.bindMemory(to: Bool.self, capacity: 1).pointee)

            case AI_INT32:
                self = .int32(pData.bindMemory(to: Int32.self, capacity: 1).pointee)

            case AI_UINT64:
                self = .uint64(pData.bindMemory(to: UInt64.self, capacity: 1).pointee)

            case AI_FLOAT:
                self = .float(pData.bindMemory(to: Float.self, capacity: 1).pointee)

            case AI_DOUBLE:
                self = .double(pData.bindMemory(to: Double.self, capacity: 1).pointee)

            case AI_AISTRING:
                guard let string = String(pData.bindMemory(to: aiString.self, capacity: 1).pointee) else {
                    return nil
                }
                self = .string(string)

            case AI_AIVECTOR3D:
                self = .vec3(AssimpVec3(pData.bindMemory(to: aiVector3D.self, capacity: 1).pointee))

            case AI_AIMETADATA:
                self = .metadata(AssimpMetadata(pData.bindMemory(to: aiMetadata.self, capacity: 1).pointee))

            case AI_META_MAX:
                return nil

            case FORCE_32BIT:
                return nil

            default:
                return nil
            }
        }
    }
}
