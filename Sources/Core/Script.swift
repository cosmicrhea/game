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

  /// Called when the scene script is loaded and initialized
  /// Override this method in scene-specific script classes to perform initialization
  func sceneDidLoad() {}

  /// Find a node by name, searching from the root node
  /// Matches exact names or names with dashed suffixes (e.g., "CatStatue" matches "CatStatue-fg")
  func findNode(_ name: String) -> Node? {
    return findNode(named: name, in: scene.rootNode)
  }

  private func findNode(named name: String, in node: Node) -> Node? {
    // Check if this node matches (exact match or starts with name followed by dash)
    if let nodeName = node.name {
      if nodeName == name || nodeName.hasPrefix("\(name)-") {
        return node
      }
    }

    // Recursively search children
    for child in node.children {
      if let found = findNode(named: name, in: child) {
        return found
      }
    }

    return nil
  }

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
