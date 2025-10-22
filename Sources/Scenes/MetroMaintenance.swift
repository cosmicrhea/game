import ObjectiveC

class Room: NSObject {

  func say(_ string: String) {}
  func acquire(_ item: Item) {}
  func acquire(_ document: Document) {}

}

class MetroMaintenance: Room {

  func bulletinBoard() {
    say("Various postings for the Metro employees.")
    say("Nothing too important, just updates.")
    acquire(.photoD)
    
  }

}
