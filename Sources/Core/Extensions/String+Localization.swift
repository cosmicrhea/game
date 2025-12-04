extension Locale {
  /// The game's active locale. Uses the user's display language preference if set,
  /// otherwise falls back to the system locale.
  @MainActor
  public static var game: Locale {
    Locale(identifier: Config.current.displayLocaleIdentifier)
  }
}

extension Bundle {
  /// Returns a localized string for the specified key and table, using the game's active locale.
  /// This method loads the locale-specific .lproj bundle to ensure proper localization.
  @MainActor
  public func localizedString(forKey key: String, value: String? = nil, table: String? = nil, locale: Locale? = nil)
    -> String
  {
    let effectiveLocale = locale ?? .game
    let localeIdentifier = effectiveLocale.identifier

    // Get language code using the modern API (macOS 13+)
    let languageCode: String
    if #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) {
      languageCode =
        effectiveLocale.language.languageCode?.identifier ?? localeIdentifier.components(separatedBy: "_").first
        ?? localeIdentifier.components(separatedBy: "-").first ?? localeIdentifier
    } else {
      // Fallback for older systems
      languageCode =
        effectiveLocale.languageCode ?? localeIdentifier.components(separatedBy: "_").first
        ?? localeIdentifier.components(separatedBy: "-").first ?? localeIdentifier
    }

    // Try full identifier first, then language code
    let bundlePath =
      self.path(forResource: localeIdentifier, ofType: "lproj")
      ?? self.path(forResource: languageCode, ofType: "lproj")

    if let bundlePath = bundlePath,
      let localeBundle = Bundle(path: bundlePath)
    {
      return localeBundle.localizedString(forKey: key, value: value, table: table)
    } else {
      // Fallback to default bundle if locale-specific bundle not found
      return self.localizedString(forKey: key, value: value, table: table)
    }
  }
}

extension String {
  @MainActor
  init(gameLocalized: LocalizedStringResource) {
    self = Bundle.game.localizedString(forKey: gameLocalized.key, locale: .game)
  }
}

extension String {
  /// Localized string initializer that respects the user's display language preference.
  /// If no locale is provided, uses the game locale (user preference or system default).
  @MainActor
  init(
    localized key: StaticString, defaultValue: String.LocalizationValue, table: String? = nil,
    locale: Locale? = nil, comment: StaticString? = nil
  ) {
    let effectiveLocale = locale ?? .game
    self.init(
      localized: key, defaultValue: defaultValue, table: table, bundle: .game, locale: effectiveLocale, comment: comment
    )
  }
}

extension LocalizedStringResource: @retroactive Hashable {
  public func hash(into hasher: inout Hasher) {
    key.hash(into: &hasher)
  }
}
