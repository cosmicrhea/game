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

  func door1() { go(toScene: "shooting_range", entry: "range") }
  func door2() { go(toScene: "shooting_range", entry: "hallway") }
  func door3() { go(toScene: "test") }
  func door4() { UISound.lockedB() }
  func door5() { UISound.lockedA() }
  func door6() { UISound.lockedB() }
  func door7() { UISound.lockedA() }
  func door8() { UISound.lockedA() }

}
