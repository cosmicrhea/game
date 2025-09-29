//
// AiFace.swift
// SwiftAssimp
//
// Copyright © 2019-2022 Christian Treffs. All rights reserved.
// Licensed under BSD 3-Clause License. See LICENSE file for details.

import CAssimp

/// The default face winding order is counter clockwise (CCW).
public class Face {
    public init(_ face: aiFace) {
        let count = Int(face.mNumIndices)
        numberOfIndices = count
        guard count > 0, let ptr = face.mIndices else {
            indices = []
            return
        }
        indices = (0..<count).map { ptr[$0] }
    }

    public convenience init?(_ face: aiFace?) {
        guard let face = face else {
            return nil
        }
        self.init(face)
    }

    /// Number of indices defining this face.
    ///
    /// The maximum value for this member is #AI_MAX_FACE_INDICES.
    public var numberOfIndices: Int

    /// Pointer to the indices array.
    /// Size of the array is given in numberOfIndices.
    public var indices: [UInt32]
}
