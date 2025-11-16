import STBTextEdit

import struct Foundation.Date

@MainActor
public final class TextField: OptionsControl {
  // MARK: - Public API

  public var frame: Rect
  public var isFocused: Bool = false {
    didSet {
      if isFocused {
        TextField.focusedField = self
      } else if TextField.focusedField === self {
        TextField.focusedField = nil
      }
    }
  }

  /// The field's text content (backed by `TextEditor`).
  public var text: String {
    get { editor.text }
    set { editor.text = newValue }
  }

  /// Legacy: Called when Return/Enter is pressed while focused.
  public var onCommit: (() -> Void)?
  /// Called when submitting a single-line field (Return/Enter). Receives current text.
  public var onSubmit: ((String) -> Void)?

  /// Placeholder shown when text is empty.
  public var placeholder: String? = nil
  public var placeholderStyle: TextStyle = TextStyle.textFieldPlaceholder

  // MARK: - Styling

  public var backgroundColor = Color.gray700.withAlphaComponent(0.30)
  public var focusedBackgroundColor = Color.gray700.withAlphaComponent(0.40)
  public var borderColor = Color.gray500.withAlphaComponent(0.45)
  public var focusedBorderColor = Color.gray400
  public var selectionColor = Color.rose.withAlphaComponent(0.35)
  public var selectionUnfocusedColor = Color.gray700
  public var caretColor = Color.gray300
  public var cornerRadius: Float = 6
  public var borderWidth: Float = 2
  public var contentInsets: EdgeInsets = EdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
  public var textStyle: TextStyle = TextStyle.textField
  public var bezeled: Bool = true  // when false: no background, no border

  // Left icon support
  public var leftIcon: Image? = nil
  public var leftIconTint: Color = .gray400
  public var leftIconSize: Float? = nil  // if nil, uses ~0.9 * font size
  public var leftIconPadding: Float = 8

  // MARK: - Private State

  private var editor: TextEditor
  private var isDragging: Bool = false
  private var lastClickTime: Double = 0
  private var lastClickLocation: Point = .zero
  private var clickCount: Int = 0
  private let caret = TextInsertionIndicator()

  // Scrolling offset for when text is clipped
  private var scrollOffsetX: Float = 0

  // Global reference to focused field for text input routing
  private static weak var focusedField: TextField?

  /// Get the currently focused TextField (if any).
  public static var currentFocusedField: TextField? { focusedField }

  // MARK: - Init

  public init(frame: Rect = .zero, text: String = "", singleLine: Bool = true) {
    self.frame = frame
    self.editor = TextEditor(singleLine: singleLine)
    self.editor.text = text
  }

  // MARK: - Drawing

