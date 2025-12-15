/// A dialog view that displays text with a typewriter animation effect.
/// The text is wrapped to a maximum of 2 lines within a 400px wide box centered at the bottom of the screen.
/// Text is left-aligned within the box.
@MainActor final class DialogView {
  /// Width of the text box in points
  private static let textBoxWidth: Float = 600.0

  /// The full text to display
  var text: String = "" {
    didSet {
      displayedCharacterCount = 0
      if isChunkMode {
        // In chunk mode, reset page index when text changes (new string chunk)
        currentPageIndex = 0
      } else {
        // In single text mode, reset chunk index
        currentChunkIndex = 0
      }
      needsLayout = true
    }
  }

  /// Characters per second for the typewriter animation
  var charactersPerSecond: Float = 30.0

  /// Speed multiplier for typewriter animation (default: 1.0, set to 2.5 for fast-forward)
  var speedMultiplier: Float = 1.0

  /// Padding from the bottom of the screen
  var bottomPadding: Float = 128.0

  // Private state
  private var displayedCharacterCount: Float = 0
  private var needsLayout: Bool = true
  private var allLines: [String] = []  // All wrapped lines
  private var wrappedLines: [String] = []  // Current chunk (max 2 lines)
  private var fullTextBounds: Rect = .zero
  private var lineHeight: Float = 0.0  // Line height for positioning adjustments
  private var currentChunkIndex: Int = 0  // Which 2-line chunk we're showing
  private var hasOverflow: Bool = false
  private let moreIndicatorCaret = Caret(direction: .down, animationBehavior: .move)
  private var deltaTime: Float = 0.0
  private var wasCaretVisibleLastFrame: Bool = false

  // Chunk-based mode (when using print() with array of strings)
  private var chunks: [String] = []  // Array of strings, each treated as a chunk
  private var isChunkMode: Bool = false  // Whether we're in chunk mode vs single text mode
  private var currentStringChunkIndex: Int = 0  // Which string chunk we're on (in chunk mode)
  private var currentPageIndex: Int = 0  // Which 2-line page within the current chunk we're on

  // Async completion support
  private var completionContinuation: CheckedContinuation<Void, Never>?
  private var wasTextEmptyLastFrame: Bool = false

  // Force more indicator to show even if there are no more chunks
  private var forceMoreIndicator: Bool = false

  // Ask mode state (for inline option selection)
  private var askText: String?
  private var askOptions: [String] = []
  private var selectedOptionIndex: Int = 0
  private var previousSelectedOptionIndex: Int = -1  // Track previous selection to reset animation
  private var askContinuation: CheckedContinuation<Int, Never>?
  private var wasLeftKeyPressedLastFrame: Bool = false
  private var wasRightKeyPressedLastFrame: Bool = false
  private var wasActionKeyPressedLastFrame: Bool = false
  private var skipInputThisFrame: Bool = false  // Skip input on first frame to avoid immediate selection
  private var waitingForActionKeyRelease: Bool = false  // Wait for action key to be released before allowing selection
  private var hasSeenActionKeyRelease: Bool = false  // Track if we've seen the key released after entering ask mode
  private let optionCaret = Caret(direction: .right, animationBehavior: .fade)

  init() {}

  func update(deltaTime: Float) {
    self.deltaTime = deltaTime

    // // Check if text just became empty (user dismissed dialog) and resume continuation if needed
    // let isTextEmptyNow = text.isEmpty
    // if isTextEmptyNow && !wasTextEmptyLastFrame {
    //   // Text just became empty (user dismissed), resume continuation if one exists
    //   if let continuation = completionContinuation {
    //     completionContinuation = nil
    //     continuation.resume()
    //   }
    //   // Reset forceMoreIndicator when dialog is dismissed
    //   forceMoreIndicator = false
    // }
    // wasTextEmptyLastFrame = isTextEmptyNow

    // Update speed multiplier based on held action keys or left mouse button
    updateSpeedMultiplier()

    // Handle ask mode - update typewriter effect and handle input (keyboard and gamepad)
    if let askText = askText {
      // Ensure layout is done for ask mode
      if needsLayout {
        layoutText(askText)
        needsLayout = false
      }

      // Update typewriter effect for question text (same approach as print())
      // Calculate total characters in wrapped lines (max 2 lines)
      let totalCharacters = wrappedLines.reduce(0) { $0 + $1.count }
      let effectiveSpeed = charactersPerSecond * speedMultiplier
      displayedCharacterCount = min(
        displayedCharacterCount + effectiveSpeed * deltaTime,
        Float(totalCharacters)
      )

      // Update animation tracking for ask mode
      if selectedOptionIndex != previousSelectedOptionIndex {
        optionCaret.resetAnimation()
        previousSelectedOptionIndex = selectedOptionIndex
      }

      // Check for key release on first frame (check initial state)
      if skipInputThisFrame {
        skipInputThisFrame = false
        guard let window = Engine.shared.window else { return }
        let keyboard = window.keyboard
        let isActionKeyPressed =
          keyboard.state(of: .f) == .pressed || keyboard.state(of: .space) == .pressed
          || keyboard.state(of: .enter) == .pressed || keyboard.state(of: .numpadEnter) == .pressed
        // Also check gamepad A button
        let isGamepadActionPressed = Gamepad.allGamepads.first?.state(of: .a) == .pressed
        waitingForActionKeyRelease = isActionKeyPressed || isGamepadActionPressed
        hasSeenActionKeyRelease = !(isActionKeyPressed || isGamepadActionPressed)
      }

      // Handle gamepad input for ask mode navigation
      handleAskModeGamepadInput()

      // Handle keyboard input for ask mode
      handleAskModeInput()

      return
    }

    let fullText = text
    guard !fullText.isEmpty else { return }

    // Layout text if needed
    if needsLayout {
      layoutText(fullText)
      needsLayout = false
    }

    // Calculate total characters in wrapped lines (max 2 lines)
    let totalCharacters = wrappedLines.reduce(0) { $0 + $1.count }

    // Update displayed character count with speed multiplier
    let effectiveSpeed = charactersPerSecond * speedMultiplier
    displayedCharacterCount = min(
      displayedCharacterCount + effectiveSpeed * deltaTime,
      Float(totalCharacters)
    )
  }

