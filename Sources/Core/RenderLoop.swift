import Foundation
import GLFW

protocol RenderLoop {
  @MainActor func onAttach(window: GLFWWindow)
  @MainActor func onDetach(window: GLFWWindow)
  @MainActor func onKey(window: GLFWWindow, key: Keyboard.Key, scancode: Int32, state: ButtonState, mods: Keyboard.Modifier) -> Bool
  @MainActor func onMouseMove(window: GLFWWindow, x: Double, y: Double) -> Bool
  @MainActor func onScroll(window: GLFWWindow, xOffset: Double, yOffset: Double) -> Bool
  @MainActor func update(deltaTime: Float)
  @MainActor func draw()
}

extension RenderLoop {
  @MainActor func onAttach(window: GLFWWindow) {}
  @MainActor func onDetach(window: GLFWWindow) {}
  @MainActor func onKey(window: GLFWWindow, key: Keyboard.Key, scancode: Int32, state: ButtonState, mods: Keyboard.Modifier) -> Bool { return false }
  @MainActor func onMouseMove(window: GLFWWindow, x: Double, y: Double) -> Bool { return false }
  @MainActor func onScroll(window: GLFWWindow, xOffset: Double, yOffset: Double) -> Bool { return false }
  @MainActor func update(deltaTime: Float) {}
}
