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

  func door1() { goTo(scene: "shooting_range", entry: "range") }
  func door2() { goTo(scene: "shooting_range", entry: "hallway") }
  func door3() { goTo(scene: "test") }
  func door4() { UISound.lockedB(); say("It's locked.") }
  func door5() { UISound.lockedA(); say("It's locked.") }
  func door6() { UISound.lockedB(); say("It's locked.") }
  func door7() { UISound.lockedA(); say("It's locked.") }
  func door8() { goTo(scene: "chiefs_office") }

}