  private func updateSpeedMultiplier() {
    // Check for held action keys or left mouse button
    guard let window = Engine.shared.window else {
      speedMultiplier = 1.0
      return
    }

    let keyboard = window.keyboard
    let mouse = window.mouse

    let isActionKeyHeld =
      keyboard.state(of: .f) == .pressed || keyboard.state(of: .space) == .pressed
      || keyboard.state(of: .enter) == .pressed || keyboard.state(of: .numpadEnter) == .pressed

    let isLeftMouseHeld = mouse.state(of: .left) == .pressed

    // Check for gamepad A button (action button)
    let isGamepadActionHeld = Gamepad.allGamepads.first?.state(of: .a) == .pressed

    // Set speed multiplier to 4.0x if any action input is held
    speedMultiplier = (isActionKeyHeld || isLeftMouseHeld || isGamepadActionHeld) ? 4.0 : 1.0
  }

  private func handleAskModeInput() {
    guard let window = Engine.shared.window else { return }
    let keyboard = window.keyboard

    // Skip input on first frame to avoid immediate selection from the key that triggered the action
    if skipInputThisFrame {
      skipInputThisFrame = false
      // Check if action key is pressed - if so, wait for it to be released
      let isActionKeyPressed =
        keyboard.state(of: .f) == .pressed || keyboard.state(of: .space) == .pressed
        || keyboard.state(of: .enter) == .pressed || keyboard.state(of: .numpadEnter) == .pressed
      waitingForActionKeyRelease = isActionKeyPressed
      hasSeenActionKeyRelease = !isActionKeyPressed  // If not pressed, we've already seen release

      // Still update the "was pressed" flags so we don't trigger on the next frame
      let isLeftPressed = keyboard.state(of: .a) == .pressed || keyboard.state(of: .left) == .pressed
      let isRightPressed = keyboard.state(of: .d) == .pressed || keyboard.state(of: .right) == .pressed
      wasLeftKeyPressedLastFrame = isLeftPressed
      wasRightKeyPressedLastFrame = isRightPressed
      wasActionKeyPressedLastFrame = isActionKeyPressed
      return
    }

    // Wait for action key to be released if it was pressed when entering ask mode
    if waitingForActionKeyRelease {
      let isActionKeyPressed =
        keyboard.state(of: .f) == .pressed || keyboard.state(of: .space) == .pressed
        || keyboard.state(of: .enter) == .pressed || keyboard.state(of: .numpadEnter) == .pressed
      // Also check gamepad A button
      let isGamepadActionPressed = Gamepad.allGamepads.first?.state(of: .a) == .pressed

      if !isActionKeyPressed && !isGamepadActionPressed {
        // Action key has been released, mark that we've seen the release
        hasSeenActionKeyRelease = true
        waitingForActionKeyRelease = false
        wasActionKeyPressedLastFrame = false
      } else {
        // Still pressed (key repeat), keep waiting and skip input
        wasActionKeyPressedLastFrame = isActionKeyPressed || isGamepadActionPressed
        return
      }
    }

    // If we haven't seen the action key released yet (even if not waiting), don't allow selection
    // This handles the case where key repeat keeps the key "pressed" continuously
    if !hasSeenActionKeyRelease {
      let isActionKeyPressed =
        keyboard.state(of: .f) == .pressed || keyboard.state(of: .space) == .pressed
        || keyboard.state(of: .enter) == .pressed || keyboard.state(of: .numpadEnter) == .pressed
      // Also check gamepad A button
      let isGamepadActionPressed = Gamepad.allGamepads.first?.state(of: .a) == .pressed
      if !isActionKeyPressed && !isGamepadActionPressed {
        hasSeenActionKeyRelease = true
      } else {
        // Still pressed, update flag but don't allow selection yet
        wasActionKeyPressedLastFrame = isActionKeyPressed || isGamepadActionPressed
        // Continue to navigation handling but skip selection
      }
    }

    // Keyboard navigation is handled by handleAskModeNavigation() via MainLoop.onKeyPressed()
    // We only need to track state here for other logic
    let isLeftPressed = keyboard.state(of: .a) == .pressed || keyboard.state(of: .left) == .pressed
    let isRightPressed = keyboard.state(of: .d) == .pressed || keyboard.state(of: .right) == .pressed
    wasLeftKeyPressedLastFrame = isLeftPressed
    wasRightKeyPressedLastFrame = isRightPressed

    // Reset animation if selection changed (for any reason)
    if selectedOptionIndex != previousSelectedOptionIndex {
      optionCaret.resetAnimation()
      previousSelectedOptionIndex = selectedOptionIndex
    }

    // Handle selection (action keys)
    // Only allow selection if we've seen the key released at least once
    guard hasSeenActionKeyRelease else {
      // Update flag but don't allow selection
      let isActionKeyPressed =
        keyboard.state(of: .f) == .pressed || keyboard.state(of: .space) == .pressed
        || keyboard.state(of: .enter) == .pressed || keyboard.state(of: .numpadEnter) == .pressed
      wasActionKeyPressedLastFrame = isActionKeyPressed
      return
    }

    // Wait until question text has finished typewriting before allowing selection
    guard askText != nil else { return }
    // Calculate total characters in wrapped lines (same as in update())
    let totalCharacters = wrappedLines.reduce(0) { $0 + $1.count }
    let isQuestionComplete = displayedCharacterCount >= Float(totalCharacters)
    guard isQuestionComplete else {
      // Update flag but don't allow selection while typewriting
      let isActionKeyPressed =
        keyboard.state(of: .f) == .pressed || keyboard.state(of: .space) == .pressed
        || keyboard.state(of: .enter) == .pressed || keyboard.state(of: .numpadEnter) == .pressed
      wasActionKeyPressedLastFrame = isActionKeyPressed
      return
    }

    let isActionKeyPressed =
      keyboard.state(of: .f) == .pressed || keyboard.state(of: .space) == .pressed
      || keyboard.state(of: .enter) == .pressed || keyboard.state(of: .numpadEnter) == .pressed
    // Also check gamepad A button
    let isGamepadActionPressed = (Gamepad.allGamepads.first?.state(of: .a) == .pressed) ?? false
    let isAnyActionPressed = isActionKeyPressed || isGamepadActionPressed

    // Only trigger selection on key press (not while held)
    let actionKeyJustPressed = isAnyActionPressed && !wasActionKeyPressedLastFrame

    if actionKeyJustPressed {
      // User selected an option
      let selectedIndex = selectedOptionIndex

      // Clear ask mode state
      askText = nil
      askOptions = []
      text = ""

      // Resume continuation with selected index
      if let continuation = askContinuation {
        askContinuation = nil
        continuation.resume(returning: selectedIndex)
      }
    }

    wasActionKeyPressedLastFrame = isAnyActionPressed
  }

