@MainActor
final class UIDemo: RenderLoop {
  private let indicator = ProgressIndicator()
  private let tfBasic = TextField(frame: Rect(x: 20, y: 90, width: 360, height: 36), text: "Hello")
  private let tfPlaceholder = TextField(frame: Rect(x: 20, y: 140, width: 360, height: 36), text: "")
  private let tfMultiline = TextField(
    frame: Rect(x: 20, y: 190, width: 480, height: 90), text: "This is a\nmultiline\nfield.", singleLine: false)

  init() {}

  func update(deltaTime: Float) {
    indicator.update(deltaTime: deltaTime)
  }

  func draw() {
    // UI background
    GraphicsContext.current?.renderer.setClearColor(Color(0.08, 0.08, 0.1, 1))

    // Title text
    let titleStyle = TextStyle(fontName: "Determination", fontSize: 28, color: .white)
    "UI Demo — Progress Indicator".draw(
      at: Point(20, 20),
      style: titleStyle,
      anchor: .topLeft
    )

    // Spinner
    indicator.draw()

    // Hint
    let hintStyle = TextStyle(fontName: "CreatoDisplay-Bold", fontSize: 14, color: .gray300)
    "Spinning circle shows center-aligned UI indicator".draw(
      at: Point(20, 54),
      style: hintStyle,
      anchor: .topLeft
    )

    // TextField demos
    "Basic".draw(
      at: Point(20, 84), style: TextStyle(fontName: "CreatoDisplay-Bold", fontSize: 14, color: .gray400),
      anchor: .bottomLeft)
    tfBasic.draw()

    "With placeholder".draw(
      at: Point(20, 134), style: TextStyle(fontName: "CreatoDisplay-Bold", fontSize: 14, color: .gray400),
      anchor: .bottomLeft)
    tfPlaceholder.placeholder = "Search…"
    tfPlaceholder.draw()

    "Multiline".draw(
      at: Point(20, 184), style: TextStyle(fontName: "CreatoDisplay-Bold", fontSize: 14, color: .gray400),
      anchor: .bottomLeft)
    tfMultiline.draw()
  }

  // MARK: - Input

  func onKeyPressed(window: Window, key: Keyboard.Key, scancode: Int32, mods: Keyboard.Modifier) {
    // Forward navigation/editing keys to the focused field
    if tfBasic.isFocused {
      if tfBasic.handleKey(key) { return }
      if let s = mapKeyToCharacter(key, mods: mods) {
        _ = tfBasic.insertText(s)
        return
      }
    } else if tfPlaceholder.isFocused {
      if tfPlaceholder.handleKey(key) { return }
      if let s = mapKeyToCharacter(key, mods: mods) {
        _ = tfPlaceholder.insertText(s)
        return
      }
    } else if tfMultiline.isFocused {
      if tfMultiline.handleKey(key) { return }
      if let s = mapKeyToCharacter(key, mods: mods) {
        _ = tfMultiline.insertText(s)
        return
      }
    }
  }

  func onMouseButtonPressed(window: Window, button: Mouse.Button, mods: Keyboard.Modifier) {
    guard button == .left else { return }
    let p = mousePoint(window)
    // Manage focus and dispatch mouse down to whichever is hit
    var consumed = false
    for field in [tfBasic, tfPlaceholder, tfMultiline] {
      field.isFocused = false
    }
    for field in [tfMultiline, tfPlaceholder, tfBasic] {  // top-most first if overlapping
      if field.frame.contains(p) {
        field.isFocused = true
        consumed = field.handleMouseDown(at: p) || consumed
        break
      }
    }
  }

  func onMouseMove(window: Window, x: Double, y: Double) {
    let p = mousePoint(window)
    for field in [tfBasic, tfPlaceholder, tfMultiline] { field.handleMouseMove(at: p) }
  }

  func onMouseButtonReleased(window: Window, button: Mouse.Button, mods: Keyboard.Modifier) {
    guard button == .left else { return }
    for field in [tfBasic, tfPlaceholder, tfMultiline] { field.handleMouseUp() }
  }

  // MARK: - Helpers

  private func mousePoint(_ window: Window) -> Point {
    Point(Float(window.mouse.position.x), Float(Engine.viewportSize.height) - Float(window.mouse.position.y))
  }

  private func mapKeyToCharacter(_ key: Keyboard.Key, mods: Keyboard.Modifier) -> String? {
    let shifted = mods.contains(.shift)
    switch key {
    case .space: return " "
    case .apostrophe: return shifted ? "\"" : "'"
    case .comma: return shifted ? "<" : ","
    case .period: return shifted ? ">" : "."
    case .slash: return shifted ? "?" : "/"
    case .minus: return shifted ? "_" : "-"
    case .equal: return shifted ? "+" : "="
    case .semicolon: return shifted ? ":" : ";"
    case .num0: return shifted ? ")" : "0"
    case .num1: return shifted ? "!" : "1"
    case .num2: return shifted ? "@" : "2"
    case .num3: return shifted ? "#" : "3"
    case .num4: return shifted ? "$" : "4"
    case .num5: return shifted ? "%" : "5"
    case .num6: return shifted ? "^" : "6"
    case .num7: return shifted ? "&" : "7"
    case .num8: return shifted ? "*" : "8"
    case .num9: return shifted ? "(" : "9"
    case .a: return shifted ? "A" : "a"
    case .b: return shifted ? "B" : "b"
    case .c: return shifted ? "C" : "c"
    case .d: return shifted ? "D" : "d"
    case .e: return shifted ? "E" : "e"
    case .f: return shifted ? "F" : "f"
    case .g: return shifted ? "G" : "g"
    case .h: return shifted ? "H" : "h"
    case .i: return shifted ? "I" : "i"
    case .j: return shifted ? "J" : "j"
    case .k: return shifted ? "K" : "k"
    case .l: return shifted ? "L" : "l"
    case .m: return shifted ? "M" : "m"
    case .n: return shifted ? "N" : "n"
    case .o: return shifted ? "O" : "o"
    case .p: return shifted ? "P" : "p"
    case .q: return shifted ? "Q" : "q"
    case .r: return shifted ? "R" : "r"
    case .s: return shifted ? "S" : "s"
    case .t: return shifted ? "T" : "t"
    case .u: return shifted ? "U" : "u"
    case .v: return shifted ? "V" : "v"
    case .w: return shifted ? "W" : "w"
    case .x: return shifted ? "X" : "x"
    case .y: return shifted ? "Y" : "y"
    case .z: return shifted ? "Z" : "z"
    default: return nil
    }
  }
}
