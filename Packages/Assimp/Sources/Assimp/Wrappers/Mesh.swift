//
// AiMesh.swift
// SwiftAssimp
//
// Copyright © 2019-2022 Christian Treffs. All rights reserved.
// Licensed under BSD 3-Clause License. See LICENSE file for details.

import CAssimp

public class Mesh {
    public struct PrimitiveType: OptionSet {
        public let rawValue: UInt32

        public init(rawValue: UInt32) {
            self.rawValue = rawValue
        }

        public static let point = PrimitiveType(rawValue: aiPrimitiveType_POINT.rawValue)
        public static let line = PrimitiveType(rawValue: aiPrimitiveType_LINE.rawValue)
        public static let triangle = PrimitiveType(rawValue: aiPrimitiveType_TRIANGLE.rawValue)
        public static let polygon = PrimitiveType(rawValue: aiPrimitiveType_POLYGON.rawValue)
    }

    private let meshPtr: UnsafePointer<aiMesh>

    init(_ meshPtr: UnsafePointer<aiMesh>) {
        self.meshPtr = meshPtr
        let mesh = meshPtr.pointee
        primitiveTypes = PrimitiveType(rawValue: mesh.mPrimitiveTypes)
        numberOfVertices = Int(mesh.mNumVertices)
        numberOfFaces = Int(mesh.mNumFaces)
        numberOfBones = Int(mesh.mNumBones)
        materialIndex = Int(mesh.mMaterialIndex)
        name = String(mesh.mName)
        numberOfAnimatedMeshes = Int(mesh.mNumAnimMeshes)
        method = mesh.mMethod.rawValue
    }

    convenience init?(_ meshPtr: UnsafePointer<aiMesh>?) {
        guard let meshPtr = meshPtr else { return nil }
        self.init(meshPtr)
    }

    /// Bitwise combination of the members of the #aiPrimitiveType enum.
    /// This specifies which types of primitives are present in the mesh.
    ///
    /// The "SortByPrimitiveType"-Step can be used to make sure the output meshes consist of one primitive type each.
    public var primitiveTypes: PrimitiveType

    /// The number of vertices in this mesh. This is also the size of all of the per-vertex data arrays.
    /// The maximum value for this member is #AI_MAX_VERTICES.
    public var numberOfVertices: Int

    /// The number of primitives (triangles, polygons, lines) in this mesh.
    /// This is also the size of the mFaces array.
    /// The maximum value for this member is #AI_MAX_FACES.
    public var numberOfFaces: Int

    /// Vertex positions. This array is always present in a mesh.
    /// The array is numberOfVertices * 3 in size.
    public lazy var vertices = withUnsafeVertices([AssimpReal].init)

    public func withUnsafeVertices<R>(_ body: (UnsafeBufferPointer<AssimpReal>) throws -> R)
        rethrows -> R
    {
        let count = numberOfVertices * 3
        return try meshPtr.pointee.mVertices.withMemoryRebound(to: AssimpReal.self, capacity: count)
        {
            try body(UnsafeBufferPointer(start: $0, count: count))
        }
    }

    /// Vertex normals.
    /// The array contains normalized vectors, NULL if not present.
    /// The array is mNumVertices * 3 in size.
    ///
    /// Normals are undefined for point and line primitives.
    /// A mesh consisting of points and lines only may not have normal vectors.
    /// Meshes with mixed primitive types (i.e. lines and triangles) may have normals,
    /// but the normals for vertices that are only referenced by point or line primitives
    /// are undefined and set to QNaN (WARN: qNaN compares to inequal to *everything*, even to qNaN itself.
    public lazy var normals = withUnsafeNormals([AssimpReal].init)

    public func withUnsafeNormals<R>(_ body: (UnsafeBufferPointer<AssimpReal>) throws -> R) rethrows
        -> R
    {
        let count = numberOfVertices * 3
        return try meshPtr.pointee.mNormals.withMemoryRebound(to: AssimpReal.self, capacity: count)
        {
            try body(UnsafeBufferPointer(start: $0, count: count))
        }
    }

    /// Vertex tangents.
    /// The tangent of a vertex points in the direction of the positive X texture axis.
    /// The array contains normalized vectors, NULL if not present.
    /// The array is mNumVertices * 3 in size.
    ///
    /// A mesh consisting of points and lines only may not have normal vectors.
    /// Meshes with mixed primitive types (i.e. lines and triangles) may have normals,
    /// but the normals for vertices that are only referenced by point or line primitives
    /// are undefined and set to qNaN.
    /// See the #mNormals member for a detailed discussion of qNaNs.
    public lazy var tangents = withUnsafeTangents([AssimpReal].init)

