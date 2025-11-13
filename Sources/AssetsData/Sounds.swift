// TODO: once miniaudio works, use positional `Sound` instead of UISound
extension UISound {

  static func handgunFire() { play("REWeapons/handgun_fire") }
  static func handgunEmpty() { play("REWeapons/handgun_empty") }
  static func handgunReload() { play("REWeapons/handgun_reload") }

  static func knifeSlash() { play("REWeapons/knife_slash") }
  static func knifeMiss() { play("REWeapons/knife_miss") }

  static func shotgunFire() { play("REWeapons/shotgun_fire") }
  static func shotgunEmpty() { play("REWeapons/handgun_empty") }
  static func shotgunReload() { play("REWeapons/shotgun_reload") }

  static func launcherFire() { play("REWeapons/grenade_launcher_fire") }
  static func launcherEmpty() { play("REWeapons/handgun_empty") }
  static func launcherReload() { play("REWeapons/grenade_launcher_reload") }

  static func grenadeHit() { play("REWeapons/grenade_hit") }

  static func lockedA() { play("RE/locked_a") }
  static func lockedB() { play("RE/locked_b") }

  static func doorOpenA() { play("RE/doors/re2_19_1") }
  static func doorCloseA() { play("RE/doors/re2_19_2") }

  static func footstep() { play("RE/footstep", volume: 0.7) }

}
