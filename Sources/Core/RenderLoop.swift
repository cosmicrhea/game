import enum GLFW.ButtonState
@preconcurrency import class GLFW.GLFWWindow
import struct GLFW.Keyboard
import struct GLFW.Mouse

public typealias Window = GLFW.GLFWWindow

@MainActor
protocol RenderLoop {
  func onAttach(window: Window)
  func onDetach(window: Window)
  func onKey(
    window: Window, key: Keyboard.Key, scancode: Int32, state: ButtonState, mods: Keyboard.Modifier
  )
  func onMouseMove(window: Window, x: Double, y: Double)
  func onScroll(window: Window, xOffset: Double, yOffset: Double)
  func onMouseButton(window: Window, button: Mouse.Button, state: ButtonState, mods: Keyboard.Modifier)
  func onKeyPressed(window: Window, key: Keyboard.Key, scancode: Int32, mods: Keyboard.Modifier)
  func onMouseButtonPressed(window: Window, button: Mouse.Button, mods: Keyboard.Modifier)
  func onMouseButtonReleased(window: Window, button: Mouse.Button, mods: Keyboard.Modifier)
  func onTextInput(window: Window, text: String)
  func update(deltaTime: Float)
  func update(window: Window, deltaTime: Float)
  func draw()
}

extension RenderLoop {
  func onAttach(window: Window) {}
  func onDetach(window: Window) {}
  func onKey(
    window: Window, key: Keyboard.Key, scancode: Int32, state: ButtonState, mods: Keyboard.Modifier
  ) {}
  func onMouseMove(window: Window, x: Double, y: Double) {}
  func onScroll(window: Window, xOffset: Double, yOffset: Double) {}
  func onMouseButton(window: Window, button: Mouse.Button, state: ButtonState, mods: Keyboard.Modifier) {}
  func onKeyPressed(window: Window, key: Keyboard.Key, scancode: Int32, mods: Keyboard.Modifier) {}
  func onMouseButtonPressed(window: Window, button: Mouse.Button, mods: Keyboard.Modifier) {}
  func onMouseButtonReleased(window: Window, button: Mouse.Button, mods: Keyboard.Modifier) {}
  func onTextInput(window: Window, text: String) {}
  func update(deltaTime: Float) {}
  func update(window: Window, deltaTime: Float) {
    update(deltaTime: deltaTime)
  }
}
