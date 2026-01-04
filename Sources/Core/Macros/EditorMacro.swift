import Collections
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

extension String {
  private static let acronyms = [
    "SDF",
    "UI",
  ]

  public var titleCased: String {
    let spaced = replacingOccurrences(
      of: #"(?<=[a-z])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])"#,
      with: " ",
      options: .regularExpression
    )
    let capitalized = spaced.capitalized

    return capitalized.components(separatedBy: " ").map { word in
      let uppercased = word.uppercased()
      if Self.acronyms.contains(uppercased) {
        return uppercased
      }
      return word
    }.joined(separator: " ")
  }
}

public struct EditableMacro: MemberMacro, ExtensionMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingMembersOf declaration: some DeclGroupSyntax,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {

    guard
      let typeName = declaration.as(ClassDeclSyntax.self)?.name.text ?? declaration.as(StructDeclSyntax.self)?.name.text
        ?? declaration.as(ActorDeclSyntax.self)?.name.text
    else {
      throw EditableMacroError("@Editable can only be applied to types (classes, structs, actors)")
    }

    // Extract grouping option from macro arguments
    let grouping = extractGroupingOption(from: node)

    // Find all @Editor properties and functions
    let editorProperties = findEditorProperties(in: declaration)
    let editorFunctions = findEditorFunctions(in: declaration)

    guard !editorProperties.isEmpty || !editorFunctions.isEmpty else {
      throw EditableMacroError("No @Editor properties or functions found in \(typeName)")
    }

    // Generate the getEditableProperties method
    let method = generateGetEditablePropertiesMethod(
      properties: editorProperties, functions: editorFunctions, grouping: grouping)

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
      throw EditableMacroError("@Editable can only be applied to types (classes, structs, actors)")
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

