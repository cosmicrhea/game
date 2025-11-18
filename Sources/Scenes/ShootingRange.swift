@SceneScript
class ShootingRange: Script {

  @FindNode var catStatue: Node

  func rangeDoor() {
    go(to: currentArea == "hallway" ? "range" : "hallway")
  }

  func frontDoor() {
    //play(.doorLocked, at: currentActionTriggerNodeThingy)
//    go(toScene: "test")
    go(toScene: "nexus")
    // UISound.lockedA()
    // say(variations: [
    //   "It's locked.",
    //   "It's locked!",
    //   "It's still locked.",
    //   "It's really locked.",
    //   "It's locked. I can't open it.",
    //   "It's fucking locked and I'm really freaking out.",
    //   "I'M TRAPPED AND I CAN'T GET OUT! HELP!",
    //   "HELP! HELP! HELP!",
    // ])
  }

  func tables() {
    say("Various equipment.")
  }

  func cabinet() {
    UISound.lockedB()
    say([
      "It's locked.",
      "I bet there's something cool in there.",
    ])
  }

  func cat() async {
    guard !catStatue.isHidden else { return }
    // await say("A cat has appeared.")
    await say("Whoa! There's a cat.", more: true)
    if await acquire(.catStatue) {
      catStatue.isHidden = true
    }
    //removeActiveTrigger() // ???
  }

}
