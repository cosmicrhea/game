import STBTextEdit

import struct Foundation.Date

@MainActor
public final class TextField: OptionsControl {
  // MARK: - Public API

  public var frame: Rect
  public var isFocused: Bool = false

  /// The field's text content (backed by `TextEditor`).
  public var text: String {
    get { editor.text }
    set { editor.text = newValue }
  }

  /// Called when Return/Enter is pressed while focused.
  public var onCommit: (() -> Void)?

  /// Placeholder shown when text is empty.
  public var placeholder: String? = nil
  public var placeholderStyle: TextStyle = TextStyle.textFieldPlaceholder

  // MARK: - Styling

  public var backgroundColor = Color.gray700.withAlphaComponent(0.30)
  public var focusedBackgroundColor = Color.gray700.withAlphaComponent(0.40)
  public var borderColor = Color.gray500.withAlphaComponent(0.45)
  public var focusedBorderColor = Color.gray400
  public var selectionColor = Color.rose.withAlphaComponent(0.35)
  public var caretColor = Color.gray300
  public var cornerRadius: Float = 6
  public var borderWidth: Float = 2
  public var contentInsets: EdgeInsets = EdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
  public var textStyle: TextStyle = TextStyle.textField
  public var bordered: Bool = true

  // MARK: - Private State

  private var editor: TextEditor
  private var isDragging: Bool = false
  private var lastClickTime: Double = 0
  private var lastClickLocation: Point = .zero
  private var clickCount: Int = 0

  // MARK: - Init

  public init(frame: Rect = .zero, text: String = "", singleLine: Bool = true) {
    self.frame = frame
    self.editor = TextEditor(singleLine: singleLine)
    self.editor.text = text
  }

  // MARK: - Drawing

  public func draw() {
    // Background
    let bg = isFocused ? focusedBackgroundColor : backgroundColor
    RoundedRect(frame, cornerRadius: cornerRadius).draw(color: bg)
    if bordered {
      RoundedRect(frame, cornerRadius: cornerRadius)
        .stroke(color: isFocused ? focusedBorderColor : borderColor, lineWidth: borderWidth)
    }

    // Text origin and baseline
    let textOriginX = frame.origin.x + contentInsets.left
    let baselineY: Float = editor.isSingleLine
      ? frame.midY
      : (frame.origin.y + contentInsets.top + textStyle.fontSize)

    // Selection (behind text)
    let selectionRects = editor.selectionRects(originX: textOriginX, originY: baselineY)
    for r in selectionRects { Rect(x: r.x, y: r.y, width: r.width, height: r.height).fill(with: selectionColor) }

    // Text content or placeholder
    if editor.text.isEmpty, let placeholder {
      placeholder.draw(at: Point(textOriginX, baselineY), style: placeholderStyle, anchor: .baselineLeft)
    } else {
      editor.text.draw(at: Point(textOriginX, baselineY), style: textStyle, anchor: .baselineLeft)
    }

    // Caret (on top)
    if isFocused {
      let caret = editor.caretRect(originX: textOriginX, originY: baselineY, caretWidth: 1)
      Rect(x: caret.x, y: caret.y, width: caret.width, height: caret.height).fill(with: caretColor)
    }
  }

  // MARK: - Input Handling

  @discardableResult
  public func handleKey(_ key: Keyboard.Key) -> Bool {
    guard isFocused else { return false }
    switch key {
    case .a:
      // Cmd+A selects all when focused
      // We don't get modifiers here, so implement as: if focused and 'a' pressed with command elsewhere,
      // but for now, treat Command+A as handled via Engine key handler; here we provide select-all on 'command' modifier check if available.
      return false
    case .left:
      editor.key(.left(shift: false))
      return true
    case .right:
      editor.key(.right(shift: false))
      return true
    case .up:
      editor.key(.up(shift: false))
      return true
    case .down:
      editor.key(.down(shift: false))
      return true
    case .home:
      editor.key(.lineStart(shift: false))
      return true
    case .end:
      editor.key(.lineEnd(shift: false))
      return true
    case .backspace:
      editor.key(.backspace)
      return true
    case .delete:
      editor.key(.delete)
      return true
    case .enter, .numpadEnter:
      onCommit?()
      return true
    default:
      return false
    }
  }

  /// Insert literal text (e.g., from a character/text input event).
  @discardableResult
  public func insertText(_ string: String) -> Bool {
    guard isFocused else { return false }
    editor.insert(string)
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

    let textOriginX = frame.origin.x + contentInsets.left
    let baselineY = frame.midY
    let localX = position.x - textOriginX
    let localY = position.y - baselineY
    editor.click(x: localX, y: localY)

    if clickCount == 2 {
      // Select word under caret
      let ip = editor.insertionPoint
      let (wStart, wEnd) = wordRange(containing: ip)
      let startX = localXForIndex(wStart, originX: textOriginX, originY: baselineY) - textOriginX
      let endX = localXForIndex(wEnd, originX: textOriginX, originY: baselineY) - textOriginX
      editor.click(x: startX, y: localY)
      editor.drag(x: endX, y: localY)
      isDragging = false
    } else if clickCount >= 3 {
      // Select all text
      let len = editor.text.unicodeScalars.count
      editor.click(x: 0, y: localY)
      let endX = localXForIndex(len, originX: textOriginX, originY: baselineY) - textOriginX
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
    let textOriginX = frame.origin.x + contentInsets.left
    let baselineY: Float = editor.isSingleLine
      ? frame.midY
      : (frame.origin.y + contentInsets.top + textStyle.fontSize)
    editor.drag(x: position.x - textOriginX, y: position.y - baselineY)
  }

  public func handleMouseUp() { isDragging = false }

  // MARK: - Private helpers

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
}
