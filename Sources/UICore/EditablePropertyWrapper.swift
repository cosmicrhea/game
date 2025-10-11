import Foundation
import SwiftUI

/// A property wrapper that marks properties as editable in the debug editor
@propertyWrapper
public struct Editable<T> {
  private var value: T
  private let displayName: String
  private let range: ClosedRange<Double>?

  public init(wrappedValue: T, displayName: String? = nil, range: ClosedRange<Double>? = nil) where T == Float {
    self.value = wrappedValue
    self.displayName = displayName ?? String(describing: T.self)
    self.range = range ?? 0.0...1.0
  }

  public init(wrappedValue: T, displayName: String? = nil) where T: Equatable {
    self.value = wrappedValue
    self.displayName = displayName ?? String(describing: T.self)
    self.range = nil
  }

  public var wrappedValue: T {
    get { value }
    set { value = newValue }
  }

  public var projectedValue: Editable<T> {
    get { self }
    set { self = newValue }
  }

  /// The display name for this property in the editor
  public var name: String {
    displayName
  }

  /// The range for numeric properties (if applicable)
  public var validRange: ClosedRange<Double>? {
    range
  }
}

/// Protocol for objects that can provide editable properties
public protocol EditableObject: AnyObject {
  func getEditableProperties() -> [AnyEditableProperty]
}

/// Type-erased wrapper for editable properties that can actually modify the original values
public struct AnyEditableProperty {
  public let name: String
  public let value: Any
  public let setValue: (Any) -> Void
  public let displayName: String
  public let validRange: ClosedRange<Double>?

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
  }

  public init(
    name: String,
    value: Any,
    setValue: @escaping (Any) -> Void,
    displayName: String,
    validRange: ClosedRange<Double>?
  ) {
    self.name = name
    self.value = value
    self.setValue = setValue
    self.displayName = displayName
    self.validRange = validRange
  }
}

/// A SwiftUI view that automatically generates controls for @Editable properties
public struct AutoEditorView<T: EditableObject>: View {
  @State private var properties: [AnyEditableProperty] = []
  private let object: T

  public init(for object: T) {
    self.object = object
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(Array(properties.enumerated()), id: \.offset) { index, property in
        EditablePropertyControl(property: property)
      }
    }
    .onAppear {
      properties = object.getEditableProperties()
    }
  }
}

/// A control for editing a single property
public struct EditablePropertyControl: View {
  @State private var localValue: Double
  private let property: AnyEditableProperty

  public init(property: AnyEditableProperty) {
    self.property = property
    self._localValue = State(initialValue: property.value as? Double ?? 0.0)
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(property.displayName)
        .font(.caption)
        .foregroundColor(.secondary)

      if let range = property.validRange {
        Slider(value: $localValue, in: range)
          .onChange(of: localValue) { newValue in
            property.setValue(Float(newValue))
          }
      } else {
        Text("\(localValue)")
          .font(.system(.body, design: .monospaced))
      }
    }
  }
}
