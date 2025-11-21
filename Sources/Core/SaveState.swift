import struct Foundation.Date
import struct Foundation.TimeInterval

struct SaveState {
  static let numberOfSaveSlots = 16

  let slotIndex: Int
  var sceneName: String
  var cameraName: String
  var playerPosition: Vector3<Float>
  /// Euler angles in degrees for quick inspection (yaw, pitch, roll).
  var playerRotation: Vector3<Float>
  var totalPlaytime: TimeInterval
  var gameVersion: String
  var saveCount: Int
  var lastSavedAt: Date
  var isAutoSave: Bool
}

extension SaveState {
  static func demoSamples(referenceDate: Date = Date()) -> [SaveState] {
    let base = referenceDate
    return [
      SaveState(
        slotIndex: 0,
        sceneName: "Metro / Maintenance Room",
        cameraName: "Maintenance Elevator",
        playerPosition: Vector3<Float>(12.4, -3.1, 6.8),
        playerRotation: Vector3<Float>(0, 182, 0),
        totalPlaytime: 6 * 3600 + 28 * 60,
        gameVersion: "0.5.0-dev",
        saveCount: 0,
        lastSavedAt: base.addingTimeInterval(-120),
        isAutoSave: true
      ),
      SaveState(
        slotIndex: 1,
        sceneName: "Kastellet / Armory",
        cameraName: "Armory South Cam",
        playerPosition: Vector3<Float>(12.4, -3.1, 6.8),
        playerRotation: Vector3<Float>(0, 182, 0),
        totalPlaytime: 6 * 3600 + 25 * 60 + 18,
        gameVersion: "0.5.0-dev",
        saveCount: 63,
        lastSavedAt: base.addingTimeInterval(-180),
        isAutoSave: false
      ),
      SaveState(
        slotIndex: 2,
        sceneName: "Pharma Building / Break Room",
        cameraName: "BreakRoomCam_Front",
        playerPosition: Vector3<Float>(4.2, -1.9, -2.7),
        playerRotation: Vector3<Float>(12, 145, 0),
        totalPlaytime: 3 * 3600 + 42 * 60 + 5,
        gameVersion: "0.5.0-dev",
        saveCount: 18,
        lastSavedAt: base.addingTimeInterval(-3600 * 4 - 720),
        isAutoSave: false
      ),
      SaveState(
        slotIndex: 3,
        sceneName: "Downtown / Marmorkirken",
        cameraName: "HelipadCam_Pan",
        playerPosition: Vector3<Float>(-18.2, 7.5, 3.4),
        playerRotation: Vector3<Float>(0, 90, 0),
        totalPlaytime: 1 * 3600 + 5 * 60 + 12,
        gameVersion: "0.5.0-dev",
        saveCount: 4,
        lastSavedAt: base.addingTimeInterval(-3600 * 24),
        isAutoSave: false
      ),
    ]
  }
}
