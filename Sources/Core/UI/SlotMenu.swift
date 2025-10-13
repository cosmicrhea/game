import GL
import GLFW
import GLMath

/// An action that can be performed on a slot.
public enum SlotAction: String, CaseIterable {
  case use
  case inspect
  case combine
  case discard
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
    at position: Point, slotIndex: Int, slotPosition: Point,
    availableActions: [SlotAction] = [.use, .inspect, .combine, .discard], openedWithKeyboard: Bool = false,
    slotSize: Size = Size(80, 80)
  ) {
    self.slotIndex = slotIndex
    self.slotPosition = slotPosition

    let menuItems = createMenuItems(for: availableActions)
    show(at: position, items: menuItems, openedWithKeyboard: openedWithKeyboard, triggerSize: slotSize)
  }

  /// Show the slot menu with custom actions
  public func showWithCustomActions(
    at position: Point, slotIndex: Int, slotPosition: Point, actions: [(String, SlotAction)]
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

// MARK: - SlotAction Extensions

extension SlotAction {
  var id: String { rawValue }
  var label: String { rawValue.titleCased }

  var icon: String? {
    switch self {
    case .use: return "UI/use_icon"
    case .inspect: return "UI/inspect_icon"
    case .combine: return "UI/combine_icon"
    case .discard: return "UI/discard_icon"
    }
  }

  func isEnabled(for slotIndex: Int) -> Bool {
    switch self {
    case .use, .inspect, .combine, .discard:
      return true
    }
  }
}