  public func draw() {
    guard let ctx = GraphicsContext.current else { return }
    // Background + bezel
    if bezeled {
      let bg = isFocused ? focusedBackgroundColor : backgroundColor
      RoundedRect(frame, cornerRadius: cornerRadius).draw(color: bg)
      RoundedRect(frame, cornerRadius: cornerRadius)
        .stroke(color: isFocused ? focusedBorderColor : borderColor, lineWidth: borderWidth)
    }

    // Text origin and baseline
    var textOriginX = frame.origin.x + contentInsets.left
    let baselineY: Float =
      editor.isSingleLine
      ? (frame.midY - textStyle.fontSize * 0.2)  // visual nudge upward
      : (frame.origin.y + contentInsets.top + textStyle.fontSize * 0.85)

    // Draw left icon if present and shift text origin accordingly
    if let icon = leftIcon {
      let desiredH = leftIconSize ?? 20  //(textStyle.fontSize * 0.9)
      let aspect = icon.naturalSize.width / max(1, icon.naturalSize.height)
      let iconW = desiredH * aspect
      let iconX = frame.origin.x + contentInsets.left
      let iconY = frame.midY - desiredH * 0.5
      let iconRect = Rect(x: iconX, y: iconY, width: iconW, height: desiredH)
      if let ctx = GraphicsContext.current {
        ctx.renderer.drawImage(textureID: icon.textureID, in: iconRect, tint: leftIconTint, strokeWidth: 0, strokeColor: nil, shadowColor: nil, shadowOffset: Point(0, 0), shadowBlur: 0)
      }
      textOriginX += iconW + leftIconPadding
    }

    // Prepare font/advances for proportional layout
    var advances: [Float] = []
    let scalars = Array(editor.text.unicodeScalars)
    if let font = Font(fontName: textStyle.fontName, pixelHeight: textStyle.fontSize), !scalars.isEmpty {
      advances.reserveCapacity(scalars.count)
      for i in 0..<scalars.count {
        let codepoint = Int32(scalars[i].value)
        let next: Int32? = (i + 1 < scalars.count) ? Int32(scalars[i + 1].value) : nil
        advances.append(font.getAdvance(for: codepoint, next: next, scale: 1.0))
      }
      editor.setAdvances(advances)
    }

    // Clip to field bounds so text stays inside
    ctx.save()
    let clipRect = Rect(
      x: frame.origin.x + contentInsets.left,
      y: frame.origin.y + contentInsets.top,
      width: frame.size.width - contentInsets.left - contentInsets.right,
      height: frame.size.height - contentInsets.top - contentInsets.bottom)
    ctx.clip(to: clipRect)

    // Apply scroll offset
    let effectiveTextOriginX = textOriginX - scrollOffsetX

    // Selection (behind text) using proportional widths
    if !scalars.isEmpty {
      var adjustedBaselineY = baselineY
      if editor.isSingleLine { adjustedBaselineY += textStyle.fontSize * 0.6 - 3 }
      let frags = editor.lineFragments(originX: effectiveTextOriginX, originY: adjustedBaselineY)
      let sel = editor.selection.range
      let selEnd = sel.location + sel.length
      if sel.length > 0 {
        for (lineIndex, frag) in frags.enumerated() {
          _ = lineIndex  // keep for potential debugging
          let lineStart = frag.start
          let lineEnd = frag.start + frag.length
          let segStart = max(sel.location, lineStart)
          let segEnd = min(selEnd, lineEnd)
          if segEnd > segStart {
            let x0 = effectiveTextOriginX + sumAdv(advances, from: lineStart, to: segStart)
            let w = sumAdv(advances, from: segStart, to: segEnd)
            let selColor = isFocused ? selectionColor : selectionUnfocusedColor
            Rect(x: x0, y: frag.rect.y, width: w, height: frag.rect.height).fill(with: selColor)
          }
        }
      }
    }

    // Text content or placeholder
    if editor.text.isEmpty, let placeholder {
      placeholder.draw(at: Point(effectiveTextOriginX, baselineY), style: placeholderStyle, anchor: .baselineLeft)
    } else {
      editor.text.draw(at: Point(effectiveTextOriginX, baselineY), style: textStyle, anchor: .baselineLeft)
    }

    // Caret (on top)
    if isFocused {
      // Compute caret X using proportional advances, Y/height from line fragment
      var caretX = effectiveTextOriginX
      var caretY: Float = baselineY
      var caretH: Float = textStyle.fontSize
      var adjustedBaselineY = baselineY
      if editor.isSingleLine { adjustedBaselineY += textStyle.fontSize * 0.6 }
      let frags = editor.lineFragments(originX: effectiveTextOriginX, originY: adjustedBaselineY)
      let ip = editor.insertionPoint
      for frag in frags {
        if ip >= frag.start && ip <= frag.start + frag.length {
          caretX = effectiveTextOriginX + sumAdv(advances, from: frag.start, to: ip)
          caretY = frag.rect.y
          caretH = frag.rect.height
          break
        }
      }
      // Set an offset so the caret aligns with the text's visual baseline
      caret.yOffset = editor.isSingleLine ? (-textStyle.fontSize * 0.2) : 0
      caret.draw(at: caretX, y: caretY, height: caretH, focused: isFocused)
    }

    // Restore clipping
    ctx.restore()
  }

  // MARK: - Input Handling

  @discardableResult
  public func handleKey(_ key: Keyboard.Key) -> Bool { handleKey(key, mods: []) }

