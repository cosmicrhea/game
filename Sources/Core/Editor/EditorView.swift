#if EDITOR

  import SwiftUI

  struct EditorView: View {
    var body: some View {
      Group {
        if let mapView = activeLoop as? MapView {
          AutoEditorView(for: mapView)
        } else if let mapDemo = activeLoop as? MapDemo {
          // Access the MapView from MapDemo
          AutoEditorView(for: mapDemo.mapView)
        } else {
          Text("Current loop: \(String(describing: type(of: activeLoop)))")
          Text("No editable properties available")
        }
      }
      .formStyle(.grouped)
      .controlSize(.mini)
      .frame(maxWidth: 320)
      .scrollDisabled(true)
      .scrollContentBackground(.hidden)
      // .fixedSize(horizontal: false, vertical: true)
      //.background(Color.clear)
      // .border(.mint)
      //.tint(.black)
    }
  }

#endif
