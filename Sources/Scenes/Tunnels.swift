@SceneScript
class Tunnels: Script {

  private var thirdRailTouches = 0

  func door() {
    goTo(scene: "nexus", entry: "1")
  }

  func thirdRail() {
    thirdRailTouches += 1

    if thirdRailTouches >= 10 {
      die()
    } else if thirdRailTouches >= 7 {
      say("I really shouldn't keep doing this...")
    } else if thirdRailTouches >= 4 {
      say("Maybe I should stop touching this.")
    } else {
      say(["It's the third rail.", "I better not touch it."])
    }
  }

}
