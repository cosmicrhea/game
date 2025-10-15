import Foundation

/// A gradient defines a transition between colors over a range from 0.0 to 1.0.
/// The gradient can be drawn as either a linear or radial gradient.
public struct Gradient: Sendable, Equatable {
  /// A color stop in the gradient, consisting of a color and its location (0.0 to 1.0).
  public struct ColorStop: Sendable, Equatable {
    /// The color at this stop.
    public let color: Color
    /// The location of this stop (0.0 to 1.0).
    public let location: Float
    
    /// Creates a new color stop.
    /// - Parameters:
    ///   - color: The color at this stop.
    ///   - location: The location of this stop (0.0 to 1.0).
    public init(color: Color, location: Float) {
      self.color = color
      self.location = max(0.0, min(1.0, location)) // Clamp to valid range
    }
  }
  
  /// The color stops that define this gradient.
  public let colorStops: [ColorStop]
  
  /// Creates a gradient with the specified color stops.
  /// - Parameter colorStops: The color stops that define the gradient.
  public init(colorStops: [ColorStop]) {
    // Sort by location and ensure we have at least one stop
    let sortedStops = colorStops.sorted { $0.location < $1.location }
    self.colorStops = sortedStops.isEmpty ? [ColorStop(color: .white, location: 0.0)] : sortedStops
  }
  
  /// Creates a gradient with two colors at locations 0.0 and 1.0.
  /// - Parameters:
  ///   - startingColor: The color at location 0.0.
  ///   - endingColor: The color at location 1.0.
  public init(startingColor: Color, endingColor: Color) {
    self.colorStops = [
      ColorStop(color: startingColor, location: 0.0),
      ColorStop(color: endingColor, location: 1.0)
    ]
  }
  
  /// Creates a gradient with multiple colors distributed evenly from 0.0 to 1.0.
  /// - Parameter colors: The colors to use in the gradient.
  public init(colors: [Color]) {
    guard !colors.isEmpty else {
      self.colorStops = [ColorStop(color: .white, location: 0.0)]
      return
    }
    
    if colors.count == 1 {
      self.colorStops = [ColorStop(color: colors[0], location: 0.0)]
    } else {
      let step = 1.0 / Float(colors.count - 1)
      self.colorStops = colors.enumerated().map { index, color in
        ColorStop(color: color, location: Float(index) * step)
      }
    }
  }
  
  /// Creates a gradient with colors and their specific locations.
  /// - Parameters:
  ///   - colors: The colors to use in the gradient.
  ///   - locations: The locations for each color (0.0 to 1.0).
  public init(colors: [Color], locations: [Float]) {
    guard colors.count == locations.count && !colors.isEmpty else {
      self.colorStops = [ColorStop(color: .white, location: 0.0)]
      return
    }
    
    let stops = zip(colors, locations).map { color, location in
      ColorStop(color: color, location: location)
    }
    
    self.colorStops = stops.sorted { $0.location < $1.location }
  }
  
  /// Returns the interpolated color at the specified location.
  /// - Parameter location: The location to sample (0.0 to 1.0).
  /// - Returns: The interpolated color at that location.
  public func interpolatedColor(at location: Float) -> Color {
    let clampedLocation = max(0.0, min(1.0, location))
    
    // Handle edge cases
    if colorStops.count == 1 {
      return colorStops[0].color
    }
    
    // Find the two stops that bracket the location
    for i in 0..<(colorStops.count - 1) {
      let currentStop = colorStops[i]
      let nextStop = colorStops[i + 1]
      
      if clampedLocation >= currentStop.location && clampedLocation <= nextStop.location {
        // Interpolate between the two stops
        let t = (clampedLocation - currentStop.location) / (nextStop.location - currentStop.location)
        return interpolateColor(from: currentStop.color, to: nextStop.color, t: t)
      }
    }
    
    // If we're outside the range, return the closest stop
    if clampedLocation <= colorStops.first!.location {
      return colorStops.first!.color
    } else {
      return colorStops.last!.color
    }
  }
  
  /// The number of color stops in this gradient.
  public var numberOfColorStops: Int {
    return colorStops.count
  }
  
  /// Returns the color at the specified stop index.
  /// - Parameter index: The index of the color stop.
  /// - Returns: The color at that stop, or nil if the index is invalid.
  public func color(at index: Int) -> Color? {
    guard index >= 0 && index < colorStops.count else { return nil }
    return colorStops[index].color
  }
  
  /// Returns the location of the specified stop index.
  /// - Parameter index: The index of the color stop.
  /// - Returns: The location of that stop, or nil if the index is invalid.
  public func location(at index: Int) -> Float? {
    guard index >= 0 && index < colorStops.count else { return nil }
    return colorStops[index].location
  }
}

// MARK: - Color Interpolation

private func interpolateColor(from startColor: Color, to endColor: Color, t: Float) -> Color {
  let clampedT = max(0.0, min(1.0, t))
  
  return Color(
    red: startColor.red + (endColor.red - startColor.red) * clampedT,
    green: startColor.green + (endColor.green - startColor.green) * clampedT,
    blue: startColor.blue + (endColor.blue - startColor.blue) * clampedT,
    alpha: startColor.alpha + (endColor.alpha - startColor.alpha) * clampedT
  )
}

// MARK: - Convenience Initializers

extension Gradient {
  /// Creates a gradient with alternating colors and locations.
  /// - Parameter colorsAndLocations: Alternating color and location values, terminated by nil.
  public init(colorsAndLocations: (Color, Float)...) {
    var colors: [Color] = []
    var locations: [Float] = []
    
    for (color, location) in colorsAndLocations {
      colors.append(color)
      locations.append(location)
    }
    
    self.init(colors: colors, locations: locations)
  }
}

// MARK: - Predefined Gradients

extension Gradient {
  /// A gradient from black to white.
  public static let blackToWhite = Gradient(startingColor: .black, endingColor: .white)
  
  /// A gradient from white to black.
  public static let whiteToBlack = Gradient(startingColor: .white, endingColor: .black)
  
  /// A gradient from red to blue.
  public static let redToBlue = Gradient(startingColor: .red, endingColor: .blue)
  
  /// A gradient from blue to red.
  public static let blueToRed = Gradient(startingColor: .blue, endingColor: .red)
  
  /// A rainbow gradient with multiple colors.
  public static let rainbow = Gradient(colors: [
    .red,
    .orange,
    .yellow,
    .green,
    .blue,
    .purple
  ])
}