  func draw() {
    guard !text.isEmpty else { return }

    let viewportWidth = Float(Engine.viewportSize.width)
    let viewportHeight = Float(Engine.viewportSize.height)

    // Use text box width constant
    let effectiveMaxWidth = Self.textBoxWidth

    // Use left-aligned dialog style
    let dialogStyle = TextStyle.dialog.withAlignment(.left)

    // Handle ask mode rendering
    if let askText = askText, !askOptions.isEmpty {
      drawAskMode(
        questionText: askText,
        options: askOptions,
        selectedIndex: selectedOptionIndex,
        viewportWidth: viewportWidth,
        viewportHeight: viewportHeight,
        effectiveMaxWidth: effectiveMaxWidth,
        dialogStyle: dialogStyle
      )
      return
    }

    // Normal dialog rendering
    let displayCount = Int(displayedCharacterCount.rounded(.towardZero))
    guard displayCount > 0 else { return }

    // Get visible text for drawing
    let fullTextToShow = getVisibleText(characterCount: displayCount)

    // Calculate bounds of both the visible text and full chunk
    // This lets us compensate for height differences
    let visibleTextBounds = fullTextToShow.boundingRect(
      with: dialogStyle,
      wrapWidth: effectiveMaxWidth
    )
    let textBounds = fullTextBounds

    // Calculate the height difference - this is what causes the jump
    let heightDifference = textBounds.size.height - visibleTextBounds.size.height

    // Center the 400px text box on screen, text is left-aligned within it
    let textX = (viewportWidth - effectiveMaxWidth) / 2
    let baseTextY: Float
    if let context = GraphicsContext.current, !context.isFlipped {
      // In flipped coordinates, Y=0 is at bottom, so calculate from bottom
      // Use fullTextBounds to ensure position stays stable
      baseTextY = bottomPadding + textBounds.size.height
    } else {
      // In normal coordinates, Y=0 is at top, so calculate from top
      // Use fullTextBounds to ensure position stays stable
      baseTextY = viewportHeight - bottomPadding - textBounds.size.height
    }

    // Adjust Y position to compensate for height difference
    // When partial text is smaller, we need to move it up by the height difference
    // to keep the bottom aligned (since smaller text would naturally sit higher)
    var textY = baseTextY + heightDifference

    // If the full chunk is only one line, shift it up by one line height
    // so it appears at the same position as the first line of a two-line chunk
    if wrappedLines.count == 1 {
      textY += lineHeight * 2  // Shift up by two line heights because of a possible bug in text rendering? 😵‍💫
    }

    // Draw the text - compensate for height difference to prevent jumping
    fullTextToShow.draw(
      at: Point(textX, textY),
      style: dialogStyle,
      wrapWidth: effectiveMaxWidth,
      anchor: .bottomLeft
    )

    // Draw caret indicator if there's more chunks to show AND current chunk is complete,
    // or if forceMoreIndicator is set
    let shouldShowCaret = (hasMoreChunks || forceMoreIndicator) && isCurrentChunkComplete()
    if shouldShowCaret {
      // Reset animation if caret just became visible
      if !wasCaretVisibleLastFrame {
        moreIndicatorCaret.resetAnimation()
      }
      drawMoreIndicator(textX: textX, textY: textY, textHeight: textBounds.size.height)
    }
    wasCaretVisibleLastFrame = shouldShowCaret
  }

