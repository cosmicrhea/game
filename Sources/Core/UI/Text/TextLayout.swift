import Foundation
import STBTrueType

/// Handles text layout, line wrapping, and measurement
public final class TextLayout {
  private let font: Font
  private let scale: Float

  init(font: Font, scale: Float = 1.0) {
    self.font = font
    self.scale = scale
  }

  /// Represents a single line of text with its metrics
  struct Line {
    let text: String
    let startIndex: String.Index
    let endIndex: String.Index
    let width: Float
    let baselineY: Float
  }

  /// Layout result containing all lines and total metrics
  struct LayoutResult {
    let lines: [Line]
    let totalWidth: Float
    let totalHeight: Float
    let lineHeight: Float
  }

  /// Layout text with optional wrapping
  func layout(
    _ text: String,
    wrapWidth: Float? = nil,
    lineHeight: Float
  ) -> LayoutResult {
    let lines = wrapText(text, wrapWidth: wrapWidth)
    let totalWidth = lines.map(\.width).max() ?? 0
    let totalHeight = Float(lines.count) * lineHeight

    return LayoutResult(
      lines: lines,
      totalWidth: totalWidth,
      totalHeight: totalHeight,
      lineHeight: lineHeight
    )
  }

  /// Layout text with TextStyle (uses TextStyle lineHeight if available)
  func layout(
    _ text: String,
    style: TextStyle,
    wrapWidth: Float? = nil
  ) -> LayoutResult {
    let effectiveLineHeight = (style.lineHeight ?? 1.0) * font.lineHeight
    return layout(text, wrapWidth: wrapWidth, lineHeight: effectiveLineHeight)
  }

  /// Measure the width of a string
  func measureWidth(_ text: String) -> Float {
    var width: Float = 0
    let scalars = Array(text.unicodeScalars)
    var i = 0

    while i < scalars.count {
      let codepoint = Int32(scalars[i].value)

      // Handle spaces with consistent width like the rendering code
      if codepoint == 32 {  // Space character
        // Use a reasonable space width to match rendering behavior
        let spaceWidth: Float = 8  // Default space width (matches GLRenderer)
        width += spaceWidth * scale
        i += 1
        continue
      }

      let next: Int32? = (i + 1 < scalars.count) ? Int32(scalars[i + 1].value) : nil
      width += font.getTrueTypeFont().getAdvance(for: codepoint, next: next) * scale
      i += 1
    }

    return width
  }

  // MARK: - Private Methods

  private func processNewlines(_ text: String) -> [Line] {
    var lines: [Line] = []
    var currentLine = ""
    var currentStart = text.startIndex
    var currentIndex = text.startIndex

    while currentIndex < text.endIndex {
      let char = text[currentIndex]

      if char == "\n" {
        // Found a newline - finalize current line
        if !currentLine.isEmpty {
          lines.append(
            createLine(
              text: currentLine,
              startIndex: currentStart,
              endIndex: currentIndex,
              baselineY: Float(lines.count)
            ))
        } else {
          // Empty line
          lines.append(
            createLine(
              text: "",
              startIndex: currentIndex,
              endIndex: currentIndex,
              baselineY: Float(lines.count)
            ))
        }

        currentLine = ""
        currentIndex = text.index(after: currentIndex)
        currentStart = currentIndex
        continue
      }

      // Add character to current line
      currentLine.append(char)
      currentIndex = text.index(after: currentIndex)
    }

    // Add final line if there's content
    if !currentLine.isEmpty {
      lines.append(
        createLine(
          text: currentLine,
          startIndex: currentStart,
          endIndex: text.endIndex,
          baselineY: Float(lines.count)
        ))
    }

    return lines
  }

  private func wrapText(_ text: String, wrapWidth: Float?) -> [Line] {
    guard let wrapWidth = wrapWidth else {
      // No wrapping - but still need to process newlines
      return processNewlines(text)
    }

    // If wrapWidth is effectively infinite, just process newlines
    if wrapWidth >= Float.greatestFiniteMagnitude {
      return processNewlines(text)
    }

    var lines: [Line] = []
    var currentLine = ""
    var currentStart = text.startIndex
    var currentIndex = text.startIndex

    // Process text character by character to properly handle newlines
    while currentIndex < text.endIndex {
      let char = text[currentIndex]

      if char == "\n" {
        // Found a newline - finalize current line and move to next line
        if !currentLine.isEmpty {
          lines.append(
            createLine(
              text: currentLine,
              startIndex: currentStart,
              endIndex: currentIndex,
              baselineY: Float(lines.count)
            ))
        }

        currentLine = ""
        currentIndex = text.index(after: currentIndex)

        // Check if this is a consecutive newline (paragraph break)
        if currentIndex < text.endIndex && text[currentIndex] == "\n" {
          // This is \n\n - add an empty line for paragraph spacing
          lines.append(
            createLine(
              text: "",
              startIndex: currentIndex,
              endIndex: currentIndex,
              baselineY: Float(lines.count)
            ))
          currentIndex = text.index(after: currentIndex)
        }

        currentStart = currentIndex
        continue
      }

      // Add character to current line
      currentLine.append(char)

      // Check if current line exceeds wrap width
      let testWidth = measureWidth(currentLine)
      if testWidth > wrapWidth && !currentLine.isEmpty {
        // Line is too wide - need to wrap
        // Find the last space to break at
        var breakIndex = currentLine.lastIndex(of: " ")
        if breakIndex == nil || breakIndex == currentLine.startIndex {
          // No space found or space is at start - break at current character
          breakIndex = currentLine.index(before: currentLine.endIndex)
        }

        // Extract the part that fits
        let fittingPart = String(currentLine[..<breakIndex!])
        let remainingPart = String(currentLine[text.index(after: breakIndex!)...])

        if !fittingPart.isEmpty {
          lines.append(
            createLine(
              text: fittingPart,
              startIndex: currentStart,
              endIndex: currentIndex,
              baselineY: Float(lines.count)
            ))
        }

        currentLine = remainingPart
        currentStart = currentIndex
      }

      currentIndex = text.index(after: currentIndex)
    }

    // Add final line if there's content
    if !currentLine.isEmpty {
      lines.append(
        createLine(
          text: currentLine,
          startIndex: currentStart,
          endIndex: text.endIndex,
          baselineY: Float(lines.count)
        ))
    }

    return lines
  }

  private func createLine(
    text: String,
    startIndex: String.Index,
    endIndex: String.Index,
    baselineY: Float
  ) -> Line {
    // Don't trim whitespace - spaces are important for proper text measurement
    let width = measureWidth(text)

    return Line(
      text: text,
      startIndex: startIndex,
      endIndex: endIndex,
      width: width,
      baselineY: baselineY
    )
  }
}
