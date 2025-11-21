@SceneScript
class Test: Script {

  @FindNode var catStatue: Node
  //@SceneReference var stoveCloseup: Camera

  func showCat() {
    if catStatue.isHidden {
      UISound.select()
      catStatue.isHidden = false
      logger.trace("showing cat!!!!")
    }
  }

  func stove() {
    guard catStatue.isHidden else {
      Task { await cat() }
      return
    }

    say([
      "The stove is cold and lifeless.",
      "There's nothing cooking right now.",
      "It looks like it hasn't been used in a while.",
    ])
  }

  func cat() async {
    // await say("A cat has appeared.")
    await withCloseup(on: "stove.001") {
      await say("There's a cat here.", more: true)
      await acquire(.catStatue)
    }
  }

  func door() {
    go(toScene: "shooting_range", entry: "hallway")
  }

}
