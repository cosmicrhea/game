import Foundation

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
    // Handle nested keys (e.g., "audio.uiVolume")
    let components = key.split(separator: ".", maxSplits: 1)
    if components.count == 2 {
      let group = String(components[0])
      let property = String(components[1])
      if let groupDict = store[group] as? [String: Any],
        let storedValue = groupDict[property]
      {
        // Handle RawRepresentable types with String rawValue (e.g., Color)
        if let stringValue = storedValue as? String,
          let colorValue = Color(rawValue: stringValue) as? T
        {
          return colorValue
        }
        return storedValue as? T ?? defaultValue
      }
      return defaultValue
    }

    // Handle flat keys
    if let storedValue = store[key] as? String {
      if let colorValue = Color(rawValue: storedValue) as? T {
        return colorValue
      }
    }
    return store[key] as? T ?? defaultValue
  }

  func set<T>(_ key: String, value: T) {
    // Handle nested keys (e.g., "audio.uiVolume")
    let components = key.split(separator: ".", maxSplits: 1)
    if components.count == 2 {
      let group = String(components[0])
      let property = String(components[1])

      // Get or create the group dictionary
      var groupDict = (store[group] as? [String: Any]) ?? [:]

      // Handle RawRepresentable types (e.g., Color) by storing their rawValue
      if let rawRepresentable = value as? any RawRepresentable,
        let rawValue = rawRepresentable.rawValue as? String
      {
        groupDict[property] = rawValue
      } else {
        groupDict[property] = value
      }

      store[group] = groupDict
      save()
      return
    }

    // Handle flat keys
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

/// A binding type that works with ConfigValue for two-way data binding.
/// Works with Swift 6's Observation framework.
public struct ConfigBinding<T> {
  private let getValue: () -> T
  private let setValue: (T) -> Void

  public var wrappedValue: T {
    get { getValue() }
    nonmutating set { setValue(newValue) }
  }

  public init(get: @escaping () -> T, set: @escaping (T) -> Void) {
    self.getValue = get
    self.setValue = set
  }
}

/// Macro that simplifies ConfigValue usage by automatically inferring the key from the property name.
/// Usage: `@ConfigValue var editorEnabled = false` or `@ConfigValue("customKey") var property = defaultValue`
/// or `@ConfigValue(group: "audio") var uiVolume: Float = 1.0`
/// If no key is provided, uses the property name as the key.
@attached(accessor)
public macro ConfigValue(_ key: String = "", group: String = "") =
  #externalMacro(module: "GameMacros", type: "ConfigMacro")
