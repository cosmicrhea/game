@MainActor
final class ConfigStore {
  static let shared = ConfigStore()

  private let configURL: URL
  private var store: [String: Any] = [:]

  init() {
    // Create Application Support directory path: ~/Library/Application Support/local.cosmicrhea.Game/
    let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let appDirectory = appSupportURL.appendingPathComponent("local.cosmicrhea.Game")

    // Ensure the directory exists
    try? FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)

    self.configURL = appDirectory.appendingPathComponent("config.json")
    load()
  }

  private func load() {
    guard let data = try? Data(contentsOf: configURL),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      store = [:]
      return
    }
    store = json
  }

  private func save() {
    guard let data = try? JSONSerialization.data(withJSONObject: store, options: [.prettyPrinted]) else { return }
    try? data.write(to: configURL)
  }

  func get<T>(_ key: String, default defaultValue: T) -> T {
    // Handle RawRepresentable types with String rawValue (e.g., Color)
    if let storedValue = store[key] as? String {
      if let colorValue = Color(rawValue: storedValue) as? T {
        return colorValue
      }
    }
    return store[key] as? T ?? defaultValue
  }

  func set<T>(_ key: String, value: T) {
    // Handle RawRepresentable types (e.g., Color) by storing their rawValue
    if let rawRepresentable = value as? any RawRepresentable,
      let rawValue = rawRepresentable.rawValue as? String
    {
      store[key] = rawValue
    } else {
      store[key] = value
    }
    save()
  }
}

@MainActor
@propertyWrapper
struct ConfigValue<T> {
  private let key: String
  private let defaultValue: T
  private let store: ConfigStore

  init(wrappedValue: T, _ key: String, store: ConfigStore = .shared) {
    self.key = key
    self.defaultValue = wrappedValue
    self.store = store
  }

  var wrappedValue: T {
    get { store.get(key, default: defaultValue) }
    set { store.set(key, value: newValue) }
  }
}

/// Macro that simplifies ConfigValue usage by automatically inferring the key from the property name.
/// Usage: `@ConfigValue var editorEnabled = false` or `@ConfigValue("customKey") var property = defaultValue`
/// If no key is provided, uses the property name as the key.
@attached(accessor)
@attached(peer)
public macro ConfigValue(_ key: String = "") = #externalMacro(module: "GameMacros", type: "ConfigMacro")