  private func drawAskMode(
    questionText: String,
    options: [String],
    selectedIndex: Int,
    viewportWidth: Float,
    viewportHeight: Float,
    effectiveMaxWidth: Float,
    dialogStyle: TextStyle
  ) {
    // Layout question text to get line height
    let questionBounds = questionText.boundingRect(
      with: dialogStyle,
      wrapWidth: effectiveMaxWidth
    )

    // Calculate line height from question text
    let features = Font.Features(monospaceDigits: dialogStyle.monospaceDigits)
    guard
      let font = Font(
        fontName: dialogStyle.fontName,
        pixelHeight: dialogStyle.fontSize,
        features: features
      )
    else {
      return
    }
    let layout = TextLayout(font: font, scale: 1.0)
    let layoutResult = layout.layout(questionText, style: dialogStyle, wrapWidth: effectiveMaxWidth)
    let calculatedLineHeight = layoutResult.lineHeight

    // Center the text box on screen
    let textX = (viewportWidth - effectiveMaxWidth) / 2
    let baseTextY: Float
    if let context = GraphicsContext.current, !context.isFlipped {
      // In flipped coordinates, Y=0 is at bottom
      baseTextY = bottomPadding + questionBounds.size.height + calculatedLineHeight
    } else {
      // In normal coordinates, Y=0 is at top
      baseTextY = viewportHeight - bottomPadding - questionBounds.size.height - calculatedLineHeight
    }

    // Draw question text on first line with typewriter effect (same approach as print())
    let displayCount = Int(displayedCharacterCount.rounded(.towardZero))
    let visibleQuestionText = getVisibleText(characterCount: displayCount)
    visibleQuestionText.draw(
      at: Point(textX, baseTextY + calculatedLineHeight),
      style: dialogStyle,
      wrapWidth: effectiveMaxWidth,
      anchor: .bottomLeft
    )

    // Only show options when question is fully typed out
    let totalCharacters = wrappedLines.reduce(0) { $0 + $1.count }
    let isQuestionComplete = displayedCharacterCount >= Float(totalCharacters)
    guard isQuestionComplete else { return }

    // Build options text with padding before each option for caret space
    let caretWidth: Float = 16  // Approximate width of caret at scale 0.5
    let caretSpacing: Float = 8  // Space between caret and option text
    let totalPadding = caretWidth + caretSpacing

    // Add padding before each option (using spaces as a simple approach)
    // We'll measure the actual width needed
    let paddingText = "   "  // Use a few spaces as padding
    let separatorText = "   "  // Separator between options
    let optionsWithPadding = options.map { paddingText + $0 }
    let optionsText = optionsWithPadding.joined(separator: separatorText)

    // Calculate caret position - measure text before selected option (with padding)
    let optionsBeforeSelected = optionsWithPadding[..<selectedIndex]
    let textBeforeSelected = optionsBeforeSelected.joined(separator: separatorText)

    // Measure text before selected option to position caret
    let textBeforeBounds =
      textBeforeSelected.isEmpty
      ? Rect.zero
      : textBeforeSelected.boundingRect(
        with: dialogStyle,
        wrapWidth: effectiveMaxWidth
      )

    // Measure separator width (needed for positioning after previous options)
    let separatorBounds = separatorText.boundingRect(
      with: dialogStyle,
      wrapWidth: effectiveMaxWidth
    )

    // Draw options on second line (with half line spacing from question)
    let optionsY = baseTextY - calculatedLineHeight / 2
    optionsText.draw(
      at: Point(textX, optionsY),
      style: dialogStyle,
      wrapWidth: effectiveMaxWidth,
      anchor: .bottomLeft
    )

    // Draw animated caret in front of selected option
    // Position it at the start of the padding for the selected option
    let caretX: Float
    if selectedIndex == 0 {
      // First option: position at start of padding
      caretX = textX - totalPadding + caretSpacing
    } else {
      // Other options: after previous options + separator, then start of padding
      caretX = textX + textBeforeBounds.size.width + separatorBounds.size.width - totalPadding + caretSpacing
    }

    // Position caret aligned with text baseline
    // The text is drawn with anchor .bottomLeft, so optionsY is the baseline
    // We want the caret centered vertically on the text line
    let caretY = optionsY

    optionCaret.draw(
      at: Point(caretX, caretY),
      tint: dialogStyle.color,
      scale: 0.5,
      deltaTime: deltaTime,
      strokeWidth: dialogStyle.strokeWidth,  // / 2,
      strokeColor: dialogStyle.strokeColor
    )
  }

