/// A reusable component for rendering a title and optional description
/// Used in Inventory, Item inspection, and Library views
final class ItemDescriptionView {
  private let itemCallout = Callout(style: .itemDescription)

  /// Title text to render (e.g. item name or document title)
  var title: String = ""

  /// Optional description text (e.g. item description). Leave empty for none
  var descriptionText: String = ""

  init() {
    // Default initializer; no content
  }

  /// Draw the item description at the bottom-right of the screen
  @MainActor func draw() {
    //    itemCallout.draw()

    //Gradient(colors: [.red, .blue])
    // Rect.zero.

    let panelWidth: Float = 512
    let panelHeight: Float = 128
    let marginY: Float = 96
    let paddingX: Float = 32
    let paddingY: Float = 20

    let dividerGradient = Gradient(colors: [.white.withAlphaComponent(0.15), .clear], locations: [0.6, 1.0])

    let panelX = Engine.viewportSize.width - panelWidth + paddingX / 2
    let topDivider = Rect(x: panelX, y: marginY + panelHeight, width: 512, height: 2)
    // let middleDivider = Rect(x: panelX, y: marginY + panelHeight - paddingY, width: 512, height: 2)
    let bottomDivider = Rect(x: panelX, y: marginY, width: 512, height: 2)

    topDivider.fill(with: dividerGradient)
    // middleDivider.fill(with: dividerGradient)
    bottomDivider.fill(with: dividerGradient)

    let labelX: Float = Engine.viewportSize.width - panelWidth + paddingX
    let labelY: Float = marginY + panelHeight - paddingY
    let descriptionY = labelY - 32
    let wrapWidth = panelWidth - paddingX * 2 - 96  // = 352; 330?

    title.draw(at: Point(labelX, labelY), style: .itemName)

    if !descriptionText.isEmpty {
      descriptionText.draw(at: Point(labelX, descriptionY), style: .itemDescription, wrapWidth: wrapWidth)
    }
  }
}
