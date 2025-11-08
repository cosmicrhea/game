@objcMembers class Test: Script {

  var catStatue: Node!

  override func sceneDidLoad() {
    catStatue = findNode("CatStatue")
    //catStatue.isHidden = true
  }

  func showCat() {
    if catStatue.isHidden {
      UISound.select()
      catStatue.isHidden = false
      print("showing cat!!!!")
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
      "It looks like it hasn't been used in a while."
    ])
  }

  func cat() async {
    // await say("A cat has appeared.")
    await say("There's a cat here.", more: true)
    await acquire(.catStatue)
  }

}
