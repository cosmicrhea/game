/// Editor grouping options.
public enum EditorGrouping {
  case none
  case grouped
}

/// Macro to automatically generate getEditableProperties() method from @Editable properties.
@attached(member, names: named(getEditableProperties))
@attached(extension, conformances: Editing)
public macro Editor(_ grouping: EditorGrouping = .none) =
  #externalMacro(module: "GlassEditorMacros", type: "EditorMacro")

/// Macro for generating computed properties that provide options for @Editable String properties
@attached(accessor)
public macro EditableOptions() = #externalMacro(module: "GlassEditorMacros", type: "EditableOptionsMacro")

/// A property wrapper that marks properties as editable in the debug editor.
@propertyWrapper
public struct Editable<T> {
  private var value: T
  private let displayName: String
  private let range: ClosedRange<Double>?
  private let staticPickerOptions: [String]?
  private let pickerOptionsProvider: (() -> [String])?
  private let variableName: String

  public init(
    wrappedValue: T, displayName: String? = nil, range: ClosedRange<Double>? = nil, variableName: String = ""
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

  public var projectedValue: Editable<T> {
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

/// Protocol for objects that can provide editable properties.
@MainActor
public protocol Editing: AnyObject {
  func getEditableProperties() -> [Any]
}

/// A group of related editable properties.
public struct EditablePropertyGroup {
  public let name: String
  public let properties: [AnyEditableProperty]

  public init(name: String, properties: [AnyEditableProperty]) {
    self.name = name
    self.properties = properties
  }
}

/// Type-erased wrapper for editable properties that can actually modify the original values.
public struct AnyEditableProperty {
  public let name: String
  public let value: Any
  public let setValue: (Any) -> Void
  public let displayName: String
  public let validRange: ClosedRange<Double>?
  public let pickerOptions: [String]?

  public init<T>(_ property: Editable<T>) {
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
