import GL
import GLFW
import GLMath

/// An action that can be performed on a slot.
public enum SlotAction: String, CaseIterable {
  case use, inspect, combine, discard
}

extension SlotAction {
  var id: String { rawValue }
  var label: String { rawValue.titleCased }

  var icon: Image? {
    switch self {
    case .use: return Image("UI/Icons/phosphor-icons/gear-bold.svg", size: 20)
    case .inspect: return Image("UI/Icons/phosphor-icons/magnifying-glass-bold.svg", size: 20)
    case .combine: return Image("UI/Icons/phosphor-icons/plus-circle-bold.svg", size: 20)
    case .discard: return Image("UI/Icons/phosphor-icons/trash-bold.svg", size: 20)
    }
  }

  func isEnabled(for slotIndex: Int) -> Bool {
    switch self {
    case .use, .inspect, .combine, .discard:
      return true
    }
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

  /// Show the slot menu for a specific slot
  public func showForSlot(
    at position: Point,
    slotIndex: Int,
    slotPosition: Point,
    availableActions: [SlotAction] = [.use, .inspect, .combine, .discard],
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
