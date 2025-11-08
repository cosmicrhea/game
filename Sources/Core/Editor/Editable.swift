/// Editor grouping options.
public enum EditorGrouping {
  case none
  case grouped
}

/// Macro to automatically generate getEditableProperties() method from @Editor properties.
@attached(member, names: named(getEditableProperties))
@attached(extension, conformances: Editing)
public macro Editable(_ grouping: EditorGrouping = .none) =
  #externalMacro(module: "GameMacros", type: "EditableMacro")

/// Attribute macro for marking functions as callable from the editor.
/// This works alongside the @Editor property wrapper - Swift will choose the correct one based on context.
/// For properties: @Editor(8.0...64.0) uses the property wrapper
/// For functions: @Editor uses this attribute macro
/// The macro signature matches the property wrapper's init to allow Swift to distinguish them.
@attached(peer)
public macro Editor(_ range: ClosedRange<Double>? = nil, displayName: String? = nil) = 
  #externalMacro(module: "GameMacros", type: "EditorFunctionMacro")


/// A property wrapper that marks properties as editable in the debug editor.
@propertyWrapper
public struct Editor<T> {
  private var value: T
  private let displayName: String
  private let range: ClosedRange<Double>?
  private let staticPickerOptions: [String]?
  private let pickerOptionsProvider: (() -> [String])?
  private let variableName: String

  public init(
    wrappedValue: T, displayName: String? = nil, _ range: ClosedRange<Double>? = nil, variableName: String = ""
  )
  where T == Float {
    self.value = wrappedValue
    self.displayName = displayName ?? variableName.capitalized
    self.range = range ?? 0.0...1.0
    self.staticPickerOptions = nil
    self.pickerOptionsProvider = nil
    self.variableName = variableName
  }

  public init(wrappedValue: T, displayName: String? = nil, variableName: String = "") where T: Equatable {
    self.value = wrappedValue
    self.displayName = displayName ?? variableName.capitalized
    self.range = nil
    self.staticPickerOptions = nil
    self.pickerOptionsProvider = nil
    self.variableName = variableName
  }

  /// Initializer for String properties with static picker options
  public init(wrappedValue: T, displayName: String? = nil, options: [String]? = nil, variableName: String = "")
  where T == String {
    self.value = wrappedValue
    self.displayName = displayName ?? variableName.capitalized
    self.range = nil
    self.staticPickerOptions = options
    self.pickerOptionsProvider = nil
    self.variableName = variableName
  }

  /// Initializer for String properties with dynamic picker options
  public init(wrappedValue: T, displayName: String? = nil, options: @escaping () -> [String], variableName: String = "")
  where T == String {
    self.value = wrappedValue
    self.displayName = displayName ?? variableName.capitalized
    self.range = nil
    self.staticPickerOptions = nil
    self.pickerOptionsProvider = options
    self.variableName = variableName
  }

  /// Generic initializer for non-Equatable types (e.g., complex structs like `Light`).
  /// No range is provided for arbitrary types; sub-editors should expose fields via the macro.
  public init(wrappedValue: T, displayName: String? = nil, variableName: String = "") {
    self.value = wrappedValue
    self.displayName = displayName ?? variableName.capitalized
    self.range = nil
    self.staticPickerOptions = nil
    self.pickerOptionsProvider = nil
    self.variableName = variableName
  }

  public var wrappedValue: T {
    get { value }
    set { value = newValue }
  }

  public var projectedValue: Editor<T> {
    get { self }
    set { self = newValue }
  }

  /// The display name for this property in the editor.
  public var name: String {
    displayName
  }

  /// The range for numeric properties (if applicable).
  public var validRange: ClosedRange<Double>? {
    range
  }

  /// The picker options for String properties (if applicable).
  public var pickerOptions: [String]? {
    return pickerOptionsProvider?() ?? self.staticPickerOptions
  }
}

/// Protocol for objects that can provide editor properties.
@MainActor
public protocol Editing: AnyObject {
  func getEditableProperties() -> [Any]
}

/// A group of related editor properties.
public struct EditorPropertyGroup {
  public let name: String
  public let properties: [AnyEditorProperty]

  public init(name: String, properties: [AnyEditorProperty]) {
    self.name = name
    self.properties = properties
  }
}

/// Type-erased wrapper for editor properties that can actually modify the original values.
public struct AnyEditorProperty {
  public let name: String
  public let value: Any
  public let setValue: (Any) -> Void
  public let displayName: String
  public let validRange: ClosedRange<Double>?
  public let pickerOptions: [String]?

  public init<T>(_ property: Editor<T>) {
    self.name = property.name
    self.value = property.wrappedValue
    self.setValue = { newValue in
      // This won't work because we're capturing a copy
      var mutableProperty = property
      mutableProperty.wrappedValue = newValue as! T
    }
    self.displayName = property.name
    self.validRange = property.validRange
    self.pickerOptions = property.pickerOptions
  }

  public init(
    name: String,
    value: Any,
    setValue: @escaping (Any) -> Void,
    displayName: String,
    validRange: ClosedRange<Double>?,
    pickerOptions: [String]? = nil
  ) {
    self.name = name
    self.value = value
    self.setValue = setValue
    self.displayName = displayName
    self.validRange = validRange
    self.pickerOptions = pickerOptions
  }
}

/// Represents an editor function that can be called from the editor.
public struct EditorFunction {
  public let name: String
  public let displayName: String
  public let action: () -> Void

  public init(name: String, displayName: String, action: @escaping () -> Void) {
    self.name = name
    self.displayName = displayName
    self.action = action
  }
}
