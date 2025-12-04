import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Macro that automatically finds a node or camera from the scene and stores it.
/// Usage: `@Ref var catStatue: Node!` or `@Ref("StatueOfCat") var catStatue: Node!`
/// Usage: `@Ref var desk: Camera` or `@Ref("desk") var desk: Camera`
/// If no name is provided, converts the property name to PascalCase (e.g., "catStatue" -> "CatStatue").
public struct RefMacro: AccessorMacro, PeerMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingAccessorsOf declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext
  ) throws -> [AccessorDeclSyntax] {
    guard let variableDecl = declaration.as(VariableDeclSyntax.self),
      let binding = variableDecl.bindings.first,
      let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
      let typeAnnotation = binding.typeAnnotation
    else {
      throw RefMacroError("@Ref can only be applied to variable declarations")
    }

    let propertyName = identifier.identifier.text
    let typeName = extractTypeName(from: typeAnnotation.type)

    // Generate backing storage property name
    let backingStorageName = "_\(propertyName)"

    // Determine if this is a Camera or Node
    let isCamera = typeName == "Camera" || typeName.hasSuffix(".Camera")

    // Extract name from macro arguments, or derive from property name
    let rawName: String
    if let explicitName = extractNodeName(from: node) {
      rawName = explicitName
    } else if isCamera {
      // For cameras, use property name as-is (lowercase) instead of PascalCase
      rawName = propertyName
    } else {
      // For nodes, convert to PascalCase
      rawName = propertyNameToPascalCase(propertyName)
    }

    let searchName: String
    let findMethod: String
    let errorMessage: String
    if isCamera {
      // For cameras, convert to Camera_X format if needed
      let cameraNodeName = rawName.hasPrefix("Camera_") ? rawName : "Camera_\(rawName)"
      searchName = cameraNodeName
      findMethod = "findCamera"
      errorMessage = "Camera"
    } else {
      searchName = rawName
      findMethod = "findNode"
      errorMessage = "Node"
    }

    // Generate getter that finds the object if not already found
    let getter = AccessorDeclSyntax(
      """
      get {
        if \(raw: backingStorageName) == nil {
          guard let found = \(raw: findMethod)("\(raw: searchName)") else {
            fatalError("\(raw: errorMessage) '\(raw: searchName)' not found in scene")
          }
          \(raw: backingStorageName) = found
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
      let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
      let typeAnnotation = binding.typeAnnotation
    else {
      return []
    }

    let propertyName = identifier.identifier.text
    let backingStorageName = "_\(propertyName)"
    let typeName = extractTypeName(from: typeAnnotation.type)

    // Determine the storage type (Camera? or Node?)
    let storageType: String
    if typeName == "Camera" || typeName.hasSuffix(".Camera") {
      storageType = "Assimp.Camera"
    } else {
      storageType = "Node"
    }

    // Generate private backing storage property
    let backingStorage = try VariableDeclSyntax(
      """
      private var \(raw: backingStorageName): \(raw: storageType)?
      """
    )

    return [DeclSyntax(backingStorage)]
  }

  private static func extractTypeName(from type: TypeSyntax) -> String {
    if let identifierType = type.as(IdentifierTypeSyntax.self) {
      return identifierType.name.text
    } else if let memberType = type.as(MemberTypeSyntax.self) {
      return "\(memberType.baseType.trimmed).\(memberType.name.text)"
    } else if let optionalType = type.as(OptionalTypeSyntax.self) {
      return extractTypeName(from: optionalType.wrappedType)
    } else if let implicitlyUnwrappedType = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
      return extractTypeName(from: implicitlyUnwrappedType.wrappedType)
    }
    return ""
  }

  private static func extractNodeName(from attribute: AttributeSyntax) -> String? {
    // If no arguments, return nil to use property name
    guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self),
      !arguments.isEmpty
    else {
      return nil
    }

    // Check for positional argument: @Ref("NodeName")
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

    // Check for labeled argument: @Ref(name: "NodeName")
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

private struct RefMacroError: Error {
  let message: String
  init(_ message: String) {
    self.message = message
  }
}
