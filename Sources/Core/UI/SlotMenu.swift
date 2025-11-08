/// An action that can be performed on a slot.
public enum SlotAction: String, CaseIterable {
  case use
  case equip
  case unequip
  case inspect
  case combine
  case exchange
  case discard
}

extension SlotAction {
  var id: String { rawValue }
  var label: String { rawValue.titleCased }

  var icon: Image? {
    switch self {
    case .use: return Image("UI/Icons/phosphor-icons/gear-bold.svg", size: 20)
    case .equip: return Image("UI/Icons/gun.svg", size: 20)
    case .unequip: return Image("UI/Icons/gun.svg", size: 20)
    case .inspect: return Image("UI/Icons/phosphor-icons/magnifying-glass-bold.svg", size: 20)
    case .combine: return Image("UI/Icons/phosphor-icons/plus-circle-bold.svg", size: 20)
    //    case .exchange: return Image("UI/Icons/phosphor-icons/hand-arrow-up-bold.svg", size: 20)
    case .exchange: return Image("UI/Icons/phosphor-icons/arrows-down-up-bold.svg", size: 20)
    case .discard: return Image("UI/Icons/phosphor-icons/trash-bold.svg", size: 20)
    }
  }

  func isEnabled(for slotIndex: Int) -> Bool {
    true
  }
}

/// A menu for slot interactions.
@MainActor
public final class SlotMenu: PopupMenu {

  // MARK: - Properties
  public var slotIndex: Int = 0
  public var slotPosition: Point = Point(0, 0)
  public var onAction: ((SlotAction, Int) -> Void)?

  public override init() {
    super.init()
  }

  // MARK: - Public Methods

  /// Default available actions for slot menu
  @usableFromInline
  static var defaultAvailableActions: [SlotAction] {
    var actions: [SlotAction] = [.use, .inspect, .combine, .discard]
    if TWO_PLAYER_MODE {
      actions.insert(.exchange, at: 3)
    }
    return actions
  }

  /// Show the slot menu for a specific slot
  public func showForSlot(
    at position: Point,
    slotIndex: Int,
    slotPosition: Point,
    availableActions: [SlotAction] = SlotMenu.defaultAvailableActions,
    openedWithKeyboard: Bool = false,
    slotSize: Size
  ) {
    self.slotIndex = slotIndex
    self.slotPosition = slotPosition

    let menuItems = createMenuItems(for: availableActions)
    show(at: position, items: menuItems, openedWithKeyboard: openedWithKeyboard, triggerSize: slotSize)
  }

  /// Show the slot menu with custom actions
  public func showWithCustomActions(
    at position: Point,
    slotIndex: Int,
    slotPosition: Point,
    actions: [(String, SlotAction)]
  ) {
    self.slotIndex = slotIndex
    self.slotPosition = slotPosition

    let menuItems = actions.map { (label, action) in
      MenuItem(
        id: action.id,
        label: label,
        icon: action.icon,
        isEnabled: true
      ) { [weak self] in
        self?.handleAction(action)
      }
    }

    show(at: position, items: menuItems)
  }

  // MARK: - Private Methods

  private func createMenuItems(for actions: [SlotAction]) -> [MenuItem] {
    return actions.map { action in
      MenuItem(
        id: action.id,
        label: action.label,
        icon: action.icon,
        isEnabled: action.isEnabled(for: slotIndex)
      ) { [weak self] in
        self?.handleAction(action)
      }
    }
  }

  private func handleAction(_ action: SlotAction) {
    onAction?(action, slotIndex)
  }
}
