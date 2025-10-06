import Foundation

/// Represents a text attribute applied to a specific range
public struct TextAttribute {
  public let range: Range<String.Index>
  public let color: (Float, Float, Float, Float)?
  public let font: String?

  public init(range: Range<String.Index>, color: (Float, Float, Float, Float)? = nil, font: String? = nil) {
    self.range = range
    self.color = color
    self.font = font
  }
}

/// Attributed text that supports color and font changes within the same text
public struct AttributedText {
  public let text: String
  public let attributes: [TextAttribute]

  public init(text: String, attributes: [TextAttribute] = []) {
    self.text = text
    self.attributes = attributes
  }

  /// Create attributed text with a single color applied to the entire text
  public static func withColor(_ text: String, color: (Float, Float, Float, Float)) -> AttributedText {
    return AttributedText(
      text: text,
      attributes: [TextAttribute(range: text.startIndex..<text.endIndex, color: color)]
    )
  }

  /// Apply a color to a specific range of text
  public func withColor(_ color: (Float, Float, Float, Float), range: Range<String.Index>) -> AttributedText {
    let newAttribute = TextAttribute(range: range, color: color)
    return AttributedText(text: text, attributes: attributes + [newAttribute])
  }

  /// Apply a color to a specific substring
  public func withColor(_ color: (Float, Float, Float, Float), substring: String) -> AttributedText {
    guard let range = text.range(of: substring) else { return self }
    return withColor(color, range: range)
  }

  /// Get the color for a character at a specific index
  public func colorAt(index: String.Index) -> (Float, Float, Float, Float)? {
    // Safety check: ensure index is within bounds
    guard index >= text.startIndex && index < text.endIndex else {
      return nil
    }

    for attribute in attributes {
      if attribute.range.contains(index) {
        return attribute.color
      }
    }
    return nil
  }

  /// Get all color changes in the text as a list of (index, color) pairs
  public func colorChanges() -> [(String.Index, (Float, Float, Float, Float))] {
    var changes: [(String.Index, (Float, Float, Float, Float))] = []

    for attribute in attributes {
      if let color = attribute.color {
        changes.append((attribute.range.lowerBound, color))
        if attribute.range.upperBound < text.endIndex {
          changes.append((attribute.range.upperBound, (1.0, 1.0, 1.0, 1.0)))  // Default white
        }
      }
    }

    return changes.sorted { $0.0 < $1.0 }
  }
}

/// Helper for creating attributed text with common patterns
extension AttributedText {
  /// Create attributed text with green highlighting for specific words
  public static func withGreenHighlight(_ text: String, words: [String]) -> AttributedText {
    var attributed = AttributedText(text: text)

    for word in words {
      attributed = attributed.withColor((0.0, 1.0, 0.0, 1.0), substring: word)
    }

    return attributed
  }

  /// Create attributed text with red highlighting for specific words
  public static func withRedHighlight(_ text: String, words: [String]) -> AttributedText {
    var attributed = AttributedText(text: text)

    for word in words {
      attributed = attributed.withColor((1.0, 0.0, 0.0, 1.0), substring: word)
    }

    return attributed
  }
}
