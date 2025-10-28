#!/usr/bin/env swift
import Foundation

let executableName = "Game"
let resourceBundleName = "Game_Glass.bundle"
let buildDir = URL(fileURLWithPath: ".build/release", isDirectory: true)

struct Target {
    let name: String
    let binaryPath: URL
}

// Helper to run a shell command and return output
func runCommand(_ launchPath: String, _ args: [String]) -> String? {
    let task = Process()
    task.launchPath = launchPath
    task.arguments = args

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = Pipe()

    do {
        try task.run()
        task.waitUntilExit()
    } catch {
        return nil
    }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard !data.isEmpty else { return nil }
    return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}

func buildVersionString() -> (short: String, full: String) {
    if let countStr = runCommand("/usr/bin/git", ["rev-list", "--count", "HEAD"]),
       let countInt = Int(countStr) {
        let short = "0.\(countInt)"
        return (short, short)
    }
    return ("0.0", "0.0")
}

let fileManager = FileManager.default
let versionInfo = buildVersionString()

let executablePath = buildDir.appendingPathComponent(executableName)
guard fileManager.fileExists(atPath: executablePath.path) else {
    print("could not find executable at \(executablePath.path)")
    exit(1)
}
let target = Target(name: executableName, binaryPath: executablePath)

print("💄 bundling \(target.name)...")
let appBundle = URL(fileURLWithPath: "\(target.name).app")
let contentsDirectory = appBundle.appendingPathComponent("Contents", isDirectory: true)
let macosDirectory = contentsDirectory.appendingPathComponent("MacOS", isDirectory: true)
let resourcesDirectory = contentsDirectory.appendingPathComponent("Resources", isDirectory: true)

// reset output directory if it exists
try? fileManager.removeItem(at: appBundle)

try fileManager.createDirectory(at: macosDirectory, withIntermediateDirectories: true)
try fileManager.createDirectory(at: resourcesDirectory, withIntermediateDirectories: true)

// copy binary
let binaryDestination = macosDirectory.appendingPathComponent(target.name)
try fileManager.copyItem(at: target.binaryPath, to: binaryDestination)

// copy icon if present
let sourceIcon = URL(fileURLWithPath: "Assets/UI/AppIcon/icon.icns")
if fileManager.fileExists(atPath: sourceIcon.path) {
    let iconDestination = resourcesDirectory.appendingPathComponent("AppIcon.icns")
    try? fileManager.copyItem(at: sourceIcon, to: iconDestination)
    print("  💫 copied application icon")
}

// copy SwiftPM resources if any
let resourceBundle = buildDir.appendingPathComponent(resourceBundleName)
if fileManager.fileExists(atPath: resourceBundle.path) {
    let destination = resourcesDirectory.appendingPathComponent(resourceBundleName)
    try fileManager.copyItem(at: resourceBundle, to: destination)
    print("  💫 copied resources to: \(destination.path)")

    // remove .blend and .blend1 files from assets
    let assetPath = resourcesDirectory.appendingPathComponent(resourceBundleName)
    if let enumerator = fileManager.enumerator(at: assetPath, includingPropertiesForKeys: nil) {
        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension == "blend" || fileURL.pathExtension == "blend1" {
                try? fileManager.removeItem(at: fileURL)
                print("  🧹 removed \(fileURL.lastPathComponent)")
            }
        }
    }
}

// write Info.plist
let plist = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>\(target.name)</string>
  <key>CFBundleExecutable</key><string>\(target.name)</string>
  <key>CFBundleIdentifier</key><string>local.cosmicrhea.\(target.name)</string>
  <key>CFBundleIconFile</key><string>AppIcon.icns</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>\(versionInfo.short)</string>
  <key>CFBundleVersion</key><string>\(versionInfo.full)</string>
  <key>NSHumanReadableCopyright</key><string>© 2025 cosmic_rhea</string>
</dict>
</plist>
"""

let plistURL = contentsDirectory.appendingPathComponent("Info.plist")
try plist.write(to: plistURL, atomically: true, encoding: .utf8)

print("✨ created \(appBundle.lastPathComponent)")
