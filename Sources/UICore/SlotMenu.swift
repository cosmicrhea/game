import GL
import GLFW
import GLMath

/// A context menu specifically for slot interactions
@MainActor
public final class SlotMenu: ContextMenu {

  // MARK: - Slot Actions
  public enum SlotAction {
    case use
    case inspect
    case move
    case discard
  }

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
    availableActions: [SlotAction] = [.use, .inspect, .move, .discard]
  ) {
    self.slotIndex = slotIndex
    self.slotPosition = slotPosition

    let menuItems = createMenuItems(for: availableActions)
    show(at: position, items: menuItems)
  }

  /// Show the slot menu with custom actions
  public func showWithCustomActions(
    at position: Point, slotIndex: Int, slotPosition: Point, actions: [(String, SlotAction)]
  ) {
    self.slotIndex = slotIndex
    self.slotPosition = slotPosition

    let menuItems = actions.map { (label, action) in
      ContextMenu.MenuItem(
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

  private func createMenuItems(for actions: [SlotAction]) -> [ContextMenu.MenuItem] {
    return actions.map { action in
      ContextMenu.MenuItem(
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

extension SlotMenu.SlotAction {
  var id: String {
    switch self {
    case .use: return "use"
    case .inspect: return "inspect"
    case .move: return "move"
    case .discard: return "discard"
    }
  }

  var label: String {
    switch self {
    case .use: return "Use"
    case .inspect: return "Inspect"
    case .move: return "Move"
    case .discard: return "Discard"
    }
  }

  var icon: String? {
    switch self {
    case .use: return "UI/use_icon"
    case .inspect: return "UI/inspect_icon"
    case .move: return "UI/move_icon"
    case .discard: return "UI/discard_icon"
    }
  }

  func isEnabled(for slotIndex: Int) -> Bool {
    switch self {
    case .use, .inspect, .move, .discard:
      return true
    }
  }
}
