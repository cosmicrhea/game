import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct GlassMacrosPlugin: CompilerPlugin {
  let providingMacros: [Macro.Type] = [
    EditablePropertiesMacro.self
  ]
}
