/// A box for an array of slots.
@MainActor
public final class Inventory {
  public var slots: [ItemSlotData?]
  /// Slot index of the currently equipped weapon, if any
  public var equippedWeaponIndex: Int? = nil

  public init(slots: [ItemSlotData?], equippedWeaponIndex: Int? = nil) {
    self.slots = slots
    self.equippedWeaponIndex = equippedWeaponIndex
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

        ItemSlotData(item: .lighter, quantity: nil),
        ItemSlotData(item: .lighterFluid, quantity: nil),
        //ItemSlotData(item: .lighterWithFuel, quantity: nil),
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

  /// Global storage inventory (contains one of each available item)
  private nonisolated(unsafe) static var _storage: Inventory? = nil

  public static var storage: Inventory {
    if _storage == nil {
      // Create storage inventory with one of each available item
      var storageSlots: [ItemSlotData?] = []

      // Add all available items
      let allItems: [Item] = [
        // Recovery
        .morphine,
        // Melee
        .knife,
        // Handguns
        .glock17,
        .glock18,
        .sigp320,
        .beretta92,
        .fnx45,
        // Shotguns
        .remington870,
        .spas12,
        // SMGs
        .mp5sd,
        // Launchers
        .m32,
        // Ammo
        .handgunAmmo,
        .grenadeRounds,
        // Keys
        .utilityKey,
        .metroKey,
        .tagKey,
        // Other
        .cryoGloves,
        .lighter,
        .lighterFluid,
        .lighterWithFuel,
        .catStatue,
      ]

      // Add one of each item
      for item in allItems {
        // For weapons, add with default ammo quantity if applicable
        let quantity: Int? = {
          if case .weapon(_, _, let capacity, _) = item.kind, let capacity = capacity {
            return capacity
          }
          return nil
        }()
        storageSlots.append(ItemSlotData(item: item, quantity: quantity))
      }

      // Fill remaining slots with nil (empty)
      let totalSlots = 6 * 4  // 6 columns * 4 rows = 24 slots
      while storageSlots.count < totalSlots {
        storageSlots.append(nil)
      }

      _storage = Inventory(slots: storageSlots)
    }

    return _storage!
  }
}
