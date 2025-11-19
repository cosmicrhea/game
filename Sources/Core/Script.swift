import Assimp

// TODO: macro for `@Flag`

/// Macro to automatically generate method registry and dynamic calling for scene scripts
@attached(
  member, names: named(methodRegistry), named(availableMethods), named(callMethod), named(_register),
  named(_autoRegister))
public macro SceneScript() = #externalMacro(module: "GameMacros", type: "SceneScriptMacro")

/// Macro to automatically find a node from the scene
/// Usage: `@FindNode var catStatue: Node!` or `@FindNode("StatueOfCat") var catStatue: Node!`
@attached(accessor)
@attached(peer, names: arbitrary)
public macro FindNode(_ nodeName: String? = nil) = #externalMacro(module: "GameMacros", type: "FindNodeMacro")

class Character {

  func play(animation animationName: String) {}

  func teleport(to waypointName: String) {}
  func walk(to waypointName: String) {}
  func run(to waypointName: String) {}

}

protocol SceneLoadingDelegate {
  func sceneDidLoad()
}

extension SceneLoadingDelegate {
  func sceneDidLoad() {}
}

@MainActor
class Script: SceneLoadingDelegate {

  var scene: Scene {
    guard let mainLoop = MainLoop.shared else {
      fatalError("MainLoop.shared is nil - ensure MainLoop.init() has been called")
    }
    guard let scene = mainLoop.scene else {
      fatalError("MainLoop.shared.scene is nil - ensure loadScene() has been called")
    }
    return scene
  }

  var dialogView: DialogView {
    guard let mainLoop = MainLoop.shared else {
      fatalError("MainLoop.shared is nil - ensure MainLoop.init() has been called")
    }
    return mainLoop.dialogView
  }

  /// Track the current action name (set by MainLoop before calling interaction methods)
  var currentActionName: String?

  /// Track the current area/zone the player is in (set automatically when transitioning)
  /// This can be used to determine which side of a door the player is on, etc.
  var currentArea: String?

  /// Track interaction counts for variations cycling
  private var interactionCounts: [String: Int] = [:]
  /// Track call counters per action (resets each interaction)
  private var sayCallCounters: [String: Int] = [:]

  /// Reset the call counter for an action (called at the start of each interaction)
  func resetCallCounter(for actionName: String) {
    sayCallCounters[actionName] = 0
  }

  //private var storageView = StorageView()

  var hasAliveEnemies: Bool { false }

  // /// Called when the scene script is loaded and initialized
  // /// Override this method in scene-specific script classes to perform initialization
  // func sceneDidLoad() {}

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

  /// Transition to a different entry in the current scene
  /// - Parameter entry: The entry name (e.g., "hallway", "Entry_2")
  @MainActor func go(to entry: String) {
    guard let mainLoop = MainLoop.shared else {
      logger.warning("⚠️ Cannot transition: MainLoop.shared is nil")
      return
    }
    Task {
      await mainLoop.transition(to: entry)
    }
  }

  /// Transition to a different entry in the current scene (async version that waits for completion)
  /// - Parameter entry: The entry name (e.g., "hallway", "Entry_2")
  @MainActor func go(to entry: String) async {
    guard let mainLoop = MainLoop.shared else {
      logger.warning("⚠️ Cannot transition: MainLoop.shared is nil")
      return
    }
    await mainLoop.transition(to: entry)
  }

  /// Transition to a different scene
  /// - Parameters:
  ///   - scene: The scene name to load
  ///   - entry: Optional entry name (defaults to "Entry_1" if not specified)
  @MainActor func go(toScene scene: String, entry: String? = nil) {
    guard let mainLoop = MainLoop.shared else {
      logger.warning("⚠️ Cannot transition: MainLoop.shared is nil")
      return
    }
    Task {
      await mainLoop.transition(toScene: scene, entry: entry)
    }
  }

  /// Transition to a different scene (async version that waits for completion)
  /// - Parameters:
  ///   - scene: The scene name to load
  ///   - entry: Optional entry name (defaults to "Entry_1" if not specified)
  @MainActor func go(toScene scene: String, entry: String? = nil) async {
    guard let mainLoop = MainLoop.shared else {
      logger.warning("⚠️ Cannot transition: MainLoop.shared is nil")
      return
    }
    await mainLoop.transition(toScene: scene, entry: entry)
  }

