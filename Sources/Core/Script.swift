import Assimp
import ObjectiveC

// TODO: macro for `@Flag`

class Character {

  func play(animation animationName: String) {}

  func teleport(to waypointName: String) {}
  func walk(to waypointName: String) {}
  func run(to waypointName: String) {}

}

@MainActor
class Script: NSObject {

  private(set) var scene: Scene
  private var dialogView: DialogView

  required init(scene: Scene, dialogView: DialogView) {
    self.scene = scene
    self.dialogView = dialogView
    super.init()
  }

  //private var storageView = ItemStorageView()

  var hasAliveEnemies: Bool { false }

  func loadScene(_ name: String, entry entryName: String? = nil) {}

  @MainActor func say(_ string: String) { dialogView.print(chunks: [string]) }
  @MainActor func say(_ strings: [String]) { dialogView.print(chunks: strings) }

  func ask(_ string: String, options: [String]) -> String { options[0] }

  func confirm(_ string: String, _ optionA: String, _ optionB: String = "Cancel") -> Bool {
    ask(string, options: [optionA, optionB]) == optionA
  }

  func pause(_ seconds: Float) {}

  @discardableResult func acquire(_ item: Item, quantity: Int = 1) -> Bool { false }
  func acquire(_ document: Document) {}

  func play(sound soundName: String) {}
  func play(sound soundName: String, at node: Node) {}
  func play(video videoName: String) {}
  func play(cutscene cutsceneName: String) {}

  func fadeOut() {}
  func fadeIn() {}

  func openStorage() {}

  func interact(with node: Node, using item: Item?) {}

}
