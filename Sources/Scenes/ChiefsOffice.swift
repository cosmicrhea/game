@SceneScript
class ChiefsOffice: Script {

  func chiefsDoor() {
    goTo(scene: "nexus", entry: "8")
  }

  func laptop() async {
    await script {
      withCloseup(on: "desk") {
        await say("Looks like chief is working on something.", more: true)
      }

      withCloseup(on: "laptop") {
        await pause(1.0)
        await say("What the hell?!")
      }
    }
  }

}
