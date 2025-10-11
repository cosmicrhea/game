import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct EditorMacrosPlugin: CompilerPlugin {
  let providingMacros: [Macro.Type] = [
    EditorMacro.self
  ]
}