  @MainActor func say(_ string: String) { dialogView.print(chunks: [string]) }
  @MainActor func say(_ strings: [String]) { dialogView.print(chunks: strings) }

  /// Async version of say() that waits until the dialog is finished
  /// - Parameter string: The text to display
  /// - Parameter more: If true, forces the more indicator to show even if there are no more chunks
  @MainActor func say(_ string: String, more: Bool = false) async {
    await dialogView.print(chunks: [string], forceMore: more)
  }

  /// Async version of say() that waits until the dialog is finished
  /// - Parameter strings: Array of text chunks to display
  /// - Parameter more: If true, forces the more indicator to show even if there are no more chunks
  @MainActor func say(_ strings: [String], more: Bool = false) async {
    await dialogView.print(chunks: strings, forceMore: more)
  }

  /// Say text with variations that cycle through on repeated interactions
  /// - Parameter variations: Array of text variations to cycle through
  /// The variations loop back to the first after exhausting all options
  @MainActor func say(variations: [String]) {
    guard !variations.isEmpty else { return }

    // Use currentActionName if available, otherwise fall back to #function
    let actionName = currentActionName ?? #function

    // Get and increment the call counter for this action
    let callIndex = sayCallCounters[actionName, default: 0]
    sayCallCounters[actionName] = callIndex + 1

    // Use action name + call index as the key
    let key = "\(actionName):\(callIndex)"
    let count = interactionCounts[key, default: 0]
    let index = count % variations.count
    let text = variations[index]

    interactionCounts[key] = count + 1

    say(text)
  }

  /// Async version of say(variations:) that waits until the dialog is finished
  /// - Parameter variations: Array of text variations to cycle through
  /// The variations loop back to the first after exhausting all options
  @MainActor func say(variations: [String]) async {
    guard !variations.isEmpty else { return }

    // Use currentActionName if available, otherwise fall back to #function
    let actionName = currentActionName ?? #function

    // Get and increment the call counter for this action
    let callIndex = sayCallCounters[actionName, default: 0]
    sayCallCounters[actionName] = callIndex + 1

    // Use action name + call index as the key
    let key = "\(actionName):\(callIndex)"
    let count = interactionCounts[key, default: 0]
    let index = count % variations.count
    let text = variations[index]

    interactionCounts[key] = count + 1

    say(text)
  }

  func ask(_ string: String, options: [String]) -> String { options[0] }

  func confirm(_ string: String, _ optionA: String, _ optionB: String = "Cancel") -> Bool {
    ask(string, options: [optionA, optionB]) == optionA
  }

  func pause(_ seconds: Float) {}

  @discardableResult func acquire(_ item: Item, quantity: Int = 1) async -> Bool {
    // Input is already disabled by dialogView.dismiss() when dialog finishes
    // Show PickupView and wait for result
    guard let mainLoop = MainLoop.shared else {
      logger.warning("⚠️ Cannot show PickupView: MainLoop.shared is nil")
      Input.player1.isEnabled = true  // Re-enable on error
      return false
    }

    // Show the pickup view and wait for result
    return await mainLoop.showPickupView(item: item, quantity: quantity)
  }

  func acquire(_ document: Document) {}

  func play(sound soundName: String) {}
  func play(sound soundName: String, at node: Node) {}
  func play(video videoName: String) {}
  func play(cutscene cutsceneName: String) {}

  func fadeOut() {}
  func fadeIn() {}

  /// Shake the screen with the specified intensity
  /// - Parameters:
  ///   - intensity: The intensity of the shake (.subtle or .heavy)
  ///   - axis: Optional axis to limit shake to (.horizontal or .vertical). If nil, shakes on both axes.
  func shakeScreen(_ intensity: ScreenShake.Intensity, axis: Axis? = nil) {
    ScreenShake.shared.shake(intensity, axis: axis)
  }

  func openStorage() {}

  func interact(with node: Node, using item: Item?) {}

  // Default implementations for @SceneScript macro-generated methods
  // These are overridden by the macro in scene script classes
  class func availableMethods() -> [String] {
    return []
  }

  func callMethod(named methodName: String) -> Task<Void, Never>? {
    return nil
  }

}
