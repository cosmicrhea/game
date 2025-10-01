import struct Foundation.URL
import class Foundation.Bundle

enum FontLibrary {
  private static let defaultFontsPath = "Fonts"

  struct ResolvedFont {
    let url: URL  // e.g. file:///Users/AlexCrawford/Applications/Glass.app/Contents/Resources/UI/Fonts/Orange%20Kid%20(13px).ttf
    let displayName: String  // e.g. "Orange Kid (13px)"
    let baseName: String  // e.g. "Orange Kid"
    let pixelSize: Int?  // e.g. 13
  }

  static var availableFonts: [ResolvedFont] {
    let extensions = ["ttf", "otf"]
    var entries: [ResolvedFont] = []

    for ext in extensions {
      let urls =
        Bundle.module.urls(forResourcesWithExtension: ext, subdirectory: defaultFontsPath) ?? []

      for url in urls {
        let name = url.deletingPathExtension().lastPathComponent
        let (base, size) = parseBaseAndSize(from: name)
        entries.append(ResolvedFont(url: url, displayName: name, baseName: base, pixelSize: size))
      }
    }

    return entries.sorted { $0.displayName > $1.displayName }
  }

  static func resolve(name: String) -> ResolvedFont? {
    let (requestedBase, requestedSize) = parseBaseAndSize(from: name)
    let matches = availableFonts.filter { $0.displayName == name || $0.baseName == requestedBase }
    if matches.isEmpty { return nil }

    if let size = requestedSize {
      let sized = matches.first(where: { $0.pixelSize == size })
      if let sized = sized { return sized }
    }

    // Prefer TTF if both TTF/OTF exist for the same base name
    if let preferred = matches.first(where: { $0.url.pathExtension.lowercased() == "ttf" }) {
      return preferred
    }
    return matches.first
  }

  private static func parseBaseAndSize(from displayName: String) -> (String, Int?) {
    // Matches: Name (13px)
    // Very lightweight parsing without regex dependency
    guard let open = displayName.lastIndex(of: "("),
      let close = displayName.lastIndex(of: ")"),
      open < close
    else {
      return (displayName, nil)
    }

    let sizePart = displayName[displayName.index(after: open)..<close]
    if sizePart.hasSuffix("px"), let num = Int(sizePart.dropLast(2)) {
      let base = displayName[..<displayName.index(before: open)].trimmingCharacters(
        in: .whitespaces)
      return (String(base), num)
    }
    return (displayName, nil)
  }
}
