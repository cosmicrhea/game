//import SwiftCrossUI
//import class Foundation.Bundle
//
//struct TitleScreen: View {
//  var body: some View {
//    VStack {
//      Spacer()
//        .frame(minHeight: 96)
//
//      Image(Bundle.module.url(forResource: "icon", withExtension: "png")!)
//        .resizable()
//        .frame(width: 96, height: 96)
//
//      Text("Glass")
//        .font(.largeTitle)
//
//      Text("Version 0.1")
//        .font(.caption)
//        .foregroundColor(.gray)
//
//      Spacer()
//        .frame(minHeight: 96)
//
//      TitleScreenButton("Start Game") {}
//      TitleScreenButton("Load Game") {}
//      TitleScreenButton("Settings") {}
//      TitleScreenButton("Quit") {}
//    }
//    .padding()
//  }
//}
//
//struct TitleScreenButton: View {
//  var title: String
//  var action: @Sendable () -> Void
//
//  init(_ title: String, action: @Sendable @escaping () -> Void) {
//    self.title = title
//    self.action = action
//    }
//
//  var body: some View {
//    Button(title, action: action)
//      ._buttonWidth(256)
//  }
//}
