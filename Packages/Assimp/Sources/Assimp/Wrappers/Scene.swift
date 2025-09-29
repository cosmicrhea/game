//
// AiScene.swift
// SwiftAssimp
//
// Copyright © 2019-2022 Christian Treffs. All rights reserved.
// Licensed under BSD 3-Clause License. See LICENSE file for details.

import CAssimp

public final class Scene {
    public enum Error: Swift.Error {
        case importFailed(String)
        case importIncomplete(String)
        case noRootNode
    }

    public struct Flags: OptionSet {
        public var rawValue: Int32

        public init(rawValue: Int32) {
            self.rawValue = rawValue
        }

        public static let incomplete = Flags(rawValue: AI_SCENE_FLAGS_INCOMPLETE)
        public static let validated = Flags(rawValue: AI_SCENE_FLAGS_VALIDATED)
        public static let validationWarning = Flags(rawValue: AI_SCENE_FLAGS_VALIDATION_WARNING)
        public static let nonVerboseFormat = Flags(rawValue: AI_SCENE_FLAGS_NON_VERBOSE_FORMAT)
        public static let terrain = Flags(rawValue: AI_SCENE_FLAGS_TERRAIN)
        public static let allowShared = Flags(rawValue: AI_SCENE_FLAGS_ALLOW_SHARED)
    }

    private let scenePtr: UnsafePointer<aiScene>

    public init(file filePath: String, flags: PostProcessStep = []) throws {
        guard let scenePtr = aiImportFile(filePath, flags.rawValue) else {
            throw Error.importFailed(String(cString: aiGetErrorString()))
        }
        self.scenePtr = scenePtr
        let flags = Flags(rawValue: Int32(scenePtr.pointee.mFlags))

        if flags.contains(.incomplete) {
            throw Error.importIncomplete(filePath)
        }
        self.flags = flags

        let numberOfMeshes = Int(scenePtr.pointee.mNumMeshes)
        self.numberOfMeshes = numberOfMeshes
        let numberOfMaterials = Int(scenePtr.pointee.mNumMaterials)
        self.numberOfMaterials = numberOfMaterials
        let numberOfAnimations = Int(scenePtr.pointee.mNumAnimations)
        self.numberOfAnimations = numberOfAnimations
        let numberOfTextures = Int(scenePtr.pointee.mNumTextures)
        self.numberOfTextures = numberOfTextures
        let numberOfLights = Int(scenePtr.pointee.mNumLights)
        self.numberOfLights = numberOfLights
        let numberOfCameras = Int(scenePtr.pointee.mNumCameras)
        self.numberOfCameras = numberOfCameras

        hasMeshes = scenePtr.pointee.mMeshes != nil && numberOfMeshes > 0
        hasMaterials = scenePtr.pointee.mMaterials != nil && numberOfMaterials > 0
        hasLights = scenePtr.pointee.mLights != nil && numberOfLights > 0
        hasTextures = scenePtr.pointee.mTextures != nil && numberOfTextures > 0
        hasCameras = scenePtr.pointee.mCameras != nil && numberOfCameras > 0
        hasAnimations = scenePtr.pointee.mAnimations != nil && numberOfAnimations > 0

        guard let node = scenePtr.pointee.mRootNode?.pointee else {
            throw Error.noRootNode
        }

        rootNode = Node(node)
    }

    deinit {
        aiReleaseImport(scenePtr)
    }

    /// Check whether the scene contains meshes
    /// Unless no special scene flags are set this will always be true.
    public var hasMeshes: Bool

    /// Check whether the scene contains materials
    /// Unless no special scene flags are set this will always be true.
    public var hasMaterials: Bool

    /// Check whether the scene contains lights
    public var hasLights: Bool

    /// Check whether the scene contains embedded textures
    public var hasTextures: Bool

    /// Check whether the scene contains cameras
    public var hasCameras: Bool

    /// Check whether the scene contains animations
    public var hasAnimations: Bool

    /// Any combination of the AI_SCENE_FLAGS_XXX flags.
    ///
    /// By default this value is 0, no flags are set.
    /// Most applications will want to reject all scenes with the AI_SCENE_FLAGS_INCOMPLETE bit set.
    public var flags: Flags

    /// The root node of the hierarchy.
    ///
    /// There will always be at least the root node if the import was successful (and no special flags have been set).
    /// Presence of further nodes depends on the format and content of the imported file.
    public var rootNode: Node

    /// The number of meshes in the scene.
    public var numberOfMeshes: Int

    /// The array of meshes.
    /// Use the indices given in the aiNode structure to access this array.
    /// The array is mNumMeshes in size.
    ///
    /// If the AI_SCENE_FLAGS_INCOMPLETE flag is not set there will always be at least ONE material.
    public lazy var meshes: [Mesh] = UnsafeBufferPointer(
        start: scenePtr.pointee.mMeshes, count: numberOfMeshes
    ).compactMap { Mesh($0) }

    /// The number of materials in the scene.
    public var numberOfMaterials: Int

    /// The array of materials.
    /// Use the index given in each aiMesh structure to access this array.
    /// The array is mNumMaterials in size.
    ///
    /// If the AI_SCENE_FLAGS_INCOMPLETE flag is not set there will always be at least ONE material.
    ///
    /// <http://assimp.sourceforge.net/lib_html/materials.html>
    public lazy var materials: [Material] = UnsafeBufferPointer(
        start: scenePtr.pointee.mMaterials, count: numberOfMaterials
    ).compactMap { Material($0?.pointee) }

    /// The number of animations in the scene.
    public var numberOfAnimations: Int

    /// The array of animations.
    /// All animations imported from the given file are listed here.
    /// The array is mNumAnimations in size.
    //  public var animations: [aiAnimation] {
    //      guard numberOfAnimations > 0 else {
    //          return []
    //      }

    //      let animations = (0..<numberOfAnimations)
    //          .compactMap { scene.mAnimations[$0] }
    //          .map { $0.pointee } // TODO: wrap animations

    //      assert(animations.count == numberOfAnimations)

    //      return animations
    //  }

    /// The number of textures embedded into the file
    public var numberOfTextures: Int

    /// The array of embedded textures.
    ///
    /// Not many file formats embed their textures into the file.
    /// An example is Quake's MDL format (which is also used by some GameStudio versions)
    public lazy var textures = UnsafeBufferPointer(
        start: scenePtr.pointee.mTextures, count: numberOfTextures
    ).compactMap { Texture($0?.pointee) }

    /// The number of light sources in the scene.
    /// Light sources are fully optional, in most cases this attribute will be 0.
    public var numberOfLights: Int

    /// The array of light sources.
    /// All light sources imported from the given file are listed here.
    /// The array is mNumLights in size.
    public lazy var lights: [Light] = UnsafeBufferPointer(
        start: scenePtr.pointee.mLights, count: numberOfLights
    ).compactMap { Light($0?.pointee) }

    /// The number of cameras in the scene.
    /// Cameras are fully optional, in most cases this attribute will be 0.
    public var numberOfCameras: Int

    /// The array of cameras.
    /// All cameras imported from the given file are listed here.
    /// The array is mNumCameras in size.
    /// The first camera in the array (if existing) is the default camera view into the scene.
    public lazy var cameras: [Camera] = UnsafeBufferPointer(
        start: scenePtr.pointee.mCameras, count: numberOfCameras
    ).compactMap { Camera($0?.pointee) }
}

extension Scene {
    @inlinable
    public func meshes(for node: Node) -> [Mesh] {
        node.meshes.map { meshes[$0] }
    }
}