    public func withUnsafeTangents<R>(_ body: (UnsafeBufferPointer<AssimpReal>) throws -> R)
        rethrows -> R
    {
        let count = numberOfVertices * 3
        return try meshPtr.pointee.mTangents.withMemoryRebound(to: AssimpReal.self, capacity: count)
        {
            try body(UnsafeBufferPointer(start: $0, count: count))
        }
    }

    /// Vertex bitangents.
    /// The bitangent of a vertex points in the direction of the positive Y texture axis.
    /// The array contains normalized vectors, NULL if not present.
    /// The array is mNumVertices * 3 in size.
    public lazy var bitangents = withUnsafeBitangents([AssimpReal].init)

    public func withUnsafeBitangents<R>(_ body: (UnsafeBufferPointer<AssimpReal>) throws -> R)
        rethrows -> R
    {
        let count = numberOfVertices * 3
        return try meshPtr.pointee.mBitangents.withMemoryRebound(
            to: AssimpReal.self, capacity: count
        ) {
            try body(UnsafeBufferPointer(start: $0, count: count))
        }
    }

    public typealias Channels<T> = (T, T, T, T, T, T, T, T)

    /// Vertex color sets.
    ///
    /// A mesh may contain 0 to #AI_MAX_NUMBER_OF_COLOR_SETS vertex colors per vertex.
    /// NULL if not present.
    /// Each array is numberOfVertices * 4 in size if present.
    /// Returns RGBA colors.
    public lazy var colors: Channels<[AssimpReal]?> = {
        typealias CVertexColorSet = (
            UnsafeMutablePointer<aiColor4D>?,
            UnsafeMutablePointer<aiColor4D>?,
            UnsafeMutablePointer<aiColor4D>?,
            UnsafeMutablePointer<aiColor4D>?,
            UnsafeMutablePointer<aiColor4D>?,
            UnsafeMutablePointer<aiColor4D>?,
            UnsafeMutablePointer<aiColor4D>?,
            UnsafeMutablePointer<aiColor4D>?
        )

        let maxColorsPerSet = numberOfVertices * 4  // aiColor4D(RGBA) * numberOfVertices
        func colorSet(at keyPath: KeyPath<CVertexColorSet, UnsafeMutablePointer<aiColor4D>?>)
            -> [AssimpReal]?
        {
            guard let baseAddress = meshPtr.pointee.mColors[keyPath: keyPath] else {
                return nil
            }

            return baseAddress.withMemoryRebound(to: AssimpReal.self, capacity: maxColorsPerSet) {
                pColorSet in
                [AssimpReal](UnsafeBufferPointer(start: pColorSet, count: maxColorsPerSet))
            }
        }

        return (
            colorSet(at: \.0),
            colorSet(at: \.1),
            colorSet(at: \.2),
            colorSet(at: \.3),
            colorSet(at: \.4),
            colorSet(at: \.5),
            colorSet(at: \.6),
            colorSet(at: \.7)
        )
    }()

    /// Vertex texture coords, also known as UV channels.
    ///
    /// A mesh may contain 0 to AI_MAX_NUMBER_OF_TEXTURECOORDS per vertex.
    /// NULL if not present.
    /// The array is numberOfVertices * 3 in size.
    public lazy var texCoords: Channels<[AssimpReal]?> = {
        typealias CVertexUVChannels = (
            UnsafeMutablePointer<aiVector3D>?,
            UnsafeMutablePointer<aiVector3D>?,
            UnsafeMutablePointer<aiVector3D>?,
            UnsafeMutablePointer<aiVector3D>?,
            UnsafeMutablePointer<aiVector3D>?,
            UnsafeMutablePointer<aiVector3D>?,
            UnsafeMutablePointer<aiVector3D>?,
            UnsafeMutablePointer<aiVector3D>?
        )

        let maxTexCoordsPerChannel = numberOfVertices * 3  // aiVector3D * numberOfVertices

        func uvChannel(at keyPath: KeyPath<CVertexUVChannels, UnsafeMutablePointer<aiVector3D>?>)
            -> [AssimpReal]?
        {
            guard let baseAddress = meshPtr.pointee.mTextureCoords[keyPath: keyPath] else {
                return nil
            }

            return baseAddress.withMemoryRebound(
                to: AssimpReal.self, capacity: maxTexCoordsPerChannel
            ) {
                [AssimpReal](UnsafeBufferPointer(start: $0, count: maxTexCoordsPerChannel))
            }
        }

        return Channels(
            uvChannel(at: \.0),
            uvChannel(at: \.1),
            uvChannel(at: \.2),
            uvChannel(at: \.3),
            uvChannel(at: \.4),
            uvChannel(at: \.5),
            uvChannel(at: \.6),
            uvChannel(at: \.7)
        )
    }()

