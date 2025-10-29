import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct MacrosPlugin: CompilerPlugin {
  let providingMacros: [Macro.Type] = [
    EditorMacro.self,
    EditableOptionsMacro.self,
    ConfigMacro.self,
  ]
}
