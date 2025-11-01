// TODO: hack hi-dpi support into GLFW
extension GLFW.Mouse.Cursor {
  @MainActor static let regular = {
    let image = GLFW.Image("UI/Cursors/cursor_none.png")
    return Mouse.Cursor.custom(image, center: GLFW.Point(11, 7))
  }()

  @MainActor static let dot = {
    let image = GLFW.Image("UI/Cursors/dot_large.png")
    return Mouse.Cursor.custom(image, center: GLFW.Point(image.width, image.height) / 2)
  }()
}
