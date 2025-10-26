class MetroMaintenanceRoom: Script {

  func bulletinBoard() {
    say("Various postings for the Metro employees.")
    say("Nothing too important, just updates.")
    acquire(.photoD)
  }

  func corridorDoor() {
    //goTo(.metroMaintenanceCorridor)
  }

}
