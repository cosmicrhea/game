/// Demo showcasing SVG loading and rendering capabilities
@Editor final class SVGDemo: RenderLoop {
  private var svgData: [(image: Image, name: String)] = []
  @Editable(range: 16...128) var iconSize: Float = 64.0
  private let iconSizes: [Float] = [16, 24, 32, 48, 64, 80, 96, 112, 128]
  private var currentSizeIndex: Int = 4  // Start at 64
  private var svgPaths: [String] = []  // Store original paths for reloading

  // Stroke width controls
  private var strokeWidth: Float? = nil  // nil = use original
  private let strokeWidths: [Float?] = [nil, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0, 6.0, 8.0, 10.0]
  private var currentStrokeIndex: Int = 0  // Start at nil (original)

  init() {
    guard let bundleURL = Bundle.game.url(forResource: "UI/Icons/test", withExtension: nil) else { return }

    let fileManager = FileManager.default
    do {
      let contents = try fileManager.contentsOfDirectory(at: bundleURL, includingPropertiesForKeys: nil)
      let svgFiles = contents.filter { $0.pathExtension.lowercased() == "svg" }

      for svgURL in svgFiles {
        let relativePath = "UI/Icons/test/\(svgURL.lastPathComponent)"
        if Image.validateSVG(svgPath: relativePath) {
          svgPaths.append(relativePath)
        }
      }

      loadImages()
    } catch {
      // Silently handle errors
    }
  }

  private func loadImages() {
    svgData.removeAll()
    // for path in svgPaths {
    //   let image = Image(path, size: Size(iconSize, iconSize), strokeWidth: strokeWidth)
    //   let name = URL(fileURLWithPath: path).lastPathComponent.replacingOccurrences(of: ".svg", with: "")
    //   svgData.append((image: image, name: name))
    // }

    let testIcons = [
      "gear", "hand-arrow-up", "gps-fix", "magnifying-glass", "trash", "plus-circle", "eye", "arrow-square-out",
      "arrows-down-up", "arrows-left-right", "map-pin-area", "user", "files",
    ]

    for icon in testIcons {
      let image = Image("UI/Icons/phosphor-icons/\(icon)-bold.svg", size: Size(iconSize, iconSize))
      svgData.append((image: image, name: icon))
    }
  }

//  func onKeyPressed(window: Window, key: Keyboard.Key, scancode: Int32, mods: Keyboard.Modifier) {
//    switch key {
//    case .minus:
//      if currentSizeIndex > 0 {
//        currentSizeIndex -= 1
//        iconSize = iconSizes[currentSizeIndex]
//        loadImages()  // Reload images at new size
//        UISound.select()
//      }
//    case .equal:
//      if currentSizeIndex < iconSizes.count - 1 {
//        currentSizeIndex += 1
//        iconSize = iconSizes[currentSizeIndex]
//        loadImages()  // Reload images at new size
//        UISound.select()
//      }
//    case .q:  // Q key - decrease stroke width
//      if currentStrokeIndex > 0 {
//        currentStrokeIndex -= 1
//        strokeWidth = strokeWidths[currentStrokeIndex]
//        loadImages()  // Reload images with new stroke width
//        UISound.select()
//      }
//    case .e:  // E key - increase stroke width
//      if currentStrokeIndex < strokeWidths.count - 1 {
//        currentStrokeIndex += 1
//        strokeWidth = strokeWidths[currentStrokeIndex]
//        loadImages()  // Reload images with new stroke width
//        UISound.select()
//      }
//    default:
//      break
//    }
//  }

  func draw() {
    guard !svgData.isEmpty else { return }
    guard GraphicsContext.current != nil else { return }

    let padding: Float = 32.0
    let iconsPerRow = 8
    let textStyle = TextStyle(
      fontName: "CreatoDisplay-Bold",
      fontSize: 13,
      color: .gray300,
      alignment: .center
    )

    for (index, data) in svgData.enumerated() {
      let col = index % iconsPerRow
      let row = index / iconsPerRow

      let x = Float(col) * (iconSize + padding) + padding
      let y = Float(row) * (iconSize + padding) + padding

      let rect = Rect(origin: Point(x, y), size: Size(iconSize, iconSize))
      data.image.draw(in: rect, tint: .white)

      if Config.current.wireframeMode {
        rect.frame(with: .rose, lineWidth: 2)
      }

      // Draw icon name underneath - manually center it
      let textSize = data.name.size(with: textStyle)
      let textX = x + (iconSize - textSize.width) / 2
      let textY = y - 16

      data.name.draw(
        at: Point(textX, textY),
        style: textStyle,
        anchor: .bottomLeft
      )
    }
  }
}
