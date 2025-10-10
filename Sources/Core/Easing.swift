import Foundation

enum Easing {
  case linear
  case easeIn
  case easeOut
  case easeInOut
  case easeInQuad
  case easeOutQuad
  case easeInOutQuad
  case easeInCubic
  case easeOutCubic
  case easeInOutCubic
  case easeInCirc
  case easeOutCirc
  case easeInOutCirc

  func apply(_ t: Float) -> Float {
    switch self {
    case .linear:
      return t
    case .easeIn:
      return t * t
    case .easeOut:
      let oneMinusT = 1.0 - t
      return 1.0 - oneMinusT * oneMinusT
    case .easeInOut:
      if t < 0.5 {
        return 2.0 * t * t
      } else {
        let twoTMinusTwo = -2.0 * t + 2.0
        return 1.0 - twoTMinusTwo * twoTMinusTwo / 2.0
      }
    case .easeInQuad:
      return t * t
    case .easeOutQuad:
      let oneMinusT = 1.0 - t
      return 1.0 - oneMinusT * oneMinusT
    case .easeInOutQuad:
      if t < 0.5 {
        return 2.0 * t * t
      } else {
        let twoTMinusTwo = -2.0 * t + 2.0
        return 1.0 - twoTMinusTwo * twoTMinusTwo / 2.0
      }
    case .easeInCubic:
      return t * t * t
    case .easeOutCubic:
      let oneMinusT = 1.0 - t
      return 1.0 - oneMinusT * oneMinusT * oneMinusT
    case .easeInOutCubic:
      if t < 0.5 {
        return 4.0 * t * t * t
      } else {
        let twoTMinusTwo = -2.0 * t + 2.0
        return 1.0 - twoTMinusTwo * twoTMinusTwo * twoTMinusTwo / 2.0
      }
    case .easeInCirc:
      let tSquared = t * t
      return 1.0 - sqrt(1.0 - tSquared)
    case .easeOutCirc:
      let tMinusOne = t - 1.0
      return sqrt(1.0 - tMinusOne * tMinusOne)
    case .easeInOutCirc:
      if t < 0.5 {
        let twoT = 2.0 * t
        let twoTSquared = twoT * twoT
        return (1.0 - sqrt(1.0 - twoTSquared)) / 2.0
      } else {
        let twoTMinusTwo = -2.0 * t + 2.0
        let twoTMinusTwoSquared = twoTMinusTwo * twoTMinusTwo
        return (sqrt(1.0 - twoTMinusTwoSquared) + 1.0) / 2.0
      }
    }
  }
}
