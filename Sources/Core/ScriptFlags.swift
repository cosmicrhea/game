@MainActor
final class ScriptFlagStore {
  private var storage: [String: StoredValue] = [:]

  func set<Value: ScriptFlagValue>(_ value: Value, forKey key: String) {
    storage[key] = value.flagStoredValue
  }

  func value<Value: ScriptFlagValue>(forKey key: String, default defaultValue: Value) -> Value {
    guard let stored = storage[key], let decoded = Value(flagStoredValue: stored) else {
      return defaultValue
    }
    return decoded
  }

  func containsValue(forKey key: String) -> Bool {
    return storage[key] != nil
  }

  func removeValue(forKey key: String) {
    storage.removeValue(forKey: key)
  }

  func allFlags() -> [String: StoredValue] {
    return storage
  }
}

extension ScriptFlagStore {
  enum StoredValue: Codable {
    case bool(Bool)
    case int(Int)
    case float(Float)
    case string(String)

    private enum CodingKeys: String, CodingKey {
      case type
      case bool
      case int
      case float
      case string
    }

    private enum ValueType: String, Codable {
      case bool
      case int
      case float
      case string
    }

    func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      switch self {
      case .bool(let value):
        try container.encode(ValueType.bool, forKey: .type)
        try container.encode(value, forKey: .bool)
      case .int(let value):
        try container.encode(ValueType.int, forKey: .type)
        try container.encode(value, forKey: .int)
      case .float(let value):
        try container.encode(ValueType.float, forKey: .type)
        try container.encode(value, forKey: .float)
      case .string(let value):
        try container.encode(ValueType.string, forKey: .type)
        try container.encode(value, forKey: .string)
      }
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      let type = try container.decode(ValueType.self, forKey: .type)
      switch type {
      case .bool:
        let value = try container.decode(Bool.self, forKey: .bool)
        self = .bool(value)
      case .int:
        let value = try container.decode(Int.self, forKey: .int)
        self = .int(value)
      case .float:
        let value = try container.decode(Float.self, forKey: .float)
        self = .float(value)
      case .string:
        let value = try container.decode(String.self, forKey: .string)
        self = .string(value)
      }
    }
  }
}

protocol ScriptFlagValue {
  init?(flagStoredValue: ScriptFlagStore.StoredValue)
  var flagStoredValue: ScriptFlagStore.StoredValue { get }
}

extension Bool: ScriptFlagValue {
  init?(flagStoredValue: ScriptFlagStore.StoredValue) {
    guard case let .bool(value) = flagStoredValue else { return nil }
    self = value
  }

  var flagStoredValue: ScriptFlagStore.StoredValue { .bool(self) }
}

extension Int: ScriptFlagValue {
  init?(flagStoredValue: ScriptFlagStore.StoredValue) {
    guard case let .int(value) = flagStoredValue else { return nil }
    self = value
  }

  var flagStoredValue: ScriptFlagStore.StoredValue { .int(self) }
}

extension Float: ScriptFlagValue {
  init?(flagStoredValue: ScriptFlagStore.StoredValue) {
    guard case let .float(value) = flagStoredValue else { return nil }
    self = value
  }

  var flagStoredValue: ScriptFlagStore.StoredValue { .float(self) }
}

extension String: ScriptFlagValue {
  init?(flagStoredValue: ScriptFlagStore.StoredValue) {
    guard case let .string(value) = flagStoredValue else { return nil }
    self = value
  }

  var flagStoredValue: ScriptFlagStore.StoredValue { .string(self) }
}

@propertyWrapper
struct ScriptFlagStorage<Value: ScriptFlagValue> {
  private let name: String
  private let defaultValue: Value

  init(name: String, default defaultValue: Value) {
    self.name = name
    self.defaultValue = defaultValue
  }

  @available(*, unavailable, message: "ScriptFlagStorage can only be used on Script subclasses.")
  var wrappedValue: Value {
    get { fatalError("ScriptFlagStorage can only be used on Script subclasses.") }
    set { fatalError("ScriptFlagStorage can only be used on Script subclasses.") }
  }

  @MainActor static subscript(
    _enclosingInstance instance: Script,
    wrapped wrappedKeyPath: ReferenceWritableKeyPath<Script, Value>,
    storage storageKeyPath: ReferenceWritableKeyPath<Script, ScriptFlagStorage>
  ) -> Value {
    get {
      let storage = instance[keyPath: storageKeyPath]
      return instance.readFlag(storage.name, default: storage.defaultValue)
    }
    set {
      let storage = instance[keyPath: storageKeyPath]
      instance.writeFlag(newValue, name: storage.name)
    }
  }
}

