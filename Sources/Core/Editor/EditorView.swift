#if EDITOR

  import SwiftUI

  /// Notification name for loop changes.
  extension Notification.Name {
    static let loopChanged = Notification.Name("LoopChanged")
  }

  /// A SwiftUI view that displays the editor for the current active loop.
  struct EditorView: View {
    /// Observable object that tracks the current active loop.
    @MainActor
    class LoopManager: ObservableObject {
      @Published var currentLoop: RenderLoop

      init(initialLoop: RenderLoop) {
        self.currentLoop = initialLoop
      }
    }

    @StateObject private var loopManager = LoopManager(initialLoop: activeLoop)

    var body: some View {
      Group {
        if loopManager.currentLoop is Editing {
          PropertiesEditor(for: loopManager.currentLoop as! Editing)
            .controlSize(.mini)
        } else {
          Form {
            Text("No Editor for `\(String(describing: type(of: loopManager.currentLoop)))`")
              .foregroundStyle(.secondary)
          }
          // VStack(alignment: .leading, spacing: 8) {
          //   Text("Current loop: \(String(describing: type(of: loopManager.currentLoop)))")
          //     .font(.headline)
          //   Text("No editable properties available")
          //     .font(.caption)
          //     .foregroundColor(.secondary)
          //   Text("Add @Editor to this RenderLoop to enable editing")
          //     .font(.caption2)
          //     .foregroundColor(.secondary)
          // }
        }
      }
      .formStyle(.grouped)
      .frame(maxWidth: 320)
      .scrollDisabled(true)
      .scrollContentBackground(.hidden)
      .onReceive(NotificationCenter.default.publisher(for: .loopChanged)) { _ in
        loopManager.currentLoop = activeLoop
      }
    }
  }

  /// A SwiftUI view that works with any Editing object
  public struct PropertiesEditor: View {
    private let object: Editing
    @State private var properties: [AnyEditableProperty] = []

    public init(for object: Editing) {
      self.object = object
    }

    public var body: some View {
      Form {
        ForEach(Array(properties.enumerated()), id: \.offset) { index, property in
          EditablePropertyControl(property: property)
        }
      }
      .onAppear {
        properties = object.getEditableProperties()
      }
    }
  }

  // /// A SwiftUI view that automatically generates controls for @Editable properties
  // public struct AutoEditorView<T: Editing>: View {
  //   @State private var properties: [AnyEditableProperty] = []
  //   private let object: T

  //   public init(for object: T) {
  //     self.object = object
  //   }

  //   public var body: some View {
  //     Form {
  //       ForEach(Array(properties.enumerated()), id: \.offset) { index, property in
  //         EditablePropertyControl(property: property)
  //       }
  //     }
  //     .onAppear {
  //       properties = object.getEditableProperties()
  //     }
  //   }
  // }

  /// A control for editing a single property
  public struct EditablePropertyControl: View {
    @State private var localValue: Double
    private let property: AnyEditableProperty

    public init(property: AnyEditableProperty) {
      self.property = property
      self._localValue = State(initialValue: property.value as? Double ?? 0.0)
    }

    public var body: some View {
      if let range = property.validRange {
        Slider(value: $localValue, in: range) {
          Text(property.displayName)
        } onEditingChanged: { editing in
          print("editing \(property.displayName): \(editing)")
        }
        .onChange(of: localValue) { newValue in
          property.setValue(Float(newValue))
          UISound.select()
        }
      } else {
        LabeledContent(property.displayName) {
          Text("\(localValue)")
            .font(.system(.body, design: .monospaced))
        }
      }
    }
  }

#endif
