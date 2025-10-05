import Foundation
import STBTrueType

/// Handles text layout, line wrapping, and measurement
public final class TextLayout {
  private let font: TrueTypeFont
  private let scale: Float

  init(font: TrueTypeFont, scale: Float = 1.0) {
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

  /// Measure the width of a string
  func measureWidth(_ text: String) -> Float {
    var width: Float = 0
    let bytes = Array(text.utf8)
    var i = 0

    while i < bytes.count {
      let codepoint = Int32(bytes[i])
      let next: Int32? = (i + 1 < bytes.count) ? Int32(bytes[i + 1]) : nil
      width += font.getAdvance(for: codepoint, next: next) * scale
      i += 1
    }

    return width
  }

  // MARK: - Private Methods

  private func wrapText(_ text: String, wrapWidth: Float?) -> [Line] {
    guard let wrapWidth = wrapWidth else {
      // No wrapping - return single line
      return [
        Line(
          text: text,
          startIndex: text.startIndex,
          endIndex: text.endIndex,
          width: measureWidth(text),
          baselineY: 0
        )
      ]
    }

    var lines: [Line] = []
    var currentLine = ""
    var currentStart = text.startIndex
    let currentIndex = text.startIndex

    // Simple word-based wrapping
    let words = text.components(separatedBy: .whitespacesAndNewlines)
    var wordIndex = 0

    while wordIndex < words.count {
      let word = words[wordIndex]

      // Handle newlines explicitly
      if word.isEmpty && wordIndex < words.count - 1 {
        // This is a newline - finalize current line
        if !currentLine.isEmpty {
          lines.append(
            createLine(
              text: currentLine,
              startIndex: currentStart,
              endIndex: currentIndex,
              baselineY: Float(lines.count)
            ))
          currentLine = ""
        }
        // Add empty line for the newline
        lines.append(
          createLine(
            text: "",
            startIndex: currentIndex,
            endIndex: currentIndex,
            baselineY: Float(lines.count)
          ))
        wordIndex += 1
        continue
      }

      let testLine = currentLine.isEmpty ? word : currentLine + " " + word
      let testWidth = measureWidth(testLine)

      if testWidth <= wrapWidth || currentLine.isEmpty {
        // Word fits or it's the first word on the line
        currentLine = testLine
        wordIndex += 1
      } else {
        // Word doesn't fit - finalize current line
        if !currentLine.isEmpty {
          lines.append(
            createLine(
              text: currentLine,
              startIndex: currentStart,
              endIndex: currentIndex,
              baselineY: Float(lines.count)
            ))
        }
        currentLine = word
        currentStart = currentIndex
        wordIndex += 1
      }
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
    // Trim whitespace from the line
    let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let width = measureWidth(trimmedText)

    return Line(
      text: trimmedText,
      startIndex: startIndex,
      endIndex: endIndex,
      width: width,
      baselineY: baselineY
    )
  }
}