  /// Variant that includes modifiers to support shifted selection and future word-selection with Alt.
  @discardableResult
  public func handleKey(_ key: Keyboard.Key, mods: Keyboard.Modifier) -> Bool {
    guard isFocused else { return false }

    // Handle copy/cut/paste with platform-appropriate modifiers
    #if os(macOS)
      let commandModifier = Keyboard.Modifier.command
    #else
      let commandModifier = Keyboard.Modifier.control
    #endif

    if mods.contains(commandModifier) {
      switch key {
      case .c:
        // Copy
        let sel = editor.selection.range
        if sel.length > 0 {
          let startIdx = editor.text.startIndex
          let selStart = editor.text.index(startIdx, offsetBy: sel.location)
          let selEnd = editor.text.index(selStart, offsetBy: sel.length)
          let selectedText = String(editor.text[selStart..<selEnd])
          GLFWSession.clipboard = selectedText
        }
        return true
      case .x:
        // Cut
        let sel = editor.selection.range
        if sel.length > 0 {
          let startIdx = editor.text.startIndex
          let selStart = editor.text.index(startIdx, offsetBy: sel.location)
          let selEnd = editor.text.index(selStart, offsetBy: sel.length)
          let selectedText = String(editor.text[selStart..<selEnd])
          GLFWSession.clipboard = selectedText
          editor.key(.delete)
          updateScrollOffset()
        }
        return true
      case .v:
        // Paste
        if let clipboardText = GLFWSession.clipboard {
          // If there's a selection, delete it first
          let sel = editor.selection.range
          if sel.length > 0 {
            editor.key(.delete)
          }
          _ = editor.paste(clipboardText)
          updateScrollOffset()
        }
        return true
      case .a:
        // Select all
        editor.selectAll()
        updateScrollOffset()
        return true
      default:
        break
      }
    }

    let shift = mods.contains(.shift)
    switch key {
    case .left:
      editor.key(.left(shift: shift))
      updateScrollOffset()
      return true
    case .right:
      editor.key(.right(shift: shift))
      updateScrollOffset()
      return true
    case .up:
      editor.key(.up(shift: shift))
      updateScrollOffset()
      return true
    case .down:
      editor.key(.down(shift: shift))
      updateScrollOffset()
      return true
    case .home:
      editor.key(.lineStart(shift: shift))
      updateScrollOffset()
      return true
    case .end:
      editor.key(.lineEnd(shift: shift))
      updateScrollOffset()
      return true
    case .backspace:
      editor.key(.backspace)
      updateScrollOffset()
      return true
    case .delete:
      editor.key(.delete)
      updateScrollOffset()
      return true
    case .escape:
      // Cancel editing: simply unfocus
      isFocused = false
      return true
    case .enter, .numpadEnter:
      onCommit?()
      if editor.isSingleLine {
        onSubmit?(text)
        isFocused = false
      }
      return true
    default:
      return false
    }
  }

  /// Insert literal text (e.g., from a character/text input event).
  @discardableResult
  public func insertText(_ string: String) -> Bool {
    guard isFocused else { return false }
    // If there's a selection, delete it first
    let sel = editor.selection.range
    if sel.length > 0 {
      editor.key(.delete)
    }
    editor.insert(string)
    updateScrollOffset()
    return true
  }

  @discardableResult
  public func handleMouseDown(at position: Point) -> Bool {
    guard frame.contains(position) else { return false }
    // Multi-click detection (simple double/triple click)
    let now = Date().timeIntervalSinceReferenceDate
    let dt = now - lastClickTime
    let dx = position.x - lastClickLocation.x
    let dy = position.y - lastClickLocation.y
    if dt < 0.3 && (dx * dx + dy * dy) < 16 { clickCount += 1 } else { clickCount = 1 }
    lastClickTime = now
    lastClickLocation = position

    var textOriginX = frame.origin.x + contentInsets.left
    if let icon = leftIcon {
      let desiredH = leftIconSize ?? (textStyle.fontSize * 0.9)
      let aspect = icon.naturalSize.width / max(1, icon.naturalSize.height)
      let iconW = desiredH * aspect
      textOriginX += iconW + leftIconPadding
    }
    let baselineY: Float =
      editor.isSingleLine
      ? (frame.midY - textStyle.fontSize * 0.2) : (frame.origin.y + contentInsets.top + textStyle.fontSize * 0.85)
    // Account for scroll offset when calculating local coordinates
    let effectiveTextOriginX = textOriginX - scrollOffsetX
    let localX = position.x - effectiveTextOriginX
    let localY = position.y - baselineY
    editor.click(x: localX, y: localY)

    if clickCount == 2 {
      // Select word under caret
      let ip = editor.insertionPoint
      let (wStart, wEnd) = wordRange(containing: ip)
      let startX = localXForIndex(wStart, originX: effectiveTextOriginX, originY: baselineY) - effectiveTextOriginX
      let endX = localXForIndex(wEnd, originX: effectiveTextOriginX, originY: baselineY) - effectiveTextOriginX
      editor.click(x: startX, y: localY)
      editor.drag(x: endX, y: localY)
      isDragging = false
    } else if clickCount >= 3 {
      // Select all text
      let len = editor.text.unicodeScalars.count
      editor.click(x: 0, y: localY)
      let endX = localXForIndex(len, originX: effectiveTextOriginX, originY: baselineY) - effectiveTextOriginX
      editor.drag(x: endX, y: localY)
      isDragging = false
      clickCount = 0
    } else {
      isDragging = true
    }
    return true
  }

  public func handleMouseMove(at position: Point) {
    guard isDragging else { return }
    var textOriginX = frame.origin.x + contentInsets.left
    if let icon = leftIcon {
      let desiredH = leftIconSize ?? (textStyle.fontSize * 0.9)
      let aspect = icon.naturalSize.width / max(1, icon.naturalSize.height)
      let iconW = desiredH * aspect
      textOriginX += iconW + leftIconPadding
    }
    let baselineY: Float =
      editor.isSingleLine
      ? (frame.midY - textStyle.fontSize * 0.2) : (frame.origin.y + contentInsets.top + textStyle.fontSize * 0.85)
    // Account for scroll offset when calculating local coordinates
    let effectiveTextOriginX = textOriginX - scrollOffsetX
    editor.drag(x: position.x - effectiveTextOriginX, y: position.y - baselineY)
  }

