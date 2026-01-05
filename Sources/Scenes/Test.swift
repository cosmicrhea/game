@SceneScript
class Test: Script {

  @Ref var catStatue: Node
  @Ref var stove: Node
  //@SceneReference var stoveCloseup: Camera

  func showCat() {
    // if catStatue.isHidden {
    //   UISound.select()
    //   catStatue.isHidden = false
    // }
  }

  func stove() async {
    guard catStatue.isHidden else {
      await cat()
      return
    }

    await withPlayerLookingAt(stove) {
      await say([
        "The stove is cold and lifeless.",
        "There's nothing cooking right now.",
        "It looks like it hasn't been used in a while.",
      ])
    }
  }

  func cat() async {
    // await say("A cat has appeared.")
    await withCloseupOn("stove.001") {
      await say("There's a cat here.", more: true)
      if await acquire(.catStatue) {
        catStatue.isHidden = true
      }
    }
  }

  func door() {
    goTo(scene: "nexus", entry: "3")
  }

}
