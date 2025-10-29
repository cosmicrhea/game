import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Macro that generates accessors for `@ConfigValue` properties, using ConfigStore automatically.
/// Usage: `@ConfigValue var editorEnabled = false` or `@ConfigValue("customKey") var property = defaultValue`
/// If no key is provided, uses the property name as the key.
public struct ConfigMacro: AccessorMacro, PeerMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingAccessorsOf declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext
  ) throws -> [AccessorDeclSyntax] {
    guard let variableDecl = declaration.as(VariableDeclSyntax.self),
      let binding = variableDecl.bindings.first,
      let identifier = binding.pattern.as(IdentifierPatternSyntax.self)
    else {
      throw ConfigMacroError("@ConfigValue can only be applied to variable declarations")
    }

    let propertyName = identifier.identifier.text

    // Extract key from macro arguments, or use property name as default
    let key = extractKey(from: node) ?? propertyName

    // Get the default value from the initializer (required)
    guard let initializer = binding.initializer else {
      throw ConfigMacroError("@ConfigValue requires an initializer value (e.g., `= false` or `= 0`)")
    }

    let defaultValue = initializer.value.trimmed

    // Generate getter and setter accessors
    let getter = AccessorDeclSyntax(
      """
      get {
        ConfigStore.shared.get("\(raw: key)", default: \(defaultValue))
      }
      """
    )

    let setter = AccessorDeclSyntax(
      """
      set {
        ConfigStore.shared.set("\(raw: key)", value: newValue)
      }
      """
    )

    return [getter, setter]
  }

  public static func expansion(
    of node: AttributeSyntax,
    providingPeersOf declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    // We don't need to generate peers - the accessors handle everything
    return []
  }

  private static func extractKey(from attribute: AttributeSyntax) -> String? {
    guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self),
      !arguments.isEmpty
    else {
      return nil
    }

    // Check for positional argument: @ConfigValue("key")
    if let firstArg = arguments.first, firstArg.label == nil {
      if let stringLiteral = firstArg.expression.as(StringLiteralExprSyntax.self),
        let key = stringLiteral.segments.first?.as(StringSegmentSyntax.self)?.content.text,
        !key.isEmpty
      {
        return key
      }
    }

    // Check for labeled argument: @ConfigValue(key: "key")
    for arg in arguments {
      if arg.label?.text == "key",
        let stringLiteral = arg.expression.as(StringLiteralExprSyntax.self),
        let key = stringLiteral.segments.first?.as(StringSegmentSyntax.self)?.content.text,
        !key.isEmpty
      {
        return key
      }
    }

    return nil
  }
}

private struct ConfigMacroError: Error {
  let message: String
  init(_ message: String) {
    self.message = message
  }
}
