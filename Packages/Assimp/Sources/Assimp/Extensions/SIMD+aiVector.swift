//
// simd+aiVector.swift
// SwiftAssimp
//
// Copyright © 2019-2022 Christian Treffs. All rights reserved.
// Licensed under BSD 3-Clause License. See LICENSE file for details.

@_implementationOnly import CAssimp

extension aiVector3D {
    @_transparent var vector: SIMD3<Float> {
        SIMD3<Float>(x, y, z)
    }
}

extension aiVector2D {
    @_transparent var vector: SIMD2<Float> {
        SIMD2<Float>(x, y)
    }
}

extension SIMD3 where Scalar == Float {
    @_transparent init(_ aiVector3D: aiVector3D) {
        self.init(aiVector3D.x, aiVector3D.y, aiVector3D.z)
    }

    @_transparent init(_ aiColor3D: aiColor3D) {
        self.init(aiColor3D.r, aiColor3D.g, aiColor3D.b)
    }
}

extension SIMD2 where Scalar == Float {
    @_transparent init(_ aiVector2D: aiVector2D) {
        self.init(aiVector2D.x, aiVector2D.y)
    }
}

public typealias AssimpVec2 = SIMD2<Float>
public typealias AssimpVec3 = SIMD3<Float>

public typealias AssimpReal = Float

public struct Matrix4x4 {
    public let a1: AssimpReal
    public let a2: AssimpReal
    public let a3: AssimpReal
    public let a4: AssimpReal
    public let b1: AssimpReal
    public let b2: AssimpReal
    public let b3: AssimpReal
    public let b4: AssimpReal
    public let c1: AssimpReal
    public let c2: AssimpReal
    public let c3: AssimpReal
    public let c4: AssimpReal
    public let d1: AssimpReal
    public let d2: AssimpReal
    public let d3: AssimpReal
    public let d4: AssimpReal

    init(_ m: aiMatrix4x4) {
        a1 = m.a1
        a2 = m.a2
        a3 = m.a3
        a4 = m.a4
        b1 = m.b1
        b2 = m.b2
        b3 = m.b3
        b4 = m.b4
        c1 = m.c1
        c2 = m.c2
        c3 = m.c3
        c4 = m.c4
        d1 = m.d1
        d2 = m.d2
        d3 = m.d3
        d4 = m.d4
    }
}