  // MARK: - Public Methods

  /// Try to advance to the next chunk if the current chunk is complete.
  /// Returns true if advanced to a chunk, false if chunk is incomplete or already on the last chunk.
  /// If the dialog is finished, dismisses it instead.
  @discardableResult
  func tryAdvance() -> Bool {
    // If in ask mode, handle selection instead
    if askText != nil {
      return handleAskModeSelection()
    }

    // Only advance if current chunk is fully displayed
    guard isCurrentChunkComplete() else {
      return false
    }
    // If finished, dismiss the dialog
    if isFinished {
      dismiss()
      return true
    }
    // Try to advance to next chunk
    return advanceToNextChunk()
  }

  /// Handle key release events (used to track when action keys are released)
  func handleKeyRelease(key: Keyboard.Key) {
    // Check if this is an action key being released
    let isActionKey =
      key == .f || key == .space || key == .enter || key == .numpadEnter
    if isActionKey && askText != nil {
      hasSeenActionKeyRelease = true
      waitingForActionKeyRelease = false
      // Debug: Swift.print to verify this is being called
    }
  }

  // MARK: - Gamepad Support
  private var previousGamepadDpadState: (left: Bool, right: Bool) = (false, false)
  private var previousGamepadActionState: Bool = false

  /// Handle continuous gamepad input for ask mode navigation (called from update loop)
  private func handleAskModeGamepadInput() {
    guard let gamepad = Gamepad.allGamepads.first else { return }
    guard askText != nil else { return }

    // Wait for action key to be released if it was pressed when entering ask mode
    if waitingForActionKeyRelease {
      let isActionKeyPressed = gamepad.state(of: .a) == .pressed
      if !isActionKeyPressed {
        // Action key has been released, mark that we've seen the release
        hasSeenActionKeyRelease = true
        waitingForActionKeyRelease = false
        previousGamepadActionState = false
      } else {
        // Still pressed, keep waiting and skip input
        previousGamepadActionState = isActionKeyPressed
        return
      }
    }

    // If we haven't seen the action key released yet, don't allow selection
    if !hasSeenActionKeyRelease {
      let isActionKeyPressed = gamepad.state(of: .a) == .pressed
      if !isActionKeyPressed {
        hasSeenActionKeyRelease = true
      } else {
        previousGamepadActionState = isActionKeyPressed
        // Continue to navigation handling but skip selection
      }
    }

    // Handle D-pad left/right navigation
    let dpadLeft = gamepad.state(of: .dpadLeft) == .pressed
    let dpadRight = gamepad.state(of: .dpadRight) == .pressed

    // Only change selection on button press (not while held)
    if dpadLeft && !previousGamepadDpadState.left {
      let newIndex = max(0, selectedOptionIndex - 1)
      if newIndex != selectedOptionIndex {
        selectedOptionIndex = newIndex
        optionCaret.resetAnimation()
        UISound.navigate()
      }
    }
    if dpadRight && !previousGamepadDpadState.right {
      let newIndex = min(askOptions.count - 1, selectedOptionIndex + 1)
      if newIndex != selectedOptionIndex {
        selectedOptionIndex = newIndex
        optionCaret.resetAnimation()
        UISound.navigate()
      }
    }

    // Update previous D-pad state
    previousGamepadDpadState = (left: dpadLeft, right: dpadRight)

    // Handle selection (A button)
    // Only allow selection if we've seen the key released at least once
    guard hasSeenActionKeyRelease else {
      let isActionKeyPressed = gamepad.state(of: .a) == .pressed
      previousGamepadActionState = isActionKeyPressed
      return
    }

    // Wait until question text has finished typewriting before allowing selection
    guard askText != nil else { return }
    // Calculate total characters in wrapped lines (same as in update())
    let totalCharacters = wrappedLines.reduce(0) { $0 + $1.count }
    let isQuestionComplete = displayedCharacterCount >= Float(totalCharacters)
    guard isQuestionComplete else {
      // Update flag but don't allow selection while typewriting
      let isActionKeyPressed = gamepad.state(of: .a) == .pressed
      previousGamepadActionState = isActionKeyPressed
      return
    }

    let isActionKeyPressed = gamepad.state(of: .a) == .pressed

    // Only trigger selection on button press (not while held)
    let actionKeyJustPressed = isActionKeyPressed && !previousGamepadActionState

    if actionKeyJustPressed {
      // User selected an option
      let selectedIndex = selectedOptionIndex

      // Clear ask mode state
      askText = nil
      askOptions = []
      text = ""

      // Resume continuation with selected index
      if let continuation = askContinuation {
        askContinuation = nil
        continuation.resume(returning: selectedIndex)
      }
    }

    previousGamepadActionState = isActionKeyPressed
  }

