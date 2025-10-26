class DebugRoom: Script {

  func ladder() {
    if confirm("There is a ladder here. Will you climb down?", "Climb down", "Stay here") {
      //goTo(.debugRoom)
    }
  }

  func keypad() {
    //loadCloseup("keypad")
  }

}
