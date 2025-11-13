/// Sort order for items in storage list
public enum ItemSortOrder: String, CaseIterable {
  case key
  case weapon
  case ammo
  case recovery

  public var label: String {
    rawValue.titleCased
  }

  /// Get the sort priority for an item kind
  public func sortPriority(for itemKind: ItemKind) -> Int {
    switch (self, itemKind) {
    case (.key, .key): return 0
    case (.weapon, .weapon): return 0
    case (.ammo, .ammo): return 0
    case (.recovery, .recovery): return 0
    default: return 999  // Items not matching sort order go to end
    }
  }
}


