import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Macro that generates flag-backed getters/setters using ScriptFlagStore.
/// Usage: `@Flag var hasReadLaptop = false` or `@Flag("customKey") var hasReadLaptop = false`
public struct FlagMacro: AccessorMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingAccessorsOf declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext
  ) throws -> [AccessorDeclSyntax] {
    guard let variableDecl = declaration.as(VariableDeclSyntax.self),
      variableDecl.bindingSpecifier.tokenKind == .keyword(.var),
      let binding = variableDecl.bindings.first,
      binding.accessorBlock == nil,
      let identifier = binding.pattern.as(IdentifierPatternSyntax.self)
    else {
      throw FlagMacroError("@Flag can only be applied to stored var properties")
    }

    guard let initializer = binding.initializer else {
      throw FlagMacroError("@Flag requires a default value (e.g., `= false`)")
    }

    let propertyName = identifier.identifier.text
    let keySuffix = extractName(from: node) ?? propertyName
    let defaultValue = initializer.value.trimmed

    let getter = AccessorDeclSyntax(
      """
      get {
        readFlag("\(raw: keySuffix)", default: \(defaultValue))
      }
      """
    )

    let setter = AccessorDeclSyntax(
      """
      set {
        writeFlag(newValue, name: "\(raw: keySuffix)")
      }
      """
    )

    return [getter, setter]
  }

  private static func extractName(from attribute: AttributeSyntax) -> String? {
    guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self),
      !arguments.isEmpty
    else {
      return nil
    }

    if let firstArg = arguments.first, firstArg.label == nil {
      if let stringLiteral = firstArg.expression.as(StringLiteralExprSyntax.self),
        let key = stringLiteral.segments.first?.as(StringSegmentSyntax.self)?.content.text,
        !key.isEmpty
      {
        return key
      }
    }

    for argument in arguments {
      if argument.label?.text == "name",
        let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self),
        let key = stringLiteral.segments.first?.as(StringSegmentSyntax.self)?.content.text,
        !key.isEmpty
      {
        return key
      }
    }

    return nil
  }
}

private struct FlagMacroError: Error {
  let message: String
  init(_ message: String) {
    self.message = message
  }
}

