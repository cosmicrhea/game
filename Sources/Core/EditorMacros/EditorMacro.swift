import Collections
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

extension String {
  var titleCased: String {
    replacingOccurrences(of: #"(?<=[a-z])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])"#, with: " ", options: .regularExpression)
      .capitalized
  }
}

public struct EditorMacro: MemberMacro, ExtensionMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingMembersOf declaration: some DeclGroupSyntax,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {

    guard
      let typeName = declaration.as(ClassDeclSyntax.self)?.name.text ?? declaration.as(StructDeclSyntax.self)?.name.text
        ?? declaration.as(ActorDeclSyntax.self)?.name.text
    else {
      throw EditorMacroError("@Editor can only be applied to types (classes, structs, actors)")
    }

    // Extract grouping option from macro arguments
    let grouping = extractGroupingOption(from: node)

    // Find all @Editable properties
    let editableProperties = findEditableProperties(in: declaration)

    guard !editableProperties.isEmpty else {
      throw EditorMacroError("No @Editable properties found in \(typeName)")
    }

    // Generate the getEditableProperties method
    let method = generateGetEditablePropertiesMethod(properties: editableProperties, grouping: grouping)

    return [DeclSyntax(method)]
  }

  public static func expansion(
    of node: AttributeSyntax,
    attachedTo declaration: some DeclGroupSyntax,
    providingExtensionsOf type: some TypeSyntaxProtocol,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [ExtensionDeclSyntax] {

    guard
      declaration.as(ClassDeclSyntax.self) != nil || declaration.as(StructDeclSyntax.self) != nil
        || declaration.as(ActorDeclSyntax.self) != nil
    else {
      throw EditorMacroError("@Editor can only be applied to types (classes, structs, actors)")
    }

    // Check if the type already conforms to Editing
    let alreadyConforms =
      declaration.as(ClassDeclSyntax.self)?.inheritanceClause?.inheritedTypes.contains { inheritedType in
        inheritedType.type.as(IdentifierTypeSyntax.self)?.name.text == "Editing"
      } ?? false

    if alreadyConforms {
      return []
    }

    // Generate extension adding Editing conformance
    let extensionDecl = try ExtensionDeclSyntax(
      """
      extension \(type.trimmed): Editing {}
      """
    )

    return [extensionDecl]
  }

  private static func findEditableProperties(in declaration: DeclGroupSyntax) -> [EditablePropertyInfo] {
    var properties: [EditablePropertyInfo] = []

    for member in declaration.memberBlock.members {
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
            let displayName = extractDisplayName(from: attribute) ?? propertyName.titleCased
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

  private static func extractGroupingOption(from node: AttributeSyntax) -> Bool {
    guard let arguments = node.arguments?.as(LabeledExprListSyntax.self) else {
      return false
    }

    for argument in arguments {
      if let memberAccess = argument.expression.as(MemberAccessExprSyntax.self) {
        // Check for both EditorGrouping.grouped and .grouped
        let isGrouped = memberAccess.declName.baseName.text == "grouped"
        let hasEditorGroupingBase = memberAccess.base?.as(IdentifierTypeSyntax.self)?.name.text == "EditorGrouping"
        let hasNoBase = memberAccess.base == nil  // This handles .grouped syntax

        if isGrouped && (hasEditorGroupingBase || hasNoBase) {
          return true
        }
      }
    }

    return false
  }

  private static func generateGetEditablePropertiesMethod(properties: [EditablePropertyInfo], grouping: Bool)
    -> FunctionDeclSyntax
  {
    if grouping {
      return generateGroupedPropertiesMethod(properties: properties)
    } else {
      return generateUngroupedPropertiesMethod(properties: properties)
    }
  }

  private static func generateUngroupedPropertiesMethod(properties: [EditablePropertyInfo]) -> FunctionDeclSyntax {
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

    let functionDecl = try! FunctionDeclSyntax(
      """
      func getEditableProperties() -> [Any] {
        return [
          \(raw: returnStatements)
        ]
      }
      """)

    return functionDecl
  }

  private static func generateGroupedPropertiesMethod(properties: [EditablePropertyInfo]) -> FunctionDeclSyntax {
    // Group properties by their prefix (first word) while preserving order
    var groupedProperties = OrderedDictionary<String, [EditablePropertyInfo]>()

    for prop in properties {
      let words = prop.displayName.components(separatedBy: " ")
      let groupName = words.first ?? "Other"

      if groupedProperties[groupName] != nil {
        groupedProperties[groupName]!.append(prop)
      } else {
        groupedProperties[groupName] = [prop]
      }
    }

    let sections = groupedProperties.map { (groupName, props) in
      let sectionProperties = props.map { prop in
        let range = prop.range ?? "0.0...1.0"

        // Remove the group name prefix from the display name
        let words = prop.displayName.components(separatedBy: " ")
        let displayName = words.count > 1 ? words.dropFirst().joined(separator: " ") : prop.displayName

        return """
          AnyEditableProperty(
            name: "\(prop.name)",
            value: \(prop.name),
            setValue: { self.\(prop.name) = $0 as! \(prop.type) },
            displayName: "\(displayName)",
            validRange: \(range)
          )
          """
      }.joined(separator: ",\n        ")

      return """
        EditablePropertyGroup(
          name: "\(groupName)",
          properties: [
            \(sectionProperties)
          ]
        )
        """
    }.joined(separator: ",\n      ")

    let functionDecl = try! FunctionDeclSyntax(
      """
      func getEditableProperties() -> [Any] {
        return [
          \(raw: sections)
        ]
      }
      """)

    return functionDecl
  }
}

private struct EditorMacroError: Error {
  let message: String
  init(_ message: String) {
    self.message = message
  }
}

private struct EditablePropertyInfo {
  let name: String
  let type: String
  let displayName: String
  let range: String?
}