    public lazy var texCoordsPacked: Channels<[AssimpReal]?> = {
        func packChannel(
            uv: KeyPath<Channels<Int>, Int>, tex: KeyPath<Channels<[AssimpReal]?>, [AssimpReal]?>
        ) -> [AssimpReal]? {
            let count: Int = self.numberOfUVComponents[keyPath: uv]
            guard let uvs = self.texCoords[keyPath: tex] else {
                return nil
            }
            switch count {
            case 1:  // u
                return stride(from: 0, to: uvs.count, by: 3).map { uvs[$0] }

            case 2:  // uv
                return stride(from: 0, to: uvs.count, by: 3).flatMap { uvs[$0...$0 + 1] }

            case 3:  // uvw
                return uvs

            default:
                return nil
            }
        }

        return Channels(
            packChannel(uv: \.0, tex: \.0),
            packChannel(uv: \.1, tex: \.1),
            packChannel(uv: \.2, tex: \.2),
            packChannel(uv: \.3, tex: \.3),
            packChannel(uv: \.4, tex: \.4),
            packChannel(uv: \.5, tex: \.5),
            packChannel(uv: \.6, tex: \.6),
            packChannel(uv: \.7, tex: \.7)
        )
    }()

    /// Specifies the number of components for a given UV channel.
    /// Up to three channels are supported (UVW, for accessing volume or cube maps).
    ///
    /// If the value is 2 for a given channel n, the component p.z of mTextureCoords[n][p] is set to 0.0f.
    /// If the value is 1 for a given channel, p.y is set to 0.0f, too.
    /// 4D coords are not supported
    public lazy var numberOfUVComponents = Channels(
        Int(meshPtr.pointee.mNumUVComponents.0),
        Int(meshPtr.pointee.mNumUVComponents.1),
        Int(meshPtr.pointee.mNumUVComponents.2),
        Int(meshPtr.pointee.mNumUVComponents.3),
        Int(meshPtr.pointee.mNumUVComponents.4),
        Int(meshPtr.pointee.mNumUVComponents.5),
        Int(meshPtr.pointee.mNumUVComponents.6),
        Int(meshPtr.pointee.mNumUVComponents.7))

    /// The faces the mesh is constructed from.
    /// Each face refers to a number of vertices by their indices.
    /// This array is always present in a mesh, its size is given in mNumFaces.
    ///
    /// If the #AI_SCENE_FLAGS_NON_VERBOSE_FORMAT is NOT set each face references an unique set of vertices.
    public lazy var faces: [Face] = {
        guard let facesPtr = meshPtr.pointee.mFaces else { return [] }
        return UnsafeBufferPointer(start: facesPtr, count: numberOfFaces).map(Face.init)
    }()

    /// The number of bones this mesh contains.
    /// Can be 0, in which case the mBones array is NULL.
    public var numberOfBones: Int

    /// The material used by this mesh.
    ///
    /// A mesh uses only a single material.
    /// If an imported model uses multiple materials, the import splits up the mesh.
    /// Use this value as index into the scene's material list.
    public var materialIndex: Int

    /// Name of the mesh. Meshes can be named, but this is not a requirement and leaving this field empty is totally fine.
    ///
    /// There are mainly three uses for mesh names:
    ///    - some formats name nodes and meshes independently.
    ///    - importers tend to split meshes up to meet the one-material-per-mesh requirement.
    ///      Assigning the same (dummy) name to each of the result meshes aids the caller at recovering the original mesh partitioning.
    ///    - Vertex animations refer to meshes by their names.
    ///
    public var name: String?

    /// The number of attachment meshes.
    ///
    /// **Note:** Currently only works with Collada loader.
    public var numberOfAnimatedMeshes: Int

    /// Method of morphing when animeshes are specified.
    public var method: UInt32
}
