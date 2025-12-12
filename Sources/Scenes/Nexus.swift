@SceneScript
class Nexus: Script {

  @Flag var hasCollectedCat = false
  @Ref var catStatue: Node

  override func sceneDidLoad() {
    if hasCollectedCat {
      catStatue.isHidden = true
    }
  }

  func cat() async {
    if hasCollectedCat {
      await say("Already picked that up.")
      return
    }

    guard !catStatue.isHidden else { return }
    if await acquire(.catStatue) {
      catStatue.isHidden = true
      hasCollectedCat = true
      //removeActiveTrigger() // ???
    }
  }

  func door1() async {
    if await confirm("Go to the shooting range?", "Go through", "Stay here") {
      await goTo(scene: "shooting_range", entry: "range")
    }
  }

  func door2() async {
    if await confirm("Go to the shooting range hallway?", "Go through", "Stay here") {
      await goTo(scene: "shooting_range", entry: "hallway")
    }
  }

  func door3() async {
    if await confirm("Go to the test room?", "Go through", "Stay here") {
      await goTo(scene: "test")
    }
  }

  func door4() async {
    if await confirm("Go to the tunnels?", "Go through", "Stay here") {
      await goTo(scene: .tunnels)
    }
  }

  func door5() async {
    if await confirm("Open the door?", "Open", "Stay here") {
      UISound.lockedA()
      await say("It's locked.")
    }
  }

  func door6() async {
    print(await ask("What's your favorite number?", options: ["1", "2", "3", "4"]))

    await say("Nothing happened.")

    //  UISound.lockedB()
    //  say("It's locked.")
  }

  func door7() { UISound.lockedA(); say("It's locked.") }

  func door8() { goTo(scene: "chiefs_office") }

}
