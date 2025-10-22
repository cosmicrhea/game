/// A reusable component for rendering item names and descriptions
/// Used in both InventoryView and ItemView for consistent item information display
final class ItemDescriptionView {
  private let itemCallout = Callout(style: .itemDescription)

  /// The item to display information for
  var item: Item? {
    didSet {
      updateItemLabel()
    }
  }

  /// The current item name being displayed
  private var currentItemName: String = ""

  /// The current item description being displayed
  private var currentItemDescription: String = ""

  init() {
    // Initialize with empty state
    updateItemLabel()
  }

  /// Update the item label based on the current item
  private func updateItemLabel() {
    if let item = item {
      currentItemName = item.name
      currentItemDescription = item.description ?? ""
    } else {
      currentItemName = ""
      currentItemDescription = ""
    }
  }

  /// Draw the item description at the bottom-right of the screen
  @MainActor func draw() {
    itemCallout.draw()

    let panelWidth: Float = 480
    let panelHeight: Float = 128
    let marginY: Float = 96
    let paddingX: Float = 32
    let paddingY: Float = 22

    let labelX: Float = Engine.viewportSize.width - panelWidth + paddingX
    let labelY: Float = marginY + panelHeight - paddingY
    let descriptionY = labelY - 32
    let wrapWidth = panelWidth - paddingX * 2 - 96

    currentItemName.draw(at: Point(labelX, labelY), style: .itemName)
    currentItemDescription.draw(at: Point(labelX, descriptionY), style: .itemDescription, wrapWidth: wrapWidth)
  }
}
