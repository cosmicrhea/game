@SceneScript
class Nexus: Script {

  @FindNode var catStatue: Node

  func cat() async {
    guard !catStatue.isHidden else { return }
    if await acquire(.catStatue) {
      catStatue.isHidden = true
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
