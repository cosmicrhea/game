import Foundation

/// Registry for scene script classes, allowing dynamic class loading
@MainActor
final class ScriptRegistry {
  static let shared = ScriptRegistry()

  private var factories: [String: () -> Script] = [:]

  private init() {}

  /// Register a scene script class factory
  func register(_ className: String, factory: @escaping () -> Script) {
    factories[className] = factory
  }

  /// Create an instance of a scene script class by name
  /// Returns nil if not registered (should be registered via registerAllSceneScripts())
  func create(_ className: String) -> Script? {
    // If registered, use the factory
    if let factory = factories[className] {
      return factory()
    }

    logger.warning("⚠️ Class \(className) not registered. Call registerAllSceneScripts() first.")
    return nil
  }

  /// Check if a class is registered
  func isRegistered(_ className: String) -> Bool {
    return factories[className] != nil
  }

  /// Get all registered class names
  func allRegisteredClasses() -> [String] {
    return Array(factories.keys)
  }
}
