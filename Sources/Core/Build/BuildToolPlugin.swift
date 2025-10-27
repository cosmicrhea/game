import Foundation
import PackagePlugin

@main
struct BuildToolPlugin: PackagePlugin.BuildToolPlugin {
  func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
    let outputFile = context.pluginWorkDirectoryURL.appendingPathComponent("Version.swift")
    let scriptFile = context.pluginWorkDirectoryURL.appendingPathComponent("generate_version.sh")

    // Create a shell script that will work better with Xcode
    let scriptContent = """
      #!/bin/sh
      set -e

      # Get git commit count
      COMMIT_COUNT=$(git rev-list --count HEAD 2>/dev/null || echo "0")

      # Generate version information
      MAJOR_VERSION=0
      MINOR_VERSION=$COMMIT_COUNT
      VERSION_STRING="$MAJOR_VERSION.$MINOR_VERSION"

      # Generate the Swift file
      cat > "\(outputFile.path)" << EOF
      // Auto-generated version information
      // Generated on: $(date)
      // Commit count: $COMMIT_COUNT

      extension Engine {
          public static let versionMajor = $MAJOR_VERSION
          public static let versionMinor = $MINOR_VERSION
          public static let versionPatch = 0
          
          public static let versionString = "$VERSION_STRING"
          public static let versionFullString = "$VERSION_STRING.0"
          
          public static let commitCount = $COMMIT_COUNT
      }
      EOF

      echo "Generated version: $VERSION_STRING (commit count: $COMMIT_COUNT)"
      """

    // Write the script to a temporary file
    try scriptContent.write(to: scriptFile, atomically: true, encoding: .utf8)

    return [
      .buildCommand(
        displayName: "Generate Version Information",
        executable: URL(fileURLWithPath: "/bin/sh"),
        arguments: [scriptFile.path],
        outputFiles: [outputFile]
      )
    ]
  }
}
