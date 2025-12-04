#!/usr/bin/env swift

import Foundation

struct XCStrings: Codable {
  let sourceLanguage: String
  let strings: [String: StringEntry]
  let version: String?

  struct StringEntry: Codable {
    let localizations: [String: Localization]?

    struct Localization: Codable {
      let stringUnit: StringUnit?

      struct StringUnit: Codable {
        let state: String?
        let value: String
      }
    }
  }
}

func convertXCStringsToPlist(inputPath: String, outputDir: String) throws {
  let inputURL = URL(fileURLWithPath: inputPath)
  let outputDirURL = URL(fileURLWithPath: outputDir)

  // Read and parse the xcstrings file
  let data = try Data(contentsOf: inputURL)
  let xcstrings = try JSONDecoder().decode(XCStrings.self, from: data)

  // Collect all languages (including source language)
  var languages: Set<String> = [xcstrings.sourceLanguage]

  // Extract all languages from localizations
  for (_, entry) in xcstrings.strings {
    if let localizations = entry.localizations {
      for lang in localizations.keys {
        languages.insert(lang)
      }
    }
  }

  // Generate .strings plist file for each language
  for language in languages {
    let lprojDir = outputDirURL.appendingPathComponent("\(language).lproj")
    try FileManager.default.createDirectory(at: lprojDir, withIntermediateDirectories: true)

    let stringsFile = lprojDir.appendingPathComponent("Localizable.strings")

    // Build the dictionary of strings for this language
    var stringsDict: [String: String] = [:]

    for (key, entry) in xcstrings.strings {
      var value: String? = nil

      // Check if there's a localization for this language
      if let localizations = entry.localizations,
        let localization = localizations[language],
        let stringUnit = localization.stringUnit
      {
        value = stringUnit.value
      } else if language == xcstrings.sourceLanguage {
        // Use the key itself as the value for source language if no explicit localization
        value = key
      }

      // If we found a value, add it to the dictionary
      if let value = value {
        stringsDict[key] = value
      }
    }

    // Generate the plist XML
    let plistXML = generatePlistXML(from: stringsDict)

    // Write to file
    try plistXML.write(to: stringsFile, atomically: true, encoding: .utf8)

    print("Generated \(language).lproj/Localizable.strings with \(stringsDict.count) strings")
  }
}

func generatePlistXML(from dict: [String: String]) -> String {
  var xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
    """

  // Sort keys for consistent output
  for key in dict.keys.sorted() {
    let value = dict[key]!
    // Escape XML special characters
    let escapedKey = escapeXML(key)
    let escapedValue = escapeXML(value)
    xml += "\t<key>\(escapedKey)</key>\n"
    xml += "\t<string>\(escapedValue)</string>\n"
  }

  xml += "</dict>\n</plist>\n"
  return xml
}

func escapeXML(_ string: String) -> String {
  return
    string
    .replacingOccurrences(of: "&", with: "&amp;")
    .replacingOccurrences(of: "<", with: "&lt;")
    .replacingOccurrences(of: ">", with: "&gt;")
    .replacingOccurrences(of: "\"", with: "&quot;")
    .replacingOccurrences(of: "'", with: "&apos;")
}

// Main execution
guard CommandLine.arguments.count >= 3 else {
  print("Usage: ConvertXCStrings.swift <input.xcstrings> <output_directory>")
  exit(1)
}

let inputPath = CommandLine.arguments[1]
let outputDir = CommandLine.arguments[2]

do {
  try convertXCStringsToPlist(inputPath: inputPath, outputDir: outputDir)
  print("✓ Successfully converted xcstrings to .strings plist files")
} catch {
  print("✗ Error: \(error)")
  exit(1)
}
