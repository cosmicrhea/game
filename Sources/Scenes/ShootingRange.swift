@SceneScript
class ShootingRange: Script {

  let locked = false

  @FindNode var catStatue: Node

  func door() {
    if locked {
      frontDoor()
    } else {
      // Toggle between hallway and Entry_1 based on current area
      if currentArea == "hallway" {
        go(to: "Entry_1")
      } else {
        go(to: "hallway")
      }
    }
  }

  func frontDoor() {
    //play(.doorLocked, at: currentActionTriggerNodeThingy)
    go(toScene: "test")
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
