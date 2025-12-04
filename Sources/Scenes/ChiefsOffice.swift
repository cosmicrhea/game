@SceneScript
class ChiefsOffice: Script {

  @Ref var desk: Camera
  @Ref var laptop: Camera

  func chiefsDoor() {
    goTo(scene: "nexus", entry: "8")
  }

  func laptop() async {
    await withCloseup(on: desk) {
      await say("Looks like chief is working on something.", more: true)
    }

    await withCloseup(on: laptop) {
      await pause()
      await say("What the hell?!")
    }
  }

}