  private static func findEditorProperties(in declaration: DeclGroupSyntax) -> [EditorPropertyInfo] {
    var properties: [EditorPropertyInfo] = []

    for member in declaration.memberBlock.members {
      if let variableDecl = member.decl.as(VariableDeclSyntax.self) {
        for binding in variableDecl.bindings {
          if let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
            let attribute = variableDecl.attributes.first?.as(AttributeSyntax.self),
            attribute.attributeName.as(IdentifierTypeSyntax.self)?.name.text == "Editor"
          {

            let propertyName = pattern.identifier.text
            // Prefer explicit type annotation; otherwise try to infer from initializer (handles e.g. Light.itemInspection)
            var propertyType: String = "Any"
            if let annotated = binding.typeAnnotation?.type {
              propertyType = annotated.description.trimmingCharacters(in: .whitespacesAndNewlines)
            } else if let initExpr = binding.initializer?.value.as(MemberAccessExprSyntax.self) {
              if let base = initExpr.base?.as(DeclReferenceExprSyntax.self) {
                propertyType = base.baseName.text
              }
            }

            // Extract display name and range from attribute arguments
            let displayName = extractDisplayName(from: attribute) ?? propertyName.titleCased
            let range = extractRange(from: attribute)

            properties.append(
              EditorPropertyInfo(
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

  private static func findEditorFunctions(in declaration: DeclGroupSyntax) -> [EditorFunctionInfo] {
    var functions: [EditorFunctionInfo] = []

    for member in declaration.memberBlock.members {
      if let functionDecl = member.decl.as(FunctionDeclSyntax.self) {
        // Check if function has @Editor attribute
        for attribute in functionDecl.attributes {
          if let attributeSyntax = attribute.as(AttributeSyntax.self),
            attributeSyntax.attributeName.as(IdentifierTypeSyntax.self)?.name.text == "Editor"
          {
            let functionName = functionDecl.name.text

            // Extract display name from attribute arguments
            let displayName = extractDisplayName(from: attributeSyntax) ?? functionName.titleCased

            // Only support functions with no parameters for now
            let hasParameters = functionDecl.signature.parameterClause.parameters.count > 0
            if hasParameters {
              // Skip functions with parameters for now
              continue
            }

            functions.append(
              EditorFunctionInfo(
                name: functionName,
                displayName: displayName
              ))
          }
        }
      }
    }

    return functions
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
        // Support both labeled and unlabeled range arguments
        if arg.label == nil || arg.label?.text == "range" {
          // Check if it's a range expression (contains "...")
          let exprStr = arg.expression.description
          if exprStr.contains("...") {
            return exprStr
          }
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

  private static func generateGetEditablePropertiesMethod(
    properties: [EditorPropertyInfo], functions: [EditorFunctionInfo], grouping: Bool
  ) -> FunctionDeclSyntax {
    if grouping {
      return generateGroupedPropertiesMethod(properties: properties, functions: functions)
    } else {
      return generateUngroupedPropertiesMethod(properties: properties, functions: functions)
    }
  }

  private static func generateUngroupedPropertiesMethod(
    properties: [EditorPropertyInfo], functions: [EditorFunctionInfo]
  ) -> FunctionDeclSyntax {
    var items: [String] = []

    // Add properties
    items.append(
      contentsOf: properties.map { prop in
        let trimmedType = prop.type.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedType == "ParticleEffect" {
          let base = prop.name
          func floatProp(_ codeName: String, _ display: String, _ valueExpr: String, _ setExpr: String, _ range: String)
            -> String
          {
            return """
              AnyEditorProperty(
                name: \"\(codeName)\",
                value: \(valueExpr),
                setValue: { newValue in
                  \(setExpr)
                  // Update emitter if it exists
                  if let emitter = self.currentEmitter {
                    emitter.setEffect(self.\(base))
                  }
                },
                displayName: \"\(display)\",
                validRange: \(range)
              )
              """
          }
          func vec3Prop(_ codeName: String, _ display: String, _ component: String, _ valueExpr: String, _ setExpr: String, _ range: String)
            -> String
          {
            return """
              AnyEditorProperty(
                name: \"\(codeName)\",
                value: \(valueExpr),
                setValue: { newValue in
                  \(setExpr)
                  // Update emitter if it exists
                  if let emitter = self.currentEmitter {
                    emitter.setEffect(self.\(base))
                  }
                },
                displayName: \"\(display)\",
                validRange: \(range)
              )
              """
          }
          func colorProp(_ codeName: String, _ display: String, _ vec4Expr: String, _ setExpr: String)
            -> String
          {
            return """
              AnyEditorProperty(
                name: \"\(codeName)\",
                value: Color(\(vec4Expr)),
                setValue: { newValue in
                  let color = newValue as! Color
                  \(setExpr)
                  // Update emitter if it exists
                  if let emitter = self.currentEmitter {
                    emitter.setEffect(self.\(base))
                  }
                },
                displayName: \"\(display)\",
                validRange: nil
              )
              """
          }
          let pieces = [
            floatProp("\(base)_emissionRate", "Emission Rate", "\(base).emissionRate", "self.\(base).emissionRate = newValue as! Float", "0.0...100.0"),
            floatProp("\(base)_burstCount", "Burst Count", "Float(\(base).burstCount)", "self.\(base).burstCount = Int(newValue as! Float)", "1.0...1000.0"),
            floatProp("\(base)_lifetimeMin", "Lifetime Min", "\(base).lifetimeMin", "self.\(base).lifetimeMin = newValue as! Float", "0.0...10.0"),
            floatProp("\(base)_lifetimeMax", "Lifetime Max", "\(base).lifetimeMax", "self.\(base).lifetimeMax = newValue as! Float", "0.0...10.0"),
            vec3Prop("\(base)_velMin_x", "Velocity Min X", "x", "Float(\(base).velocityMin.x)", "self.\(base).velocityMin = vec3(newValue as! Float, self.\(base).velocityMin.y, self.\(base).velocityMin.z)", "-10.0...10.0"),
            vec3Prop("\(base)_velMin_y", "Velocity Min Y", "y", "Float(\(base).velocityMin.y)", "self.\(base).velocityMin = vec3(self.\(base).velocityMin.x, newValue as! Float, self.\(base).velocityMin.z)", "-10.0...10.0"),
            vec3Prop("\(base)_velMin_z", "Velocity Min Z", "z", "Float(\(base).velocityMin.z)", "self.\(base).velocityMin = vec3(self.\(base).velocityMin.x, self.\(base).velocityMin.y, newValue as! Float)", "-10.0...10.0"),
            vec3Prop("\(base)_velMax_x", "Velocity Max X", "x", "Float(\(base).velocityMax.x)", "self.\(base).velocityMax = vec3(newValue as! Float, self.\(base).velocityMax.y, self.\(base).velocityMax.z)", "-10.0...10.0"),
            vec3Prop("\(base)_velMax_y", "Velocity Max Y", "y", "Float(\(base).velocityMax.y)", "self.\(base).velocityMax = vec3(self.\(base).velocityMax.x, newValue as! Float, self.\(base).velocityMax.z)", "-10.0...10.0"),
            vec3Prop("\(base)_velMax_z", "Velocity Max Z", "z", "Float(\(base).velocityMax.z)", "self.\(base).velocityMax = vec3(self.\(base).velocityMax.x, self.\(base).velocityMax.y, newValue as! Float)", "-10.0...10.0"),
            vec3Prop("\(base)_gravity_x", "Gravity X", "x", "Float(\(base).gravity.x)", "self.\(base).gravity = vec3(newValue as! Float, self.\(base).gravity.y, self.\(base).gravity.z)", "-20.0...20.0"),
            vec3Prop("\(base)_gravity_y", "Gravity Y", "y", "Float(\(base).gravity.y)", "self.\(base).gravity = vec3(self.\(base).gravity.x, newValue as! Float, self.\(base).gravity.z)", "-20.0...20.0"),
            vec3Prop("\(base)_gravity_z", "Gravity Z", "z", "Float(\(base).gravity.z)", "self.\(base).gravity = vec3(self.\(base).gravity.x, self.\(base).gravity.y, newValue as! Float)", "-20.0...20.0"),
            floatProp("\(base)_sizeStart", "Size Start", "\(base).sizeStart", "self.\(base).sizeStart = newValue as! Float", "0.0...2.0"),
            floatProp("\(base)_sizeEnd", "Size End", "\(base).sizeEnd", "self.\(base).sizeEnd = newValue as! Float", "0.0...2.0"),
            floatProp("\(base)_sizeRandomness", "Size Randomness", "\(base).sizeRandomness", "self.\(base).sizeRandomness = newValue as! Float", "0.0...1.0"),
            colorProp("\(base)_colorStart", "Color Start", "\(base).colorStart", "self.\(base).colorStart = color.vec4Representation"),
            colorProp("\(base)_colorEnd", "Color End", "\(base).colorEnd", "self.\(base).colorEnd = color.vec4Representation"),
            floatProp("\(base)_rotationSpeedMin", "Rotation Speed Min", "\(base).rotationSpeedMin", "self.\(base).rotationSpeedMin = newValue as! Float", "-10.0...10.0"),
            floatProp("\(base)_rotationSpeedMax", "Rotation Speed Max", "\(base).rotationSpeedMax", "self.\(base).rotationSpeedMax = newValue as! Float", "-10.0...10.0"),
            floatProp("\(base)_maxParticles", "Max Particles", "Float(\(base).maxParticles)", "self.\(base).maxParticles = Int(newValue as! Float)", "1.0...10000.0"),
          ].joined(separator: ",\n          ")
          return """
            EditorPropertyGroup(
              name: \"\(prop.displayName)\",
              properties: [
                \(pieces)
              ]
            )
            """
        } else if trimmedType == "Light" {
          let base = prop.name
          func floatProp(_ codeName: String, _ display: String, _ valueExpr: String, _ setExpr: String, _ range: String)
            -> String
          {
            return """
              AnyEditorProperty(
                name: \"\(codeName)\",
                value: \(valueExpr),
                setValue: { newValue in
                  \(setExpr)
                },
                displayName: \"\(display)\",
                validRange: \(range)
              )
              """
          }
          let pieces = [
            floatProp(
              "\(base)_dir_x", "Direction X", "Float(\(base).direction.x)",
              "self.\(base).direction = vec3(newValue as! Float, self.\(base).direction.y, self.\(base).direction.z)",
              "-1.0...1.0"),
            floatProp(
              "\(base)_dir_y", "Direction Y", "Float(\(base).direction.y)",
              "self.\(base).direction = vec3(self.\(base).direction.x, newValue as! Float, self.\(base).direction.z)",
              "-1.0...1.0"),
            floatProp(
              "\(base)_dir_z", "Direction Z", "Float(\(base).direction.z)",
              "self.\(base).direction = vec3(self.\(base).direction.x, self.\(base).direction.y, newValue as! Float)",
              "-1.0...1.0"),
            floatProp(
              "\(base)_pos_x", "Position X", "Float(\(base).position.x)",
              "self.\(base).position = vec3(newValue as! Float, self.\(base).position.y, self.\(base).position.z)",
              "-5.0...5.0"),
            floatProp(
              "\(base)_pos_y", "Position Y", "Float(\(base).position.y)",
              "self.\(base).position = vec3(self.\(base).position.x, newValue as! Float, self.\(base).position.z)",
              "-5.0...5.0"),
            floatProp(
              "\(base)_pos_z", "Position Z", "Float(\(base).position.z)",
              "self.\(base).position = vec3(self.\(base).position.x, self.\(base).position.y, newValue as! Float)",
              "-5.0...5.0"),
            floatProp(
              "\(base)_col_r", "Color R", "Float(\(base).color.x)",
              "self.\(base).color = vec3(newValue as! Float, self.\(base).color.y, self.\(base).color.z)", "0.0...1.0"),
            floatProp(
              "\(base)_col_g", "Color G", "Float(\(base).color.y)",
              "self.\(base).color = vec3(self.\(base).color.x, newValue as! Float, self.\(base).color.z)", "0.0...1.0"),
            floatProp(
              "\(base)_col_b", "Color B", "Float(\(base).color.z)",
              "self.\(base).color = vec3(self.\(base).color.x, self.\(base).color.y, newValue as! Float)", "0.0...1.0"),
            floatProp(
              "\(base)_intensity", "Intensity", "\(base).intensity", "self.\(base).intensity = newValue as! Float",
              "0.0...10.0"),
            floatProp(
              "\(base)_range", "Range", "\(base).range", "self.\(base).range = newValue as! Float", "0.0...20.0"),
          ].joined(separator: ",\n          ")
          return """
            EditorPropertyGroup(
              name: \"\(prop.displayName)\",
              properties: [
                \(pieces)
              ]
            )
            """
        } else {
          // If the property type is Bool, do not emit a numeric range so the panel can render a Switch
          let range: String? = (trimmedType == "Bool") ? nil : (prop.range ?? "0.0...1.0")
          return """
            AnyEditorProperty(
              name: \"\(prop.name)\",
              value: \(prop.name),
              setValue: { newValue in
                self.\(prop.name) = newValue as! \(prop.type)
              },
              displayName: \"\(prop.displayName)\",
              validRange: \(range ?? "nil")
            )
            """
        }
      })

    // Add functions
    items.append(
      contentsOf: functions.map { funcInfo in
        """
        EditorFunction(
          name: \"\(funcInfo.name)\",
          displayName: \"\(funcInfo.displayName)\",
          action: { self.\(funcInfo.name)() }
        )
        """
      })

    let itemsString = items.joined(separator: ",\n      ")

    let functionDecl = try! FunctionDeclSyntax(
      """
      func getEditableProperties() -> [Any] {
        return [
          \(raw: itemsString)
        ]
      }
      """)

    return functionDecl
  }

  private static func generateGroupedPropertiesMethod(
    properties: [EditorPropertyInfo], functions: [EditorFunctionInfo]
  ) -> FunctionDeclSyntax {
    // Group properties by their prefix (first word) while preserving order
    var groupedProperties = OrderedDictionary<String, [EditorPropertyInfo]>()

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
        // Special-case Light to expose sub-properties
        if prop.type.trimmingCharacters(in: .whitespacesAndNewlines) == "Light" {
          let base = prop.name
          func floatProp(_ codeName: String, _ display: String, _ valueExpr: String, _ setExpr: String, _ range: String)
            -> String
          {
            return """
              AnyEditorProperty(
                name: \"\(codeName)\",
                value: \(valueExpr),
                setValue: { newValue in
                  \(setExpr)
                },
                displayName: \"\(display)\",
                validRange: \(range)
              )
              """
          }
          let pieces = [
            floatProp(
              "\(base)_dir_x", "Direction X", "Float(\(base).direction.x)",
              "self.\(base).direction = vec3(newValue as! Float, self.\(base).direction.y, self.\(base).direction.z)",
              "-1.0...1.0"),
            floatProp(
              "\(base)_dir_y", "Direction Y", "Float(\(base).direction.y)",
              "self.\(base).direction = vec3(self.\(base).direction.x, newValue as! Float, self.\(base).direction.z)",
              "-1.0...1.0"),
            floatProp(
              "\(base)_dir_z", "Direction Z", "Float(\(base).direction.z)",
              "self.\(base).direction = vec3(self.\(base).direction.x, self.\(base).direction.y, newValue as! Float)",
              "-1.0...1.0"),
            floatProp(
              "\(base)_pos_x", "Position X", "Float(\(base).position.x)",
              "self.\(base).position = vec3(newValue as! Float, self.\(base).position.y, self.\(base).position.z)",
              "-5.0...5.0"),
            floatProp(
              "\(base)_pos_y", "Position Y", "Float(\(base).position.y)",
              "self.\(base).position = vec3(self.\(base).position.x, newValue as! Float, self.\(base).position.z)",
              "-5.0...5.0"),
            floatProp(
              "\(base)_pos_z", "Position Z", "Float(\(base).position.z)",
              "self.\(base).position = vec3(self.\(base).position.x, self.\(base).position.y, newValue as! Float)",
              "-5.0...5.0"),
            floatProp(
              "\(base)_col_r", "Color R", "Float(\(base).color.x)",
              "self.\(base).color = vec3(newValue as! Float, self.\(base).color.y, self.\(base).color.z)", "0.0...1.0"),
            floatProp(
              "\(base)_col_g", "Color G", "Float(\(base).color.y)",
              "self.\(base).color = vec3(self.\(base).color.x, newValue as! Float, self.\(base).color.z)", "0.0...1.0"),
            floatProp(
              "\(base)_col_b", "Color B", "Float(\(base).color.z)",
              "self.\(base).color = vec3(self.\(base).color.x, self.\(base).color.y, newValue as! Float)", "0.0...1.0"),
            floatProp(
              "\(base)_intensity", "Intensity", "\(base).intensity", "self.\(base).intensity = newValue as! Float",
              "0.0...10.0"),
            floatProp(
              "\(base)_range", "Range", "\(base).range", "self.\(base).range = newValue as! Float", "0.0...20.0"),
          ]
          return pieces.joined(separator: ",\n        ")
        }
        let range = prop.range ?? "0.0...1.0"
        // Remove the group name prefix from the display name
        let words = prop.displayName.components(separatedBy: " ")
        let displayName = words.count > 1 ? words.dropFirst().joined(separator: " ") : prop.displayName
        return """
          AnyEditorProperty(
            name: \"\(prop.name)\",
            value: \(prop.name),
            setValue: { newValue in
              self.\(prop.name) = newValue as! \(prop.type)
            },
            displayName: \"\(displayName)\",
            validRange: \(range)
          )
          """
      }.joined(separator: ",\n        ")
      return """
        EditorPropertyGroup(
          name: \"\(groupName)\",
          properties: [
            \(sectionProperties)
          ]
        )
        """
    }.joined(separator: ",\n      ")

    // Add functions as separate items (not in property groups)
    var allItems = sections
    if !functions.isEmpty {
      let functionItems = functions.map { funcInfo in
        """
        EditorFunction(
          name: \"\(funcInfo.name)\",
          displayName: \"\(funcInfo.displayName)\",
          action: { self.\(funcInfo.name)() }
        )
        """
      }.joined(separator: ",\n      ")
      allItems += ",\n      \(functionItems)"
    }

    let functionDecl = try! FunctionDeclSyntax(
      """
      func getEditableProperties() -> [Any] {
        return [
          \(raw: allItems)
        ]
      }
      """)
    return functionDecl
  }
}

private struct EditableMacroError: Error {
  let message: String
  init(_ message: String) {
    self.message = message
  }
}

private struct EditorPropertyInfo {
  let name: String
  let type: String
  let displayName: String
  let range: String?
}

private struct EditorFunctionInfo {
  let name: String
  let displayName: String
}

/// Peer macro for @Editor on functions - just marks the function, doesn't generate anything
/// This allows @Editor to be used on functions (as an attribute macro) while also being a property wrapper for properties
/// Swift will use the property wrapper for properties and this macro for functions
public struct EditorFunctionMacro: PeerMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingPeersOf declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    // Only expand for functions - properties will use the property wrapper
    guard declaration.as(FunctionDeclSyntax.self) != nil else {
      // If it's not a function, this macro shouldn't be used - let the property wrapper handle it
      // Return empty to allow the property wrapper to take over
      return []
    }

    // This macro doesn't generate anything - it's just a marker
    // The EditableMacro will find functions with this attribute
    return []
  }
}
