import class Foundation.DateFormatter
import struct Foundation.Locale

struct SaveStateRow {
  let slotIndex: Int
  let state: SaveState?

  private static let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "dd/MM/yyyy"
    return formatter
  }()

  private static let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "HH:mm"
    return formatter
  }()

  private static func formatRelativeDate(_ date: Date) -> String {
    let calendar = Calendar.current

    if calendar.isDateInToday(date) {
      return "Today"
    } else if calendar.isDateInYesterday(date) {
      return "Yesterday"
    } else {
      return dateFormatter.string(from: date)
    }
  }

  func draw(in rect: Rect, isSelected: Bool) {
    let backgroundAlpha: Float = isSelected ? 0.55 : 0.35
    let backgroundColor = Color.gray700.withAlphaComponent(backgroundAlpha)
    RoundedRect(rect, cornerRadius: 3).draw(color: backgroundColor)

    let padding: Float = 18
    let leftColumnWidth: Float = 86
    let rightColumnWidth: Float = 140

    let leftRect = Rect(
      x: rect.origin.x + padding,
      y: rect.origin.y,
      width: leftColumnWidth,
      height: rect.size.height
    )

    let centerRect = Rect(
      x: leftRect.maxX,
      y: rect.origin.y,
      width: rect.size.width - leftColumnWidth - rightColumnWidth - padding * 2,
      height: rect.size.height
    )

    let rightRect = Rect(
      x: rect.maxX - rightColumnWidth - padding,
      y: rect.origin.y,
      width: rightColumnWidth,
      height: rect.size.height
    )

    let badgeText: String
    if let state {
      badgeText = state.isAutoSave ? "AUTO" : "\(state.saveCount)"
    } else {
      badgeText = "—"
    }
    badgeText.draw(
      at: Point(leftRect.midX, leftRect.midY),
      style: TextStyle.saveSlotBadge,
      anchor: .center
    )

    let (areaLine, subAreaLine) = displayLines()
    areaLine.draw(
      at: Point(centerRect.origin.x, centerRect.midY + 10),
      style: TextStyle.saveSlotPrimary,
      anchor: .left
    )
    subAreaLine.draw(
      at: Point(centerRect.origin.x, centerRect.midY - 12),
      style: TextStyle.saveSlotSecondary,
      anchor: .left
    )

    if let state {
      let dateText = Self.formatRelativeDate(state.lastSavedAt)
      let timeText = Self.timeFormatter.string(from: state.lastSavedAt)
      dateText.draw(
        at: Point(rightRect.maxX, rightRect.midY + 10),
        style: TextStyle.saveSlotDate,
        anchor: .right
      )
      timeText.draw(
        at: Point(rightRect.maxX, rightRect.midY - 10),
        style: TextStyle.saveSlotDate,
        anchor: .right
      )
    }
  }

  private func displayLines() -> (String, String) {
    if let state {
      let components = state.sceneName.split(separator: "/", maxSplits: 1).map {
        $0.trimmingCharacters(in: .whitespaces)
      }
      let main = components.first ?? ""
      let sub = components.count > 1 ? components[1] : state.cameraName.replacingOccurrences(of: "_", with: " ")
      return (main, sub)
    } else {
      return ("NO DATA", "")
    }
  }
}
