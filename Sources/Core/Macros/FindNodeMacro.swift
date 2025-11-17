import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Macro that automatically finds a node from the scene and stores it.
/// Usage: `@FindNode var catStatue: Node!` or `@FindNode("StatueOfCat") var catStatue: Node!`
/// If no node name is provided, converts the property name to PascalCase (e.g., "catStatue" -> "CatStatue").
public struct FindNodeMacro: AccessorMacro, PeerMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingAccessorsOf declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext
  ) throws -> [AccessorDeclSyntax] {
    guard let variableDecl = declaration.as(VariableDeclSyntax.self),
      let binding = variableDecl.bindings.first,
      let identifier = binding.pattern.as(IdentifierPatternSyntax.self)
    else {
      throw FindNodeMacroError("@FindNode can only be applied to variable declarations")
    }

    let propertyName = identifier.identifier.text

    // Extract node name from macro arguments, or convert property name to PascalCase
    let nodeName = extractNodeName(from: node) ?? propertyNameToPascalCase(propertyName)

    // Generate backing storage property name
    let backingStorageName = "_\(propertyName)"

    // Generate getter that finds the node if not already found
    let getter = AccessorDeclSyntax(
      """
      get {
        if \(raw: backingStorageName) == nil {
          guard let foundNode = findNode("\(raw: nodeName)") else {
            fatalError("Node '\(raw: nodeName)' not found in scene")
          }
          \(raw: backingStorageName) = foundNode
        }
        return \(raw: backingStorageName)!
      }
      """
    )

    // Generate setter
    let setter = AccessorDeclSyntax(
      """
      set {
        \(raw: backingStorageName) = newValue
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
    guard let variableDecl = declaration.as(VariableDeclSyntax.self),
      let binding = variableDecl.bindings.first,
      let identifier = binding.pattern.as(IdentifierPatternSyntax.self)
    else {
      return []
    }

    let propertyName = identifier.identifier.text
    let backingStorageName = "_\(propertyName)"

    // Generate private backing storage property
    let backingStorage = try VariableDeclSyntax(
      """
      private var \(raw: backingStorageName): Node?
      """
    )

    return [DeclSyntax(backingStorage)]
  }

  private static func extractNodeName(from attribute: AttributeSyntax) -> String? {
    // If no arguments, return nil to use property name
    guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self),
      !arguments.isEmpty
    else {
      return nil
    }

    // Check for positional argument: @FindNode("NodeName")
    if let firstArg = arguments.first, firstArg.label == nil {
      if let stringLiteral = firstArg.expression.as(StringLiteralExprSyntax.self),
        let nodeName = stringLiteral.segments.first?.as(StringSegmentSyntax.self)?.content.text,
        !nodeName.isEmpty
      {
        return nodeName
      }
      // If it's an empty string literal, treat as no argument
      if firstArg.expression.as(StringLiteralExprSyntax.self) != nil {
        return nil
      }
    }

    // Check for labeled argument: @FindNode(name: "NodeName")
    for arg in arguments {
      if arg.label?.text == "name",
        let stringLiteral = arg.expression.as(StringLiteralExprSyntax.self),
        let nodeName = stringLiteral.segments.first?.as(StringSegmentSyntax.self)?.content.text,
        !nodeName.isEmpty
      {
        return nodeName
      }
    }

    return nil
  }

  private static func propertyNameToPascalCase(_ propertyName: String) -> String {
    guard !propertyName.isEmpty else { return propertyName }
    let firstChar = propertyName.prefix(1).uppercased()
    let rest = propertyName.dropFirst()
    return firstChar + rest
  }
}

private struct FindNodeMacroError: Error {
  let message: String
  init(_ message: String) {
    self.message = message
  }
}
