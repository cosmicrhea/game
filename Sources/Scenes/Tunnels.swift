@SceneScript
class Tunnels: Script {

  private var thirdRailTouches = 0

  func door() {
    goTo(scene: "nexus", entry: "1")
  }

  func thirdRail() async {
    thirdRailTouches += 1

    if thirdRailTouches < 10 {
      await say(["It's the third rail.", "I better not touch it."])
    } else {
      await say("It's the third rail.", more: true)
      if await confirm("Will you touch it?", "Touch it", "Leave it alone") {
        die()
      }
    }
  }

}
