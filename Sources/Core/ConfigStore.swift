import struct Foundation.Data
import class Foundation.FileManager
import class Foundation.JSONSerialization
import struct Foundation.URL

@MainActor
final class ConfigStore {
  static let shared = ConfigStore()

  private let configURL: URL
  private var store: [String: Any] = [:]

  init() {
    // Create Application Support directory path: ~/Library/Application Support/local.Glass/
    let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let appDirectory = appSupportURL.appendingPathComponent("local.Glass")

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
    return store[key] as? T ?? defaultValue
  }

  func set<T>(_ key: String, value: T) {
    store[key] = value
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
