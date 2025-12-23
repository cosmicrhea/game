extension Int {
  /// Format byte count as human-readable string (e.g., "1 MB", "419 KB", "4.2 MB")
  func formatBytes() -> String {
    let kb = 1024
    let mb = kb * 1024
    let gb = mb * 1024
    
    if self >= gb {
      let value = Double(self) / Double(gb)
      return String(format: "%.1f GB", value)
    } else if self >= mb {
      let value = Double(self) / Double(mb)
      if value >= 10 {
        return String(format: "%.0f MB", value)
      } else {
        return String(format: "%.1f MB", value)
      }
    } else if self >= kb {
      let value = Double(self) / Double(kb)
      if value >= 10 {
        return String(format: "%.0f KB", value)
      } else {
        return String(format: "%.1f KB", value)
      }
    } else {
      return "\(self) B"
    }
  }
}


