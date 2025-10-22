/// A reusable component for rendering a title and optional description
/// Used in Inventory, Item inspection, and Library views
final class ItemDescriptionView {
  private let itemCallout = Callout(style: .itemDescription)

  /// Title text to render (e.g. item name or document title)
  var title: String = "" { didSet { /* no-op */  } }

  /// Optional description text (e.g. item description). Leave empty for none
  var descriptionText: String = "" { didSet { /* no-op */  } }

  init() {
    // Default initializer; no content
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

    title.draw(at: Point(labelX, labelY), style: .itemName)
    if !descriptionText.isEmpty {
      descriptionText.draw(at: Point(labelX, descriptionY), style: .itemDescription, wrapWidth: wrapWidth)
    }
  }
}
