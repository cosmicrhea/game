import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

public struct EditablePropertiesMacro: MemberMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingMembersOf declaration: some DeclGroupSyntax,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {

    guard let classDecl = declaration.as(ClassDeclSyntax.self) else {
      throw MacroError("@EditableProperties can only be applied to classes")
    }

    let className = classDecl.name.text

    // Find all @Editable properties
    let editableProperties = findEditableProperties(in: classDecl)

    guard !editableProperties.isEmpty else {
      throw MacroError("No @Editable properties found in class \(className)")
    }

    // Generate the getEditableProperties method
    let method = generateGetEditablePropertiesMethod(properties: editableProperties)

    return [DeclSyntax(method)]
  }

  private static func findEditableProperties(in classDecl: ClassDeclSyntax) -> [EditablePropertyInfo] {
    var properties: [EditablePropertyInfo] = []

    for member in classDecl.memberBlock.members {
      if let variableDecl = member.decl.as(VariableDeclSyntax.self) {
        for binding in variableDecl.bindings {
          if let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
            let type = binding.typeAnnotation?.type,
            let attribute = variableDecl.attributes.first?.as(AttributeSyntax.self),
            attribute.attributeName.as(IdentifierTypeSyntax.self)?.name.text == "Editable"
          {

            let propertyName = pattern.identifier.text
            let propertyType = type.description.trimmingCharacters(in: .whitespacesAndNewlines)

            // Extract display name and range from attribute arguments
            let displayName = extractDisplayName(from: attribute) ?? propertyName.capitalized
            let range = extractRange(from: attribute)

            properties.append(
              EditablePropertyInfo(
                name: propertyName,
                type: propertyType,
                displayName: displayName,
                range: range
              ))
          }
        }
      }
    }

    return properties
  }

  private static func extractDisplayName(from attribute: AttributeSyntax) -> String? {
    if let argumentList = attribute.arguments?.as(LabeledExprListSyntax.self) {
      for arg in argumentList {
        if let label = arg.label?.text, label == "displayName",
          let stringLiteral = arg.expression.as(StringLiteralExprSyntax.self)
        {
          return stringLiteral.segments.first?.as(StringSegmentSyntax.self)?.content.text
        }
      }
    }
    return nil
  }

  private static func extractRange(from attribute: AttributeSyntax) -> String? {
    if let argumentList = attribute.arguments?.as(LabeledExprListSyntax.self) {
      for arg in argumentList {
        if let label = arg.label?.text, label == "range" {
          return arg.expression.description
        }
      }
    }
    return nil
  }

  private static func generateGetEditablePropertiesMethod(properties: [EditablePropertyInfo]) -> FunctionDeclSyntax {
    let returnStatements = properties.map { prop in
      let range = prop.range ?? "0.0...1.0"

      return """
        AnyEditableProperty(
          name: "\(prop.name)",
          value: \(prop.name),
          setValue: { self.\(prop.name) = $0 as! \(prop.type) },
          displayName: "\(prop.displayName)",
          validRange: \(range)
        )
        """
    }.joined(separator: ",\n      ")

    // Create the function declaration using SwiftSyntaxBuilder
    let functionDecl = try! FunctionDeclSyntax(
      """
      func getEditableProperties() -> [AnyEditableProperty] {
        return [
          \(raw: returnStatements)
        ]
      }
      """)

    return functionDecl
  }
}

private struct EditablePropertyInfo {
  let name: String
  let type: String
  let displayName: String
  let range: String?
}

private struct MacroError: Error {
  let message: String
  init(_ message: String) {
    self.message = message
  }
}
