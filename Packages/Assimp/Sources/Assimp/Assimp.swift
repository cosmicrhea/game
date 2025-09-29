//
// Assimp.swift
// SwiftAssimp
//
// Copyright © 2019-2022 Christian Treffs. All rights reserved.
// Licensed under BSD 3-Clause License. See LICENSE file for details.

import CAssimp

extension Scene {
    public static func canImportFileExtension(_ fileExtension: String) -> Bool {
        aiGetImporterDesc(fileExtension.lowercased()) != nil
    }

    public static func getImporterDescriptor(for fileExtension: String) -> ImporterDescription? {
        ImporterDescription(aiGetImporterDesc(fileExtension.lowercased())?.pointee)
    }

    public static func importFormats() -> [ImporterDescription] {
        let count = aiGetImportFormatCount()

        guard count > 0 else {
            return []
        }

        return (0..<count)
            .compactMap { ImporterDescription(aiGetImportFormatDescription($0)?.pointee) }
    }

    public static func importFileExtensions() -> [String] {
        importFormats().flatMap(\.fileExtensions).sorted()
    }

    public static func exportFormats() -> [ExporterDescription] {
        let count = aiGetExportFormatCount()

        guard count > 0 else {
            return []
        }

        return (0..<count)
            .compactMap { ExporterDescription(aiGetExportFormatDescription($0)?.pointee) }
    }

    public static func exportFileExtensions() -> [String] {
        exportFormats().map(\.fileExtension).sorted()
    }
}

public struct ImporterDescription: Equatable {
    public let name: String
    public let author: String
    public let maintainer: String
    public let comments: String
    public let flags: ImporterFlags
    public let major: Range<Int>
    public let minor: Range<Int>
    public let fileExtensions: [String]

    init(_ desc: aiImporterDesc) {
        name = String(cString: desc.mName)
        author = String(cString: desc.mAuthor)
        maintainer = String(cString: desc.mMaintainer)
        comments = String(cString: desc.mComments)
        flags = ImporterFlags(rawValue: desc.mFlags)
        major = Range<Int>(
            uncheckedBounds: (lower: Int(desc.mMinMajor), upper: Int(desc.mMaxMajor)))
        minor = Range<Int>(
            uncheckedBounds: (lower: Int(desc.mMinMinor), upper: Int(desc.mMaxMinor)))
        fileExtensions = String(cString: desc.mFileExtensions).split(separator: " ").map(
            String.init)
    }

    init?(_ desc: aiImporterDesc?) {
        guard let desc = desc else {
            return nil
        }
        self.init(desc)
    }
}

public struct ImporterFlags: Equatable, RawRepresentable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let supportTextFlavour = ImporterFlags(
        rawValue: aiImporterFlags_SupportTextFlavour.rawValue)
    public static let supportBinaryFlavour = ImporterFlags(
        rawValue: aiImporterFlags_SupportBinaryFlavour.rawValue)
    public static let supportCompressedFlavour = ImporterFlags(
        rawValue: aiImporterFlags_SupportCompressedFlavour.rawValue)
    public static let limitedSupport = ImporterFlags(
        rawValue: aiImporterFlags_LimitedSupport.rawValue)
    public static let experimental = ImporterFlags(rawValue: aiImporterFlags_Experimental.rawValue)
}

public struct ExporterDescription: Equatable {
    public let id: String
    public let description: String
    public let fileExtension: String

    init(_ desc: aiExportFormatDesc) {
        id = String(cString: desc.id)
        description = String(cString: desc.description)
        fileExtension = String(cString: desc.fileExtension)
    }

    init?(_ desc: aiExportFormatDesc?) {
        guard let desc = desc else {
            return nil
        }
        self.init(desc)
    }
}
