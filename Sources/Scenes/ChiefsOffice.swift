@SceneScript
class ChiefsOffice: Script {

  func chiefsDoor() {
    go(toScene: "nexus", entry: "8")
  }

  func laptop() async {
    await withCloseup(on: "Reference") {
      await say("Looks like chief is working on something.")
    }
  }

}
