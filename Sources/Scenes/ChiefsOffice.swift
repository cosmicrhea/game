@SceneScript
class ChiefsOffice: Script {

  @Ref var desk: Camera
  @Ref var laptop: Camera
  @Ref var laptopScreen: Node

  func chiefsDoor() {
    goTo(scene: .nexus, entry: 8)
  }

  func laptop() async {
    await withPlayer(position: vec3(3.12, 1.2, -3.86), rotation: -12.32) {
      await withPlayerLookingAt(laptopScreen) {
        await withCloseupOn(desk) {
          await say("Looks like chief is working on something.", more: true)
        }

        await withCloseupOn(laptop) {
          await pause(1.0)
          await say("What the hell?!")
        }
      }
    }
  }

}
