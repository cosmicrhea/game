import Foundation
import GLFW

// MARK: - Gamepad Navigation Cooldown

/// Simple helper for managing gamepad navigation cooldowns.
public struct GamepadNavigationCooldown {
  private var cooldown: Float = 0.0
  public let duration: Float

  public init(duration: Float = 0.2) {
    self.duration = duration
  }

  /// Update cooldown timer, returns true if cooldown is ready.
  public mutating func update(deltaTime: Float) -> Bool {
    cooldown = max(0, cooldown - deltaTime)
    return cooldown <= 0
  }

  /// Reset cooldown to full duration.
  public mutating func reset() {
    cooldown = duration
  }

  /// Check if cooldown is ready without updating.
  public var isReady: Bool {
    cooldown <= 0
  }
}

// MARK: - Gamepad Button Press Detector

/// Helper for detecting new button presses (not holds).
public struct GamepadButtonPressDetector {
  private var previousStates: Set<Gamepad.Button> = []

  /// Update state and return set of newly pressed buttons.
  @MainActor
  public mutating func update(from gamepad: Gamepad, buttons: [Gamepad.Button]) -> Set<Gamepad.Button> {
    var currentPressed: Set<Gamepad.Button> = []
    var newlyPressed: Set<Gamepad.Button> = []

    for button in buttons {
      if gamepad.state(of: button) == .pressed {
        currentPressed.insert(button)
        if !previousStates.contains(button) {
          newlyPressed.insert(button)
        }
      }
    }

    previousStates = currentPressed
    return newlyPressed
  }

  /// Check if a specific button is newly pressed (updates internal state).
  @MainActor
  public mutating func isNewlyPressed(_ button: Gamepad.Button, in gamepad: Gamepad) -> Bool {
    let buttons = [button]
    let newlyPressed = update(from: gamepad, buttons: buttons)
    return newlyPressed.contains(button)
  }

  /// Reset internal state (useful when component is hidden/shown).
  public mutating func reset() {
    previousStates.removeAll()
  }
}

// MARK: - Gamepad Navigation State

/// Helper for tracking D-pad and stick navigation state to detect direction changes.
public struct GamepadNavigationState {
  private var previousDpadX: Float = 0.0
  private var previousDpadY: Float = 0.0
  private var previousStickX: Float = 0.0
  private var previousStickY: Float = 0.0
  private var previousButtonA: Bool = false
  private var previousButtonB: Bool = false

  /// Update state from gamepad and return navigation changes.
  @MainActor
  public mutating func update(
    from gamepad: Gamepad,
    deadzone: Float = 0.3,
    trackButtons: Bool = true,
    invertY: Bool = true
  ) -> NavigationChanges {
    // Read current state
    let dpadUp = gamepad.state(of: .dpadUp) == .pressed
    let dpadDown = gamepad.state(of: .dpadDown) == .pressed
    let dpadLeft = gamepad.state(of: .dpadLeft) == .pressed
    let dpadRight = gamepad.state(of: .dpadRight) == .pressed

    let stickX = gamepad.state(of: .leftX)
    let stickY = invertY ? -gamepad.state(of: .leftY) : gamepad.state(of: .leftY)

    let currentDpadX: Float = dpadLeft ? -1.0 : (dpadRight ? 1.0 : 0.0)
    let currentDpadY: Float = dpadUp ? 1.0 : (dpadDown ? -1.0 : 0.0)

    let stickUp = stickY > deadzone
    let stickDown = stickY < -deadzone
    let stickLeft = stickX < -deadzone
    let stickRight = stickX > deadzone

    let buttonA = trackButtons ? (gamepad.state(of: .a) == .pressed) : false
    let buttonB = trackButtons ? (gamepad.state(of: .b) == .pressed) : false

    // Detect changes
    let wasNavigatingUp = previousDpadY > 0.5 || previousStickY > deadzone
    let wasNavigatingDown = previousDpadY < -0.5 || previousStickY < -deadzone
    let wasNavigatingLeft = previousDpadX < -0.5 || previousStickX < -deadzone
    let wasNavigatingRight = previousDpadX > 0.5 || previousStickX > deadzone

    let navigatedUp = (dpadUp || stickUp) && !wasNavigatingUp
    let navigatedDown = (dpadDown || stickDown) && !wasNavigatingDown
    let navigatedLeft = (dpadLeft || stickLeft) && !wasNavigatingLeft
    let navigatedRight = (dpadRight || stickRight) && !wasNavigatingRight

    let buttonAPressed = buttonA && !previousButtonA
    let buttonBPressed = buttonB && !previousButtonB

    // Update previous state
    previousDpadX = currentDpadX
    previousDpadY = currentDpadY
    previousStickX = stickX
    previousStickY = stickY
    previousButtonA = buttonA
    previousButtonB = buttonB

    return NavigationChanges(
      up: navigatedUp,
      down: navigatedDown,
      left: navigatedLeft,
      right: navigatedRight,
      buttonA: buttonAPressed,
      buttonB: buttonBPressed
    )
  }

  /// Reset internal state.
  public mutating func reset() {
    previousDpadX = 0.0
    previousDpadY = 0.0
    previousStickX = 0.0
    previousStickY = 0.0
    previousButtonA = false
    previousButtonB = false
  }

  /// Result of navigation state update.
  public struct NavigationChanges {
    public let up: Bool
    public let down: Bool
    public let left: Bool
    public let right: Bool
    public let buttonA: Bool
    public let buttonB: Bool

    public var hasAnyDirection: Bool {
      up || down || left || right
    }
  }
}
