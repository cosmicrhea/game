/// A box for an array of slots.
@MainActor
public final class Inventory {
  public var slots: [ItemSlotData?]

  public init(slots: [ItemSlotData?]) {
    self.slots = slots
  }

  /// Global player 1 inventory
  private nonisolated(unsafe) static var _player1: Inventory? = nil

  public static var player1: Inventory {
    if _player1 == nil {
      _player1 = Inventory(slots: [
        ItemSlotData(item: .sigp320, quantity: 17),
        ItemSlotData(item: .handgunAmmo, quantity: 69),
        ItemSlotData(item: .knife, quantity: nil),
        ItemSlotData(item: .morphine, quantity: nil),
        ItemSlotData(item: .metroKey, quantity: nil),
        //        ItemSlotData(item: .m32, quantity: 6),
        //        ItemSlotData(item: .grenadeRounds, quantity: 9),
        ItemSlotData(item: nil, quantity: nil),
        ItemSlotData(item: nil, quantity: nil),

        ItemSlotData(item: nil, quantity: nil),
        ItemSlotData(item: nil, quantity: nil),
        ItemSlotData(item: nil, quantity: nil),
        ItemSlotData(item: nil, quantity: nil),
        ItemSlotData(item: nil, quantity: nil),
        ItemSlotData(item: nil, quantity: nil),
        ItemSlotData(item: nil, quantity: nil),
        ItemSlotData(item: nil, quantity: nil),
        ItemSlotData(item: nil, quantity: nil),

        //        ItemSlotData(item: .knife, quantity: nil),
        //        ItemSlotData(item: .glock17, quantity: 15),
        //        ItemSlotData(item: .handgunAmmo, quantity: 69),
        //        ItemSlotData(item: .sigp320, quantity: 0),
        //        ItemSlotData(item: .morphine, quantity: nil),
        //        ItemSlotData(item: .glock18, quantity: 17),
        //        ItemSlotData(item: .metroKey, quantity: nil),
        //        ItemSlotData(item: .utilityKey, quantity: nil),
        //        ItemSlotData(item: nil, quantity: nil),
        //        ItemSlotData(item: nil, quantity: nil),
        //        ItemSlotData(item: nil, quantity: nil),
        //        ItemSlotData(item: nil, quantity: nil),
        //        ItemSlotData(item: nil, quantity: nil),
        //        ItemSlotData(item: nil, quantity: nil),
        //        ItemSlotData(item: nil, quantity: nil),
        //        ItemSlotData(item: nil, quantity: nil),

        //        ItemSlotData(item: .morphine, quantity: nil),
        //        ItemSlotData(item: .knife, quantity: nil),
        //        ItemSlotData(item: .glock17, quantity: 15),
        //        ItemSlotData(item: .glock18, quantity: 17),
        //        ItemSlotData(item: .sigp320, quantity: 0),
        //        ItemSlotData(item: .fnx45, quantity: 15),
        //        ItemSlotData(item: .handgunAmmo, quantity: 69),
        //        ItemSlotData(item: .utilityKey, quantity: nil),
        //        ItemSlotData(item: .metroKey, quantity: nil),
        //        ItemSlotData(item: .cryoGloves, quantity: nil),
        //        ItemSlotData(item: .lighter, quantity: nil),
        //        ItemSlotData(item: .beretta92, quantity: 17),
        //        ItemSlotData(item: .remington870, quantity: 8),
        //        ItemSlotData(item: .spas12, quantity: 10),
        //        ItemSlotData(item: .mp5sd, quantity: 30),
        //        ItemSlotData(item: nil, quantity: nil),  // Empty slot

        // (.morphine, nil),
        // (.knife, nil),
        // (.glock17, 15),
        // (.glock18, 17),
        // (.sigp320, 0),
        // //      (.beretta92, 17),
        // (.fnx45, 15),
        // (.handgunAmmo, 69),
        // (.utilityKey, nil),
        // (.metroKey, nil),
        // //      (.tagKey, nil),
        // (.cryoGloves, nil),
        // (.lighter, nil),
        // //      (.remington870, 8),
        // //      (.spas12, 10),
        // //      (.mp5sd, 30),
      ])
    }

    return _player1!
  }
}
