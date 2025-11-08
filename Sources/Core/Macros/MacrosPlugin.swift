import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct MacrosPlugin: CompilerPlugin {
  let providingMacros: [Macro.Type] = [
    EditableMacro.self,
    EditorFunctionMacro.self,
    ConfigMacro.self,
  ]
}
