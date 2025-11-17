import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct SceneScriptMacro: MemberMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingMembersOf declaration: some DeclGroupSyntax,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {

    guard let classDecl = declaration.as(ClassDeclSyntax.self) else {
      throw SceneScriptMacroError("@SceneScript can only be applied to classes")
    }

    let className = classDecl.name.text

    // Verify the class inherits from Script
    let inheritsFromScript =
      classDecl.inheritanceClause?.inheritedTypes.contains { inheritedType in
        inheritedType.type.as(IdentifierTypeSyntax.self)?.name.text == "Script"
      } ?? false

    guard inheritsFromScript else {
      throw SceneScriptMacroError("@SceneScript classes must inherit from Script")
    }

    // Find all public instance methods (excluding inherited ones from Script base class)
    let methods = findSceneScriptMethods(in: classDecl)

    // Generate method registry
    let methodRegistry = generateMethodRegistry(className: className, methods: methods)

    // Generate availableMethods() static method
    let availableMethods = generateAvailableMethods(methods: methods)

    // Generate callMethod(named:) instance method
    let callMethod = generateCallMethod(className: className, methods: methods)

    // Generate static _register() method
    let registerMethod = generateRegisterMethod(className: className)

    // Generate static property initializer for automatic registration
    let autoRegister = generateAutoRegister(className: className)

    return [
      DeclSyntax(methodRegistry),
      DeclSyntax(availableMethods),
      DeclSyntax(callMethod),
      DeclSyntax(registerMethod),
      DeclSyntax(autoRegister),
    ]
  }

  // Find all instance methods in the class (excluding inherited ones)
  private static func findSceneScriptMethods(in classDecl: ClassDeclSyntax) -> [MethodInfo] {
    var methods: [MethodInfo] = []

    for member in classDecl.memberBlock.members {
      guard let functionDecl = member.decl.as(FunctionDeclSyntax.self) else { continue }

      // Skip static methods, private methods, and methods that start with underscore
      let modifiers = functionDecl.modifiers
      let isStatic = modifiers.contains { $0.name.text == "static" || $0.name.text == "class" }
      let isPrivate = modifiers.contains { $0.name.text == "private" || $0.name.text == "fileprivate" }

      guard !isStatic, !isPrivate else { continue }

      // Get method name
      let methodName = functionDecl.name.text

      // Skip methods that start with underscore (internal/private)
      guard !methodName.hasPrefix("_") else { continue }

      // Skip methods that start with uppercase (likely initializers or special methods)
      guard methodName.first?.isLowercase == true else { continue }

      // Check if method is async
      let isAsync = functionDecl.signature.effectSpecifiers?.asyncSpecifier != nil

      // Skip init, deinit, and override methods
      if methodName == "init" || methodName == "deinit" || modifiers.contains(where: { $0.name.text == "override" }) {
        continue
      }

      methods.append(MethodInfo(name: methodName, isAsync: isAsync))
    }

    return methods
  }

  // Generate method registry dictionary
  private static func generateMethodRegistry(className: String, methods: [MethodInfo]) -> VariableDeclSyntax {
    let registryEntries = methods.map { method in
      if method.isAsync {
        return "\"\(method.name)\": { instance in Task { await instance.\(method.name)() } }"
      } else {
        return "\"\(method.name)\": { instance in instance.\(method.name)() }"
      }
    }.joined(separator: ",\n    ")

    return try! VariableDeclSyntax(
      """
      private static let methodRegistry: [String: (\(raw: className)) -> Any] = [
        \(raw: registryEntries)
      ]
      """
    )
  }

  // Generate availableMethods() static method
  private static func generateAvailableMethods(methods: [MethodInfo]) -> FunctionDeclSyntax {
    let methodNames = methods.map { "\"\($0.name)\"" }.joined(separator: ", ")

    return try! FunctionDeclSyntax(
      """
      override class func availableMethods() -> [String] {
        return [\(raw: methodNames)]
      }
      """
    )
  }

  // Generate callMethod(named:) instance method
  private static func generateCallMethod(className: String, methods: [MethodInfo]) -> FunctionDeclSyntax {
    // Generate switch statement for method calling
    let cases = methods.map { method in
      if method.isAsync {
        return """
          case "\(method.name)":
            if let task = Self.methodRegistry["\(method.name)"]?(self) as? Task<Void, Never> {
              return task
            }
            return nil
          """
      } else {
        return """
          case "\(method.name)":
            _ = Self.methodRegistry["\(method.name)"]?(self)
            return nil
          """
      }
    }.joined(separator: "\n      ")

    return try! FunctionDeclSyntax(
      """
      override func callMethod(named methodName: String) -> Task<Void, Never>? {
        switch methodName {
        \(raw: cases)
        default:
          return nil
        }
      }
      """
    )
  }

  // Generate static _register() method
  private static func generateRegisterMethod(className: String) -> FunctionDeclSyntax {
    return try! FunctionDeclSyntax(
      """
      static func _register() {
        logger.trace("🔄 Registering \(raw: className)")
        ScriptRegistry.shared.register("\(raw: className)") {
          // Script now accesses scene and dialogView through MainLoop.shared
          return \(raw: className)()
        }
        logger.trace("✅ Registered \(raw: className)")
      }
      """
    )
  }

  // Generate static property initializer for automatic registration
  // This will be accessed when the class type is first referenced
  private static func generateAutoRegister(className: String) -> VariableDeclSyntax {
    return try! VariableDeclSyntax(
      """
      static let _autoRegister: Void = {
        _register()
      }()
      """
    )
  }
}

private struct SceneScriptMacroError: Error {
  let message: String
  init(_ message: String) {
    self.message = message
  }
}

private struct MethodInfo {
  let name: String
  let isAsync: Bool
}