  /// Handle gamepad button press for dialog advancement and navigation
  func handleGamepadButton(_ button: Gamepad.Button, gamepad: Gamepad) {
    InputSource.updateFromGamepad(gamepad)

    switch button {
    case .a:
      // A button = Advance/Dismiss (F/Space/Enter equivalent)
      // Only advance if not in ask mode (ask mode is handled in update loop)
      if askText == nil {
        if tryAdvance() {
          // Advanced successfully
        } else if isFinished {
          // Dialog finished, dismiss it
          dismiss()
        }
      }
    default:
      break
    }
  }

  /// Handle navigation in ask mode (left/right)
  /// Returns true if navigation occurred
  @discardableResult
  func handleAskModeNavigation(key: Keyboard.Key) -> Bool {
    guard askText != nil else { return false }

    // Skip input on first frame only (navigation should work independently of action key state)
    if skipInputThisFrame {
      return false
    }

    // Wait until question text has finished typewriting before allowing navigation
    let totalCharacters = wrappedLines.reduce(0) { $0 + $1.count }
    let isQuestionComplete = displayedCharacterCount >= Float(totalCharacters)
    guard isQuestionComplete else {
      return false
    }

    switch key {
    case .a, .left:
      let newIndex = max(0, selectedOptionIndex - 1)
      if newIndex != selectedOptionIndex {
        selectedOptionIndex = newIndex
        optionCaret.resetAnimation()
        UISound.navigate()
        // Mark that we handled this key press to prevent handleAskModeInput from processing it
        wasLeftKeyPressedLastFrame = true
        return true
      }
    case .d, .right:
      let newIndex = min(askOptions.count - 1, selectedOptionIndex + 1)
      if newIndex != selectedOptionIndex {
        selectedOptionIndex = newIndex
        optionCaret.resetAnimation()
        UISound.navigate()
        // Mark that we handled this key press to prevent handleAskModeInput from processing it
        wasRightKeyPressedLastFrame = true
        return true
      }
    default:
      break
    }
    return false
  }

  /// Handle selection in ask mode
  /// Returns true if selection occurred
  private func handleAskModeSelection() -> Bool {
    guard askText != nil else { return false }

    // Wait until question text has finished typewriting before allowing selection
    let totalCharacters = wrappedLines.reduce(0) { $0 + $1.count }
    let isQuestionComplete = displayedCharacterCount >= Float(totalCharacters)
    guard isQuestionComplete else {
      return false
    }

    // Ignore repeat events for ask mode selection (only allow actual key presses)
    // This check must be first, before any other logic
    guard !Engine.isKeyRepeat else {
      return false
    }

    // Only allow selection if we've seen the key released at least once
    // (to prevent immediate selection if key was held when entering ask mode)
    guard hasSeenActionKeyRelease else {
      return false
    }

    // User selected an option (this is called from onKeyPressed, so it's an actual press)
    let selectedIndex = selectedOptionIndex

    // Clear ask mode state
    askText = nil
    askOptions = []
    text = ""

    // Resume continuation with selected index
    if let continuation = askContinuation {
      askContinuation = nil
      continuation.resume(returning: selectedIndex)
    }

    return true
  }

  /// Advance to the next chunk of text if available.
  /// Returns true if advanced to a new chunk, false if already on the last chunk.
  @discardableResult
  private func advanceToNextChunk() -> Bool {
    if isChunkMode {
      // In chunk mode, first check if current chunk has more pages
      let totalPages = (allLines.count + 1) / 2  // Round up division
      if currentPageIndex < totalPages - 1 {
        // Advance to next page within current chunk
        currentPageIndex += 1
        updateCurrentChunk()
        updateBounds()
        displayedCharacterCount = 0  // Reset typewriter animation
        return true
      } else {
        // No more pages in current chunk, advance to next string chunk
        guard currentStringChunkIndex < chunks.count - 1 else {
          return false  // Already on last string chunk
        }
        currentStringChunkIndex += 1
        self.text = chunks[currentStringChunkIndex]
        // currentPageIndex will be reset in didSet
        return true
      }
    } else {
      // In single text mode, advance to next 2-line chunk
      let totalChunks = (allLines.count + 1) / 2  // Round up division
      guard currentChunkIndex < totalChunks - 1 else {
        return false  // Already on last chunk
      }

      currentChunkIndex += 1
      updateCurrentChunk()
      updateBounds()
      displayedCharacterCount = 0  // Reset typewriter animation
      return true
    }
  }

  /// Check if all text in the current chunk has been displayed
  func isCurrentChunkComplete() -> Bool {
    let totalCharacters = wrappedLines.reduce(0) { $0 + $1.count }
    return displayedCharacterCount >= Float(totalCharacters)
  }

  /// Check if all chunks have been displayed and are complete
  var isFinished: Bool {
    guard isCurrentChunkComplete() else { return false }
    return !hasMoreChunks
  }

  /// Whether the dialog is currently active (showing text)
  var isActive: Bool {
    return !text.isEmpty
  }

  /// Dismiss the dialog (synchronously disables input to prevent frame gap)
  func dismiss() {
    text = ""
    forceMoreIndicator = false

    if let continuation = completionContinuation {
      completionContinuation = nil
      continuation.resume()
    }
  }

