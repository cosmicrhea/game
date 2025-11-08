/// Represents the data for a single slot containing a document in a DocumentSlotGrid
public struct DocumentSlotData: Sendable {
  public let document: Document?
  public let isDiscovered: Bool

  public init(document: Document? = nil, isDiscovered: Bool = false) {
    self.document = document
    self.isDiscovered = isDiscovered
  }

  /// Returns true if the slot is empty
  public var isEmpty: Bool {
    return document == nil
  }

  /// Returns true if the slot contains a document
  public var hasDocument: Bool {
    return document != nil
  }
}
