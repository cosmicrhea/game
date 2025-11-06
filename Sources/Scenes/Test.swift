import Assimp

@objcMembers class Test: Script {

  var catStatue: Node!

  func sceneDidLoad() {
    catStatue = scene.rootNode.findNode(named: "CatStatue-fg")
    catStatue.isHidden = true
  }

  func showCat() {
    catStatue.isHidden = false
  }

  func stove() {
    say([
      "The stove is cold and lifeless.",
      "There's nothing cooking right now.",
      "It looks like it hasn't been used in a while.",
    ])
  }

  func cat() async {
    say("A cat has appeared.")
    acquire(.utilityKey)
  }

}
