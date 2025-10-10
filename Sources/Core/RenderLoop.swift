import enum GLFW.ButtonState
import class GLFW.GLFWWindow
import struct GLFW.Keyboard
import struct GLFW.Mouse

typealias Window = GLFW.GLFWWindow

protocol RenderLoop {
  @MainActor func onAttach(window: Window)
  @MainActor func onDetach(window: Window)
  @MainActor func onKey(
    window: Window, key: Keyboard.Key, scancode: Int32, state: ButtonState, mods: Keyboard.Modifier
  )
  @MainActor func onMouseMove(window: Window, x: Double, y: Double)
  @MainActor func onScroll(window: Window, xOffset: Double, yOffset: Double)
  @MainActor func onMouseButton(window: Window, button: Mouse.Button, state: ButtonState, mods: Keyboard.Modifier)
  @MainActor func onKeyPressed(window: Window, key: Keyboard.Key, scancode: Int32, mods: Keyboard.Modifier)
  @MainActor func onMouseButtonPressed(window: Window, button: Mouse.Button, mods: Keyboard.Modifier)
  @MainActor func update(deltaTime: Float)
  @MainActor func update(window: Window, deltaTime: Float)
  @MainActor func draw()
}

extension RenderLoop {
  @MainActor func onAttach(window: Window) {}
  @MainActor func onDetach(window: Window) {}
  @MainActor func onKey(
    window: Window, key: Keyboard.Key, scancode: Int32, state: ButtonState, mods: Keyboard.Modifier
  ) {}
  @MainActor func onMouseMove(window: Window, x: Double, y: Double) {}
  @MainActor func onScroll(window: Window, xOffset: Double, yOffset: Double) {}
  @MainActor func onMouseButton(window: Window, button: Mouse.Button, state: ButtonState, mods: Keyboard.Modifier) {}
  @MainActor func onKeyPressed(window: Window, key: Keyboard.Key, scancode: Int32, mods: Keyboard.Modifier) {}
  @MainActor func onMouseButtonPressed(window: Window, button: Mouse.Button, mods: Keyboard.Modifier) {}
  @MainActor func update(deltaTime: Float) {}
  @MainActor func update(window: Window, deltaTime: Float) { update(deltaTime: deltaTime) }
}