  /// Display an array of text chunks. Each string will be treated as a separate chunk
  /// and will show a "more" indicator when complete (even if it doesn't wrap).
  /// - Parameter chunks: Array of strings, each treated as a chunk
  /// - Parameter forceMore: If true, forces the more indicator to show even if there are no more chunks
  func print(chunks: [LocalizedStringResource], forceMore: Bool = false) {
    guard !chunks.isEmpty else {
      self.text = ""
      forceMoreIndicator = false
      return
    }

    isChunkMode = true
    self.chunks = chunks.map { String(gameLocalized: $0) }
    currentStringChunkIndex = 0
    currentPageIndex = 0
    self.forceMoreIndicator = forceMore

    // Set text to first chunk
    self.text = self.chunks[0]
  }

  /// Async version of print() that waits until the dialog is finished
  /// - Parameter chunks: Array of strings, each treated as a chunk
  /// - Parameter forceMore: If true, forces the more indicator to show even if there are no more chunks
  func print(chunks: [LocalizedStringResource], forceMore: Bool = false) async {
    // Cancel any existing continuation
    if let continuation = completionContinuation {
      completionContinuation = nil
      continuation.resume()
    }

    // Set up the dialog (call the synchronous version)
    guard !chunks.isEmpty else {
      self.text = ""
      forceMoreIndicator = false
      return
    }

    isChunkMode = true
    self.chunks = chunks.map { String(gameLocalized: $0) }
    currentStringChunkIndex = 0
    currentPageIndex = 0
    self.forceMoreIndicator = forceMore

    // Set text to first chunk
    wasTextEmptyLastFrame = text.isEmpty
    self.text = self.chunks[0]

    // Wait for completion (until text becomes empty - user dismisses dialog)
    await withCheckedContinuation { continuation in
      completionContinuation = continuation
      // Check if already empty (shouldn't happen for non-empty chunks, but handle it)
      if text.isEmpty {
        completionContinuation = nil
        continuation.resume()
      }
    }
  }

  /// Display a single text string (legacy mode)
  /// - Parameter text: The text to display
  /// - Parameter forceMore: If true, forces the more indicator to show even if there are no more chunks
  func show(_ text: String, forceMore: Bool = false) {
    isChunkMode = false
    chunks = []
    self.forceMoreIndicator = forceMore
    self.text = text
  }

  /// Async version of show() that waits until the dialog is finished
  /// - Parameter text: The text to display
  /// - Parameter forceMore: If true, forces the more indicator to show even if there are no more chunks
  func show(_ text: String, forceMore: Bool = false) async {
    // Cancel any existing continuation
    if let continuation = completionContinuation {
      completionContinuation = nil
      continuation.resume()
    }

    // Set up the dialog (call the synchronous version)
    isChunkMode = false
    chunks = []
    self.forceMoreIndicator = forceMore
    wasTextEmptyLastFrame = self.text.isEmpty
    self.text = text

    // Wait for completion (until text becomes empty - user dismisses dialog)
    await withCheckedContinuation { continuation in
      completionContinuation = continuation
      // Check if already empty (shouldn't happen for non-empty text, but handle it)
      if text.isEmpty {
        completionContinuation = nil
        continuation.resume()
      }
    }
  }

  /// Ask a question with inline options. Returns the index of the selected option.
  /// - Parameter text: The question text to display
  /// - Parameter options: Array of option strings to choose from
  /// - Returns: The index of the selected option (0-based)
  func ask(_ text: LocalizedStringResource, options: [LocalizedStringResource]) async -> Int {
    // Cancel any existing ask continuation
    if let continuation = askContinuation {
      askContinuation = nil
      continuation.resume(returning: 0)
    }

    // Set up ask mode
    let questionText = String(gameLocalized: text)
    let optionStrings = options.map { String(gameLocalized: $0) }

    askText = questionText
    askOptions = optionStrings
    selectedOptionIndex = 0
    previousSelectedOptionIndex = -1  // Reset to trigger animation reset on first frame
    wasLeftKeyPressedLastFrame = false
    wasRightKeyPressedLastFrame = false

    // Check if action key is currently pressed - if so, set wasActionKeyPressedLastFrame = true
    // to prevent the same key press that triggered ask() from immediately selecting an option
    // This prevents double-submit when F is pressed to start interaction and ask() is called
    if let window = Engine.shared.window {
      let keyboard = window.keyboard
      let isActionKeyCurrentlyPressed =
        keyboard.state(of: .f) == .pressed || keyboard.state(of: .space) == .pressed
        || keyboard.state(of: .enter) == .pressed || keyboard.state(of: .numpadEnter) == .pressed
      let isGamepadActionCurrentlyPressed = Gamepad.allGamepads.first.map { $0.state(of: .a) == .pressed } ?? false
      wasActionKeyPressedLastFrame = isActionKeyCurrentlyPressed || isGamepadActionCurrentlyPressed
    } else {
      wasActionKeyPressedLastFrame = false
    }

    skipInputThisFrame = true  // Skip input on first frame to avoid immediate selection
    waitingForActionKeyRelease = false  // Will be set on first frame if action key is pressed
    hasSeenActionKeyRelease = false  // Will be set when we detect key release
    optionCaret.resetAnimation()  // Reset animation when ask mode first appears

    // Set text to question (will be displayed on first line with typewriter effect)
    self.text = questionText
    needsLayout = true
    // Start typewriter effect from beginning
    displayedCharacterCount = 0

    // Wait for user to select an option
    return await withCheckedContinuation { continuation in
      askContinuation = continuation
    }
  }