  public func handleMouseUp() { isDragging = false }

  // MARK: - Private helpers

  @inline(__always)
  private func sumAdv(_ adv: [Float], from start: Int, to end: Int) -> Float {
    if adv.isEmpty { return 0 }
    let clampedStart = max(0, min(start, adv.count))
    let clampedEnd = max(clampedStart, min(end, adv.count))
    var s: Float = 0
    var i = clampedStart
    while i < clampedEnd {
      s += adv[i]
      i += 1
    }
    return s
  }

  private func localXForIndex(_ index: Int, originX: Float, originY: Float) -> Float {
    let frags = editor.lineFragments(originX: originX, originY: originY)
    guard let frag = frags.first else { return originX }
    let clampedIndex = max(frag.start, min(frag.start + frag.length, index))
    let length = max(1, frag.length)
    let charAdvance = frag.rect.width / Float(length)
    let col = clampedIndex - frag.start
    return frag.rect.x + Float(col) * charAdvance
  }

  private func wordRange(containing index: Int) -> (start: Int, end: Int) {
    let scalars = Array(editor.text.unicodeScalars)
    if scalars.isEmpty { return (0, 0) }
    let clamped = max(0, min(index, scalars.count))
    let isWord: (UnicodeScalar) -> Bool = { s in
      let v = s.value
      if v == 95 { return true }  // underscore
      if v >= 48 && v <= 57 { return true }  // 0-9
      if v >= 65 && v <= 90 { return true }  // A-Z
      if v >= 97 && v <= 122 { return true }  // a-z
      return false
    }
    var start = clamped
    var end = clamped
    while start > 0 && isWord(scalars[start - 1]) { start -= 1 }
    while end < scalars.count && isWord(scalars[end]) { end += 1 }
    return (start, end)
  }

  /// Update scroll offset to keep caret visible when text is clipped
  private func updateScrollOffset() {
    guard isFocused else { return }

    var textOriginX = frame.origin.x + contentInsets.left
    if let icon = leftIcon {
      let desiredH = leftIconSize ?? 20
      let aspect = icon.naturalSize.width / max(1, icon.naturalSize.height)
      let iconW = desiredH * aspect
      textOriginX += iconW + leftIconPadding
    }

    let availableWidth =
      frame.size.width - contentInsets.left - contentInsets.right
      - (textOriginX - (frame.origin.x + contentInsets.left))

    // Calculate total text width
    var advances: [Float] = []
    let scalars = Array(editor.text.unicodeScalars)
    if let font = Font(fontName: textStyle.fontName, pixelHeight: textStyle.fontSize), !scalars.isEmpty {
      advances.reserveCapacity(scalars.count)
      for i in 0..<scalars.count {
        let codepoint = Int32(scalars[i].value)
        let next: Int32? = (i + 1 < scalars.count) ? Int32(scalars[i + 1].value) : nil
        advances.append(font.getAdvance(for: codepoint, next: next, scale: 1.0))
      }
    }

    let totalTextWidth = sumAdv(advances, from: 0, to: scalars.count)

    // If text fits, no scrolling needed
    if totalTextWidth <= availableWidth {
      scrollOffsetX = 0
      return
    }

    // Find caret position
    let baselineY: Float =
      editor.isSingleLine
      ? (frame.midY - textStyle.fontSize * 0.2)
      : (frame.origin.y + contentInsets.top + textStyle.fontSize * 0.85)
    var adjustedBaselineY = baselineY
    if editor.isSingleLine { adjustedBaselineY += textStyle.fontSize * 0.6 }

    let ip = editor.insertionPoint
    let caretX = textOriginX + sumAdv(advances, from: 0, to: ip)

    // Calculate visible range
    let visibleLeft = textOriginX - scrollOffsetX
    let visibleRight = visibleLeft + availableWidth

    // Adjust scroll to keep caret visible
    if caretX < visibleLeft {
      // Caret is to the left of visible area - scroll left
      scrollOffsetX = textOriginX - caretX + 8  // Add small padding
    } else if caretX > visibleRight {
      // Caret is to the right of visible area - scroll right
      scrollOffsetX = textOriginX - caretX + availableWidth - 8  // Add small padding
    }

    // Clamp scroll offset
    let maxScroll = max(0, totalTextWidth - availableWidth)
    scrollOffsetX = max(0, min(scrollOffsetX, maxScroll))
  }
}
