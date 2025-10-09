import class GLFW.GLFWWindow
import struct GLFW.Keyboard
import enum GLFW.ButtonState

typealias Window = GLFW.GLFWWindow

protocol RenderLoop {
  @MainActor func onAttach(window: Window)
  @MainActor func onDetach(window: Window)
  @MainActor func onKey(
    window: Window, key: Keyboard.Key, scancode: Int32, state: ButtonState, mods: Keyboard.Modifier
  ) -> Bool
  @MainActor func onMouseMove(window: Window, x: Double, y: Double) -> Bool
  @MainActor func onScroll(window: Window, xOffset: Double, yOffset: Double) -> Bool
  @MainActor func update(deltaTime: Float)
  @MainActor func update(window: Window, deltaTime: Float)
  @MainActor func draw()
}

extension RenderLoop {
  @MainActor func onAttach(window: Window) {}
  @MainActor func onDetach(window: Window) {}
  @MainActor func onKey(
    window: Window, key: Keyboard.Key, scancode: Int32, state: ButtonState, mods: Keyboard.Modifier
  ) -> Bool { return false }
  @MainActor func onMouseMove(window: Window, x: Double, y: Double) -> Bool { return false }
  @MainActor func onScroll(window: Window, xOffset: Double, yOffset: Double) -> Bool { return false }
  @MainActor func update(deltaTime: Float) {}
  @MainActor func update(window: Window, deltaTime: Float) { update(deltaTime: deltaTime) }
}
