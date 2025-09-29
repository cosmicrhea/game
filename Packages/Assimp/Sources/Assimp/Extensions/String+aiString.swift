//
// String+aiString.swift
// SwiftAssimp
//
// Copyright © 2019-2022 Christian Treffs. All rights reserved.
// Licensed under BSD 3-Clause License. See LICENSE file for details.

@_implementationOnly import CAssimp

extension String {
    init?(_ aiString: aiString) {
        // aiString.data is already a C-string, just convert it directly
        guard aiString.length > 0 else {
            return nil
        }

        // aiString.data is a fixed-size array that contains the string data
        // We can treat it as a C-string by taking the address
        let cString = withUnsafePointer(to: aiString.data) { dataPtr in
            UnsafeRawPointer(dataPtr).assumingMemoryBound(to: CChar.self)
        }

        self.init(cString: cString)
    }

    init?(bytes: UnsafeMutablePointer<Int8>, length: Int) {
        let bufferPtr = UnsafeMutableBufferPointer(
            start: bytes,
            count: length)

        let codeUnits: [UTF8.CodeUnit] =
            bufferPtr
            // .map { $0 > 0 ? $0 : Int8(0x20) } // this replaces all invalid characters with blank space
            .map { UTF8.CodeUnit($0) }

        self.init(decoding: codeUnits, as: UTF8.self)
    }
}
