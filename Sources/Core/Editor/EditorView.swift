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
      VStack {
        Group {
          if loopManager.currentLoop is Editing {
            PropertiesEditor(for: loopManager.currentLoop as! Editing)
              .controlSize(.mini)
          } else {
            Form {
              Section("`\(String(describing: type(of: loopManager.currentLoop)))`") {
                Text("No Editor")
                  .foregroundStyle(.secondary)
              }
            }
          }
        }
        .formStyle(.grouped)
//        .padding(.horizontal, -9)
//        .padding(.top, -3)
        .frame(width: 320)
        .fixedSize()
//        .padding(.bottom, 3)
        .scrollDisabled(true)
        .scrollContentBackground(.hidden)
//        .background(.ultraThinMaterial)
//        .clipShape(RoundedRectangle(cornerRadius: 7))
//        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.ultraThickMaterial))
        .padding(5)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .onReceive(NotificationCenter.default.publisher(for: .loopChanged)) { _ in
        loopManager.currentLoop = activeLoop
      }
    }
  }

  /// A SwiftUI view that works with any Editing object
  public struct PropertiesEditor: View {
    private let object: Editing
    @State private var properties: [AnyEditableProperty] = []
    @State private var groups: [EditablePropertyGroup] = []

    public init(for object: Editing) {
      self.object = object
    }

    public var body: some View {
      Form {
        if !groups.isEmpty {
          // Show grouped properties
          ForEach(groups, id: \.name) { group in
            Section(group.name) {
              ForEach(Array(group.properties.enumerated()), id: \.offset) { index, property in
                EditablePropertyControl(property: property)
              }
            }
          }
        } else {
          // Show ungrouped properties
          ForEach(Array(properties.enumerated()), id: \.offset) { index, property in
            EditablePropertyControl(property: property)
          }
        }
      }
      .onAppear {
        let allItems = object.getEditableProperties()

        // Check if we have grouped properties by looking at the first item
        if allItems.first is EditablePropertyGroup {
          groups = allItems.compactMap { $0 as? EditablePropertyGroup }
          properties = []
        } else {
          properties = allItems.compactMap { $0 as? AnyEditableProperty }
          groups = []
        }
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
        LabeledContent(property.displayName) {
          HStack(spacing: 0) {
            Slider(value: $localValue, in: range)

              //        } onEditingChanged: { editing in
              //          print("editing \(property.displayName): \(editing)")
              //        }
              .onChange(of: localValue) { newValue in
                property.setValue(Float(newValue))
                //          UISound.select()
              }

            Text("\(String(format: "%.3f", localValue).padding(toLength: 7, withPad: "\u{2007}", startingAt: 0))")
              .font(.body.monospacedDigit())
              .foregroundStyle(.secondary)
          }
        }
      } else {
        LabeledContent(property.displayName) {
          Text("\(String(format: "%.3f", localValue).padding(toLength: 7, withPad: "\u{2007}", startingAt: 0))")
            .font(.system(.body, design: .monospaced))
        }
      }
    }
  }

#endif
