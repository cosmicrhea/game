extension GLFW.Mouse.Cursor {
  @MainActor static let dot = {
    let image = GLFW.Image("UI/Cursors/dot_large.png")
    return Mouse.Cursor.custom(image, center: GLFW.Point(image.width, image.height) / 2)
  }()
}