  /// Confirm a question with two options. Returns true if the first option is selected.
  /// - Parameter text: The question text to display
  /// - Parameter trueOption: The option that returns true (first option)
  /// - Parameter falseOption: The option that returns false (second option)
  /// - Returns: true if trueOption is selected, false if falseOption is selected
  func confirm(
    _ text: LocalizedStringResource,
    _ trueOption: LocalizedStringResource,
    _ falseOption: LocalizedStringResource = "Cancel"
  ) async -> Bool {
    let index = await ask(text, options: [trueOption, falseOption])
    return index == 0
  }

  // MARK: - Private Methods

  private var hasMoreChunks: Bool {
    if isChunkMode {
      // In chunk mode, check if there are more pages in current chunk OR more string chunks
      let totalPages = (allLines.count + 1) / 2  // Round up division
      let hasMorePages = currentPageIndex < totalPages - 1
      let hasMoreStringChunks = currentStringChunkIndex < chunks.count - 1
      return hasMorePages || hasMoreStringChunks
    } else {
      // In single text mode, check if there are more 2-line chunks
      let totalChunks = (allLines.count + 1) / 2  // Round up division
      return currentChunkIndex < totalChunks - 1
    }
  }

  private func layoutText(_ text: String) {
    // Use text box width constant
    let effectiveMaxWidth = Self.textBoxWidth

    // Use left-aligned dialog style
    let dialogStyle = TextStyle.dialog.withAlignment(.left)

    // Layout the text to get wrapped lines
    let features = Font.Features(monospaceDigits: dialogStyle.monospaceDigits)
    guard
      let font = Font(
        fontName: dialogStyle.fontName,
        pixelHeight: dialogStyle.fontSize,
        features: features
      )
    else {
      wrappedLines = []
      fullTextBounds = .zero
      hasOverflow = false
      return
    }

    let layout = TextLayout(font: font, scale: 1.0)
    let layoutResult = layout.layout(text, style: dialogStyle, wrapWidth: effectiveMaxWidth)

    // Store line height for positioning adjustments
    lineHeight = layoutResult.lineHeight

    // Store all lines
    allLines = layoutResult.lines.map { $0.text }

    // Check for overflow (more than 2 lines)
    hasOverflow = allLines.count > 2

    // Update current chunk
    currentChunkIndex = 0
    updateCurrentChunk()
    updateBounds()
  }

  private func updateCurrentChunk() {
    // Get the current chunk (2 lines starting at the appropriate index)
    let pageIndex = isChunkMode ? currentPageIndex : currentChunkIndex
    let startIndex = pageIndex * 2
    let endIndex = min(startIndex + 2, allLines.count)
    wrappedLines = Array(allLines[startIndex..<endIndex])
  }

  private func updateBounds() {
    // Calculate bounds for the current chunk (for stable positioning)
    let effectiveMaxWidth = Self.textBoxWidth
    let dialogStyle = TextStyle.dialog.withAlignment(.left)
    let fullWrappedText = wrappedLines.joined(separator: "\n")
    fullTextBounds = fullWrappedText.boundingRect(
      with: dialogStyle,
      wrapWidth: effectiveMaxWidth
    )
  }

  private func getVisibleText(characterCount: Int) -> String {
    guard !wrappedLines.isEmpty else { return "" }

    // Build text progressively across lines
    var remainingChars = characterCount
    var result: [String] = []

    for line in wrappedLines {
      if remainingChars <= 0 {
        break
      }

      if remainingChars >= line.count {
        // Show entire line
        result.append(line)
        remainingChars -= line.count
      } else {
        // Show partial line
        let endIndex = line.index(line.startIndex, offsetBy: remainingChars)
        result.append(String(line[..<endIndex]))
        break
      }
    }

    return result.joined(separator: "\n")
  }

  private func drawMoreIndicator(textX: Float, textY: Float, textHeight: Float) {
    guard let context = GraphicsContext.current else { return }

    // Position caret centered below the text block
    var caretSpacing: Float = 0  // Space between text and caret
    if wrappedLines.count == 1 { caretSpacing += lineHeight * 1 }

    let caretX = textX - 5  // Center horizontally within the text box
    let caretY: Float
    if !context.isFlipped {
      // In flipped coordinates, Y=0 is at bottom
      caretY = textY - textHeight - caretSpacing
    } else {
      // In normal coordinates, Y=0 is at top
      caretY = textY + textHeight + caretSpacing
    }

    // Draw caret with fade animation and stroke from dialog style
    moreIndicatorCaret.visible = true
    moreIndicatorCaret.draw(
      at: Point(caretX, caretY),
      tint: TextStyle.dialog.color,
      // tint: .gray400,
      // scale: 0.75,
      deltaTime: deltaTime,
      strokeWidth: TextStyle.dialog.strokeWidth,  // / 2,
      strokeColor: TextStyle.dialog.strokeColor
    )
  }
}
